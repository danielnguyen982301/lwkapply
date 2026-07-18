"""
Contact endpoints.

`router` holds CRUD, nested under an application - same ownership-chain
reasoning as interviews.py (Contact -> Application -> User). Registered in
router.py under /applications/{application_id}/contacts.

`directory_router` holds one read-only route: GET /contacts, a flat listing
across every application the user owns (the "Contacts" nav item, which
shows all contacts with the company/position they belong to). A contact
still only ever exists nested under one application - this doesn't change
ownership or add a new way to create one, it's just a different read path
over the same rows, scoped via the same Application.user_id join the nested
routes already use for ownership checks. Registered in router.py under the
top-level /contacts prefix (no application_id path param).
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import or_
from sqlalchemy.orm import Session, contains_eager

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.application import Application
from app.models.contact import Contact
from app.models.user import User
from app.schemas.contact import (
    ContactCreate,
    ContactListResponse,
    ContactRead,
    ContactUpdate,
    ContactWithApplicationListResponse,
    ContactWithApplicationRead,
)

router = APIRouter()
directory_router = APIRouter()


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


def _get_owned_contact(
    db: Session, application_id: uuid.UUID, contact_id: uuid.UUID, user: User
) -> Contact:
    contact = (
        db.query(Contact)
        .join(Application, Contact.application_id == Application.id)
        .filter(
            Contact.id == contact_id,
            Contact.application_id == application_id,
            Application.user_id == user.id,
        )
        .first()
    )
    if not contact:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Contact not found"
        )
    return contact


@router.get("", response_model=ContactListResponse)
def list_contacts(
    application_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _get_owned_application(db, application_id, current_user)
    items = (
        db.query(Contact)
        .filter(Contact.application_id == application_id)
        .order_by(Contact.created_at.desc())
        .all()
    )
    return ContactListResponse(
        items=[ContactRead.model_validate(item) for item in items],
        total=len(items),
    )


@router.post("", response_model=ContactRead, status_code=status.HTTP_201_CREATED)
def create_contact(
    application_id: uuid.UUID,
    payload: ContactCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _get_owned_application(db, application_id, current_user)
    contact = Contact(**payload.model_dump(), application_id=application_id)
    db.add(contact)
    db.commit()
    db.refresh(contact)
    return contact


@router.get("/{contact_id}", response_model=ContactRead)
def get_contact(
    application_id: uuid.UUID,
    contact_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return _get_owned_contact(db, application_id, contact_id, current_user)


@router.patch("/{contact_id}", response_model=ContactRead)
def update_contact(
    application_id: uuid.UUID,
    contact_id: uuid.UUID,
    payload: ContactUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    contact = _get_owned_contact(db, application_id, contact_id, current_user)
    updates = payload.model_dump(exclude_unset=True)
    for field, value in updates.items():
        setattr(contact, field, value)

    db.add(contact)
    db.commit()
    db.refresh(contact)
    return contact


@router.delete("/{contact_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_contact(
    application_id: uuid.UUID,
    contact_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    contact = _get_owned_contact(db, application_id, contact_id, current_user)
    db.delete(contact)
    db.commit()
    return None


@directory_router.get("", response_model=ContactWithApplicationListResponse)
def list_all_contacts(
    search: str | None = None,
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # Same join Application already used for ownership on every nested
    # route above (Contact -> Application -> User) - just not scoped down
    # to one application_id here. `contains_eager` reuses this join to
    # populate `Contact.application` instead of firing a second query per
    # row; it relies on the join/filter below being the exact source of
    # that relationship's rows, so don't reorder without care.
    query = (
        db.query(Contact)
        .join(Application, Contact.application_id == Application.id)
        .options(contains_eager(Contact.application))
        .filter(Application.user_id == current_user.id)
    )

    if search:
        like = f"%{search}%"
        query = query.filter(
            or_(Contact.name.ilike(like), Application.company.ilike(like))
        )

    total = query.count()
    items = (
        query.order_by(Contact.created_at.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
        .all()
    )
    return ContactWithApplicationListResponse(
        items=[ContactWithApplicationRead.model_validate(item) for item in items],
        total=total,
        page=page,
        page_size=page_size,
    )
