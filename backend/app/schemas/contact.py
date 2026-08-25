import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, EmailStr, Field


class ContactBase(BaseModel):
    name: str = Field(min_length=1, max_length=255)
    title: str | None = Field(default=None, max_length=255)
    email: EmailStr | None = None
    linkedin_url: str | None = Field(default=None, max_length=500)


class ContactCreate(ContactBase):
    pass


class ContactUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=255)
    title: str | None = Field(default=None, max_length=255)
    email: EmailStr | None = None
    linkedin_url: str | None = Field(default=None, max_length=500)


class ContactRead(ContactBase):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    created_at: datetime
    updated_at: datetime
    # No application_id - a contact is a standalone, user-owned resource
    # that can be attached to zero, one, or several applications (see
    # ApplicationContact). Which applications it's attached to is read via
    # GET /applications/{application_id}/contacts, not from this shape.


class ContactListResponse(BaseModel):
    items: list[ContactRead]
    total: int
    page: int
    page_size: int


# --- Application <-> Contact attachment ------------------------------------
# Supports POST/GET/DELETE /applications/{application_id}/contacts (see
# app/api/v1/endpoints/application_contacts.py). Attaching only ever links
# an existing, already-owned contact - creating a new contact is always
# done standalone via POST /contacts.


class ApplicationContactCreate(BaseModel):
    contact_id: uuid.UUID
