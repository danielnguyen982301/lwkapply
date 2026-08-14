"""
Interview endpoints.

`router` holds CRUD, nested under an application: an interview only
ever exists in the context of one application, so routes are scoped
that way (mirrors the Interview -> Application -> User ownership chain
in docs/ARCHITECTURE.md). Ownership is enforced with a single join from
Interview through Application to the current user - same IDOR-prevention
approach as applications.py, just one hop further out.

`directory_router` holds one read-only route: GET /interviews, a flat
listing across every application the user owns (mirrors contacts.py's
directory_router / GET /contacts). An interview still only ever exists
nested under one application - this doesn't change ownership or add a
new way to create one, it's just a different read path over the same
rows, scoped via the same Application.user_id join the nested routes
already use for ownership checks. Registered in router.py under the
top-level /interviews prefix.
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session, contains_eager

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.application import Application
from app.models.interview import Interview, InterviewResult
from app.models.user import User
from app.schemas.interview import (
    InterviewCreate,
    InterviewListResponse,
    InterviewRead,
    InterviewUpdate,
    InterviewWithApplicationListResponse,
    InterviewWithApplicationRead,
)
from app.services.reminders import sync_interview_reminders

router = APIRouter()
directory_router = APIRouter()


def _get_owned_application(
    db: Session, application_id: uuid.UUID, user: User
) -> Application:
    application = (
        db.execute(
            select(Application).where(
                Application.id == application_id, Application.user_id == user.id
            )
        )
        .scalars()
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
        db.execute(
            select(Interview)
            .join(Application, Interview.application_id == Application.id)
            .where(
                Interview.id == interview_id,
                Interview.application_id == application_id,
                Application.user_id == user.id,
            )
        )
        .scalars()
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
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
):
    _get_owned_application(db, application_id, current_user)
    # Built without order_by/offset/limit - reused as-is for the count
    # below (via .subquery()) and extended with those three only for the
    # items fetch.
    stmt = select(Interview).where(Interview.application_id == application_id)

    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    items = (
        db.execute(
            stmt.order_by(Interview.scheduled_at.asc())
            .offset((page - 1) * page_size)
            .limit(page_size)
        )
        .scalars()
        .all()
    )

    return InterviewListResponse(
        items=[InterviewRead.model_validate(item) for item in items],
        total=total,
        page=page,
        page_size=page_size,
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

    # Needs interview.id, hence the separate commit above rather than
    # folding into the same one - see app/services/reminders.py.
    sync_interview_reminders(db, interview)
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

    # Re-sync whenever scheduled_at or result may have changed - cheap to
    # call unconditionally rather than diffing `updates` for the two
    # fields that matter, and correctness doesn't depend on which fields
    # were actually in the PATCH body.
    sync_interview_reminders(db, interview)
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


@directory_router.get("", response_model=InterviewWithApplicationListResponse)
def list_all_interviews(
    result: InterviewResult | None = None,
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # Same join Application already used for ownership on every nested
    # route above (Interview -> Application -> User) - just not scoped
    # down to one application_id here. `contains_eager` reuses this join
    # to populate `Interview.application` instead of firing a second
    # query per row; it relies on the join/filter below being the exact
    # source of that relationship's rows, so don't reorder without care.
    #
    # Built without order_by/offset/limit - reused as-is for the count
    # below (via .subquery()) and extended with those three only for the
    # items fetch.
    stmt = (
        select(Interview)
        .join(Application, Interview.application_id == Application.id)
        .options(contains_eager(Interview.application))
        .where(Application.user_id == current_user.id)
    )

    if result:
        stmt = stmt.where(Interview.result == result)

    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    items = (
        db.execute(
            stmt.order_by(Interview.scheduled_at.asc())
            .offset((page - 1) * page_size)
            .limit(page_size)
        )
        .scalars()
        .all()
    )
    return InterviewWithApplicationListResponse(
        items=[InterviewWithApplicationRead.model_validate(item) for item in items],
        total=total,
        page=page,
        page_size=page_size,
    )
