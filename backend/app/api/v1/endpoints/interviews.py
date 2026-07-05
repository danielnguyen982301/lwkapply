"""
Interview endpoints, nested under an application: an interview only
ever exists in the context of one application, so routes are scoped
that way (mirrors the Interview -> Application -> User ownership chain
in docs/ARCHITECTURE.md).

Ownership is enforced with a single join from Interview through
Application to the current user - same IDOR-prevention approach as
applications.py, just one hop further out.
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.application import Application
from app.models.interview import Interview
from app.models.user import User
from app.schemas.interview import (
    InterviewCreate,
    InterviewListResponse,
    InterviewRead,
    InterviewUpdate,
)

router = APIRouter()


def _get_owned_application(
    db: Session, application_id: uuid.UUID, user: User
) -> Application:
    application = (
        db.query(Application)
        .filter(Application.id == application_id, Application.user_id == user.id)
        .first()
    )
    if not application:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Application not found"
        )
    return application


def _get_owned_interview(
    db: Session, application_id: uuid.UUID, interview_id: uuid.UUID, user: User
) -> Interview:
    interview = (
        db.query(Interview)
        .join(Application, Interview.application_id == Application.id)
        .filter(
            Interview.id == interview_id,
            Interview.application_id == application_id,
            Application.user_id == user.id,
        )
        .first()
    )
    if not interview:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Interview not found"
        )
    return interview


@router.get("", response_model=InterviewListResponse)
def list_interviews(
    application_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _get_owned_application(db, application_id, current_user)
    items = (
        db.query(Interview)
        .filter(Interview.application_id == application_id)
        .order_by(Interview.scheduled_at.asc())
        .all()
    )
    return InterviewListResponse(
        items=[InterviewRead.model_validate(item) for item in items],
        total=len(items),
    )


@router.post("", response_model=InterviewRead, status_code=status.HTTP_201_CREATED)
def create_interview(
    application_id: uuid.UUID,
    payload: InterviewCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _get_owned_application(db, application_id, current_user)
    interview = Interview(**payload.model_dump(), application_id=application_id)
    db.add(interview)
    db.commit()
    db.refresh(interview)
    return interview


@router.get("/{interview_id}", response_model=InterviewRead)
def get_interview(
    application_id: uuid.UUID,
    interview_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return _get_owned_interview(db, application_id, interview_id, current_user)


@router.patch("/{interview_id}", response_model=InterviewRead)
def update_interview(
    application_id: uuid.UUID,
    interview_id: uuid.UUID,
    payload: InterviewUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    interview = _get_owned_interview(db, application_id, interview_id, current_user)
    updates = payload.model_dump(exclude_unset=True)
    for field, value in updates.items():
        setattr(interview, field, value)

    db.add(interview)
    db.commit()
    db.refresh(interview)
    return interview


@router.delete("/{interview_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_interview(
    application_id: uuid.UUID,
    interview_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    interview = _get_owned_interview(db, application_id, interview_id, current_user)
    db.delete(interview)
    db.commit()
    return None
