"""
Contact endpoints - top-level, user-owned resource (like Application),
mounted at /contacts. A contact is no longer created in the context of
one application: it's created standalone here, then optionally attached
to any number of applications via
app/api/v1/endpoints/application_contacts.py (mounted at
/applications/{application_id}/contacts). See app/models/contact.py's
module docstring for the ownership rationale.
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.contact import Contact
from app.models.user import User
from app.schemas.contact import (
    ContactCreate,
    ContactListResponse,
    ContactRead,
    ContactUpdate,
)

router = APIRouter()


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
def list_contacts(
    search: str | None = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
):
    # Built without order_by/offset/limit - reused as-is for the count
    # below (via .subquery()) and extended with those three only for the
    # items fetch.
    stmt = select(Contact).where(Contact.user_id == current_user.id)

    if search:
        stmt = stmt.where(Contact.name.ilike(f"%{search}%"))

    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    items = (
        db.execute(
            stmt.order_by(Contact.created_at.desc())
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
def create_contact(
    payload: ContactCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    contact = Contact(**payload.model_dump(), user_id=current_user.id)
    db.add(contact)
    db.commit()
    db.refresh(contact)
    return contact


@router.get("/{contact_id}", response_model=ContactRead)
def get_contact(
    contact_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return _get_owned_contact(db, contact_id, current_user)


@router.patch("/{contact_id}", response_model=ContactRead)
def update_contact(
    contact_id: uuid.UUID,
    payload: ContactUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    contact = _get_owned_contact(db, contact_id, current_user)
    updates = payload.model_dump(exclude_unset=True)
    for field, value in updates.items():
        setattr(contact, field, value)

    db.add(contact)
    db.commit()
    db.refresh(contact)
    return contact


@router.delete("/{contact_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_contact(
    contact_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    contact = _get_owned_contact(db, contact_id, current_user)
    db.delete(contact)
    db.commit()
    return None
