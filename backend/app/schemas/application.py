import uuid
from datetime import date, datetime

from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.models.application import ApplicationStatus


class SalaryRangeValidationMixin(BaseModel):
    """Shared cross-field validation for salary_min/salary_max.

    Used by both ApplicationBase (-> ApplicationCreate) and
    ApplicationUpdate: a PATCH that sets salary_min > salary_max needs to
    be rejected the same way a POST would be. Previously this validator
    only lived on ApplicationBase, so ApplicationUpdate (a separate
    BaseModel, not a subclass) silently accepted an inverted range.

    Note this only catches the case where a single request sets both
    fields inconsistently. A PATCH that sets only salary_min, leaving an
    already-inverted salary_max untouched from a prior state, can't be
    caught at the schema layer alone - that would need to compare against
    the stored row in the endpoint itself. Flagging this rather than
    silently treating the mixin as a complete fix.
    """

    salary_min: int | None = Field(default=None, ge=0)
    salary_max: int | None = Field(default=None, ge=0)

    @model_validator(mode="after")
    def validate_salary_range(self):
        if self.salary_min is not None and self.salary_max is not None:
            if self.salary_min > self.salary_max:
                raise ValueError("salary_min cannot be greater than salary_max")
        return self


class ApplicationBase(SalaryRangeValidationMixin):
    company: str = Field(min_length=1, max_length=255)
    position: str = Field(min_length=1, max_length=255)
    location: str | None = Field(default=None, max_length=255)
    status: ApplicationStatus = ApplicationStatus.SAVED
    applied_date: date | None = None
    job_url: str | None = Field(default=None, max_length=1000)
    notes: str | None = None


class ApplicationCreate(ApplicationBase):
    pass


class ApplicationUpdate(SalaryRangeValidationMixin):
    company: str | None = Field(default=None, min_length=1, max_length=255)
    position: str | None = Field(default=None, min_length=1, max_length=255)
    location: str | None = Field(default=None, max_length=255)
    status: ApplicationStatus | None = None
    applied_date: date | None = None
    job_url: str | None = Field(default=None, max_length=1000)
    notes: str | None = None


class ApplicationRead(ApplicationBase):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    user_id: uuid.UUID
    created_at: datetime
    updated_at: datetime


class ApplicationListResponse(BaseModel):
    items: list[ApplicationRead]
    total: int
    page: int
    page_size: int
