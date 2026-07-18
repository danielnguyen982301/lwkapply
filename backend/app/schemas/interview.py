import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

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
