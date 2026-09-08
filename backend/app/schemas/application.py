import uuid
from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.models.application import ApplicationStatus, SalaryCurrency


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
    application_name: str | None = Field(default=None, max_length=255)
    location: str | None = Field(default=None, max_length=255)
    status: ApplicationStatus = ApplicationStatus.SAVED
    salary_currency: SalaryCurrency = SalaryCurrency.USD
    applied_date: date | None = None
    job_url: str | None = Field(default=None, max_length=1000)
    notes: str | None = None
    source: str | None = Field(default=None, max_length=100)
    external_id: str | None = Field(default=None, max_length=255)


class ApplicationCreate(ApplicationBase):
    pass


class ApplicationUpsertByExternalId(ApplicationCreate):
    """Body for PUT/PATCH /applications/by-external-id - identical to
    ApplicationCreate, except source/external_id (optional there, since
    a plain manual create leaves both null) are required here, since
    identifying which row to find-or-create is the entire point of this
    endpoint. `status` is accepted but ignored - both endpoints decide
    the row's status themselves (see applications.py).

    Enforced via a validator rather than re-declaring source/external_id
    with a narrower (non-Optional) type: a subclass narrowing an
    inherited *mutable* attribute's type is a real type-safety hole
    (nothing stops code that only knows about ApplicationBase from
    assigning None to it on an instance of this subclass) that pyright
    correctly flags as reportIncompatibleVariableOverride - this keeps
    the inherited annotation as-is and rejects None at the validation
    layer instead, where "required" actually belongs.
    """

    @model_validator(mode="after")
    def require_source_and_external_id(self):
        if not self.source or not self.external_id:
            raise ValueError("source and external_id are required")
        return self


class ApplicationUpdate(SalaryRangeValidationMixin):
    company: str | None = Field(default=None, min_length=1, max_length=255)
    position: str | None = Field(default=None, min_length=1, max_length=255)
    application_name: str | None = Field(default=None, max_length=255)
    location: str | None = Field(default=None, max_length=255)
    status: ApplicationStatus | None = None
    salary_currency: SalaryCurrency | None = None
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


class ApplicationUpsertResult(BaseModel):
    """Response for PUT/PATCH /applications/by-external-id - the row
    alone doesn't say whether anything actually changed, which the
    caller needs to pick the right toast/Undo behavior."""

    application: ApplicationRead
    action: Literal["created", "updated", "unchanged"]


class ApplicationDeleteByExternalIdResult(BaseModel):
    """Response for DELETE /applications/by-external-id. Always 200, not
    404-on-not_found - "no saved row exists for this job" is one
    legitimate outcome of "make sure no saved row exists for this job",
    not an error."""

    action: Literal["deleted", "kept", "not_found"]
