"""
Schemas for the AI features (Resume Parser + ATS Score - TODO.md "AI
Features"). Two different jobs here:

- ParsedResume (+ WorkExperienceItem, EducationItem) and AtsScoreResult
  are both the `response_schema` handed to Gemini (see
  app/services/ai/client.py::call_structured) *and* the validator for its
  response - Gemini's structured-output mode fills in exactly this shape,
  and re-validating it here (rather than trusting the SDK blindly) is
  what lets a malformed/incomplete response surface as a real failure.
  Every field on these four models is required (`Field(...)`, no Python-
  side default) even where the type itself is nullable (`str | None`) -
  Gemini's API rejects a response_schema containing default values
  outright ("Default value is not supported in the response schema for
  the Gemini API" - confirmed against googleapis/python-genai#699), so
  "optional" here is expressed purely as "the key must be present, but
  its value may be null/empty", never as "the key may be omitted". Field
  types are otherwise kept deliberately simple (str, str | None,
  list[str], list[<flat submodel>]) - Gemini's response_schema support is
  an OpenAPI subset, not arbitrary Pydantic (no $ref/oneOf/allOf/
  recursive schemas).
- ResumeAnalysisCreate/Read/ListResponse and AtsScoreCreate/Read/
  ListResponse are the ordinary request/response schemas for
  app/api/v1/endpoints/ai.py, same pagination-envelope shape as every
  other list endpoint (e.g. DocumentListResponse). These aren't sent to
  Gemini, so the "no defaults" constraint above doesn't apply to them.
"""

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

from app.models.resume_analysis import AIJobStatus


# --- Gemini structured-output schemas --------------------------------------


class WorkExperienceItem(BaseModel):
    company: str = Field(...)
    title: str = Field(...)
    start_date: str | None = Field(...)
    end_date: str | None = Field(...)  # "Present" (as text) if currently held
    description: str | None = Field(...)


class EducationItem(BaseModel):
    institution: str = Field(...)
    degree: str | None = Field(...)
    field_of_study: str | None = Field(...)
    graduation_date: str | None = Field(...)


class ParsedResume(BaseModel):
    full_name: str | None = Field(...)
    email: str | None = Field(...)
    phone: str | None = Field(...)
    summary: str | None = Field(...)
    skills: list[str] = Field(...)
    work_experience: list[WorkExperienceItem] = Field(...)
    education: list[EducationItem] = Field(...)
    total_years_experience: float | None = Field(...)


class AtsScoreResult(BaseModel):
    score: int = Field(..., ge=0, le=100)
    summary: str = Field(...)
    matched_keywords: list[str] = Field(...)
    missing_keywords: list[str] = Field(...)
    suggestions: list[str] = Field(...)


# --- Resume analyses API ----------------------------------------------------


class ResumeAnalysisCreate(BaseModel):
    document_id: uuid.UUID


class ResumeAnalysisRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    document_id: uuid.UUID
    status: AIJobStatus
    parsed_data: dict | None = None
    error_message: str | None = None
    created_at: datetime
    updated_at: datetime


class ResumeAnalysisListResponse(BaseModel):
    items: list[ResumeAnalysisRead]
    total: int
    page: int
    page_size: int


# --- ATS scores API ----------------------------------------------------------


class AtsScoreCreate(BaseModel):
    resume_analysis_id: uuid.UUID
    application_id: uuid.UUID | None = None
    # Optional: prefers the linked application's job_url when omitted -
    # see app/api/v1/endpoints/ai.py's create endpoint and
    # app/tasks/ai.py::score_ats_task. Length-bounded so an empty/garbage
    # submission doesn't burn a real Gemini call.
    job_description: str | None = Field(default=None, min_length=50, max_length=20000)


class AtsScoreRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    resume_analysis_id: uuid.UUID
    application_id: uuid.UUID | None
    job_description: str | None
    job_description_source: str | None
    status: AIJobStatus
    score: int | None = None
    feedback: dict | None = None
    error_message: str | None = None
    created_at: datetime
    updated_at: datetime


class AtsScoreListResponse(BaseModel):
    items: list[AtsScoreRead]
    total: int
    page: int
    page_size: int
