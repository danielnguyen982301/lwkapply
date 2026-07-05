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
    application_id: uuid.UUID
    created_at: datetime
    updated_at: datetime


class ContactListResponse(BaseModel):
    items: list[ContactRead]
    total: int
