import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, EmailStr, Field

from app.models.application import ApplicationStatus


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
    application_id: uuid.UUID
    created_at: datetime
    updated_at: datetime


class ContactListResponse(BaseModel):
    items: list[ContactRead]
    total: int


# --- Cross-application contact directory ---------------------------------
# Everything below supports GET /contacts (app/api/v1/endpoints/contacts.py
# :: directory_router), the flat "all my contacts" listing used by the
# Contacts nav item. It's the only place a Contact is represented alongside
# its parent Application, so those fields live here rather than on
# ContactRead itself, which every nested (single-application-scoped)
# response still uses unchanged.


class ApplicationSummary(BaseModel):
    """Minimal parent-application context for a contact in the directory view."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    company: str
    position: str
    status: ApplicationStatus


class ContactWithApplicationRead(ContactRead):
    application: ApplicationSummary


class ContactWithApplicationListResponse(BaseModel):
    items: list[ContactWithApplicationRead]
    total: int
    page: int
    page_size: int
