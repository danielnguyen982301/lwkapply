"""
Attach/detach endpoints linking a Contact to an Application - mounted at
/applications/{application_id}/contacts (app/api/v1/router.py). A
contact is created standalone via POST /contacts
(app/api/v1/endpoints/contacts.py) and attached here afterward; detaching
only removes the link (ApplicationContact row), it never deletes the
contact itself - see app/models/application_contact.py.
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.application import Application
from app.models.application_contact import ApplicationContact
from app.models.contact import Contact
from app.models.user import User
from app.schemas.contact import (
    ApplicationContactCreate,
    ContactListResponse,
    ContactRead,
)

router = APIRouter()


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


def _get_owned_contact(db: Session, contact_id: uuid.UUID, user: User) -> Contact:
    contact = (
        db.execute(
            select(Contact).where(Contact.id == contact_id, Contact.user_id == user.id)
        )
        .scalars()
        .first()
    )
    if not contact:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Contact not found"
        )
    return contact


@router.get("", response_model=ContactListResponse)
def list_attached_contacts(
    application_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
):
    _get_owned_application(db, application_id, current_user)

    stmt = (
        select(Contact)
        .join(ApplicationContact, ApplicationContact.contact_id == Contact.id)
        .where(ApplicationContact.application_id == application_id)
    )

    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    items = (
        db.execute(
            stmt.order_by(ApplicationContact.created_at.desc())
            .offset((page - 1) * page_size)
            .limit(page_size)
        )
        .scalars()
        .all()
    )

    return ContactListResponse(
        items=[ContactRead.model_validate(item) for item in items],
        total=total,
        page=page,
        page_size=page_size,
    )


@router.post("", response_model=ContactRead, status_code=status.HTTP_201_CREATED)
def attach_contact(
    application_id: uuid.UUID,
    payload: ApplicationContactCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    application = _get_owned_application(db, application_id, current_user)
    contact = _get_owned_contact(db, payload.contact_id, current_user)

    existing = (
        db.execute(
            select(ApplicationContact).where(
                ApplicationContact.application_id == application.id,
                ApplicationContact.contact_id == contact.id,
            )
        )
        .scalars()
        .first()
    )
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This contact is already attached to this application.",
        )

    link = ApplicationContact(application_id=application.id, contact_id=contact.id)
    db.add(link)
    db.commit()
    db.refresh(contact)
    return contact


@router.delete("/{contact_id}", status_code=status.HTTP_204_NO_CONTENT)
def detach_contact(
    application_id: uuid.UUID,
    contact_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _get_owned_application(db, application_id, current_user)

    link = (
        db.execute(
            select(ApplicationContact).where(
                ApplicationContact.application_id == application_id,
                ApplicationContact.contact_id == contact_id,
            )
        )
        .scalars()
        .first()
    )
    if not link:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="This contact isn't attached to this application.",
        )

    db.delete(link)
    db.commit()
    return None
