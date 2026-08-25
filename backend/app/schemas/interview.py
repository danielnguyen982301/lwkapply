import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

from app.models.application import ApplicationStatus
from app.models.interview import InterviewResult, InterviewType


class InterviewBase(BaseModel):
    type: InterviewType
    scheduled_at: datetime
    duration_minutes: int | None = Field(default=None, ge=1, le=1440)
    feedback: str | None = None
    result: InterviewResult = InterviewResult.PENDING


class InterviewCreate(InterviewBase):
    pass


class InterviewUpdate(BaseModel):
    type: InterviewType | None = None
    scheduled_at: datetime | None = None
    duration_minutes: int | None = Field(default=None, ge=1, le=1440)
    feedback: str | None = None
    result: InterviewResult | None = None


class InterviewRead(InterviewBase):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    application_id: uuid.UUID
    created_at: datetime
    updated_at: datetime


class InterviewListResponse(BaseModel):
    items: list[InterviewRead]
    total: int
    page: int
    page_size: int


# --- Cross-application interview directory --------------------------------
# Everything below supports GET /interviews
# (app/api/v1/endpoints/interviews.py :: directory_router), the flat "all my
# interviews" listing. Interview is still nested-only (an interview only
# ever exists in the context of one application), unlike Contact/Document,
# which are now top-level resources reusable across applications - see
# app/models/contact.py's module docstring for why that pair doesn't need
# this ApplicationSummary-embedding pattern any more.


class ApplicationSummary(BaseModel):
    """Minimal parent-application context for an interview in the directory view."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    company: str
    position: str
    application_name: str | None
    status: ApplicationStatus


class InterviewWithApplicationRead(InterviewRead):
    application: ApplicationSummary


class InterviewWithApplicationListResponse(BaseModel):
    items: list[InterviewWithApplicationRead]
    total: int
    page: int
    page_size: int
