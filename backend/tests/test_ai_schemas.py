"""
Unit tests for app.schemas.ai.

ParsedResume/AtsScoreResult/WorkExperienceItem/EducationItem are the
schemas handed to Gemini as response_schema, so every field on them must
be required (Field(...), no Python-side default) even where the type is
nullable - Gemini's API rejects a response_schema containing default
values (see app/schemas/ai.py's module docstring). These tests guard
that constraint directly, since a regression here wouldn't fail loudly
until an actual Gemini call at runtime.
"""

import uuid

import pytest
from pydantic import ValidationError

from app.schemas.ai import (
    AtsScoreCreate,
    AtsScoreResult,
    EducationItem,
    ParsedResume,
    ResumeAnalysisCreate,
    ResumeAnalysisUpdate,
    WorkExperienceItem,
)


class TestNoDefaultsOnGeminiSchemas:
    """Every field on these four models must be required - see module
    docstring above. Constructing each with a required field omitted
    should raise, proving there's no Python-side default silently
    filling it in (which would make the field optional from Gemini's
    response_schema conversion, tripping the "Default value is not
    supported" API-side rejection)."""

    @pytest.mark.parametrize(
        "field_name",
        [
            "full_name",
            "email",
            "phone",
            "summary",
            "skills",
            "work_experience",
            "education",
            "total_years_experience",
        ],
    )
    def test_parsed_resume_field_is_required(self, field_name):
        assert ParsedResume.model_fields[field_name].is_required()

    @pytest.mark.parametrize(
        "field_name",
        ["score", "summary", "matched_keywords", "missing_keywords", "suggestions"],
    )
    def test_ats_score_result_field_is_required(self, field_name):
        assert AtsScoreResult.model_fields[field_name].is_required()

    @pytest.mark.parametrize(
        "field_name",
        ["company", "title", "start_date", "end_date", "description"],
    )
    def test_work_experience_item_field_is_required(self, field_name):
        assert WorkExperienceItem.model_fields[field_name].is_required()

    @pytest.mark.parametrize(
        "field_name",
        ["institution", "degree", "field_of_study", "graduation_date"],
    )
    def test_education_item_field_is_required(self, field_name):
        assert EducationItem.model_fields[field_name].is_required()

    def test_parsed_resume_accepts_nulls_for_nullable_fields(self):
        # Required doesn't mean non-nullable - Gemini must supply the key,
        # but its value may legitimately be null/empty.
        parsed = ParsedResume(
            full_name=None,
            email=None,
            phone=None,
            summary=None,
            skills=[],
            work_experience=[],
            education=[],
            total_years_experience=None,
        )
        assert parsed.full_name is None
        assert parsed.skills == []

    def test_ats_score_result_score_bounds(self):
        with pytest.raises(ValidationError):
            AtsScoreResult(
                score=101,
                summary="x",
                matched_keywords=[],
                missing_keywords=[],
                suggestions=[],
            )


class TestAtsScoreCreate:
    def test_requires_resume_analysis_id(self):
        # model_validate(), not the constructor: omitting a required
        # keyword argument is exactly what this test wants to prove
        # raises ValidationError, but it's also a static type error at
        # the constructor call site - model_validate() takes an
        # untyped dict, so the missing-field check only happens at
        # runtime, which is the point here.
        with pytest.raises(ValidationError):
            AtsScoreCreate.model_validate({"job_description": "x" * 60})

    def test_job_description_is_optional(self):
        payload = AtsScoreCreate(resume_analysis_id=uuid.uuid4())
        assert payload.job_description is None

    def test_job_description_too_short_is_rejected(self):
        with pytest.raises(ValidationError):
            AtsScoreCreate(resume_analysis_id=uuid.uuid4(), job_description="short")

    def test_job_description_within_bounds_is_accepted(self):
        payload = AtsScoreCreate(
            resume_analysis_id=uuid.uuid4(), job_description="x" * 100
        )
        assert payload.job_description is not None


class TestResumeAnalysisCreate:
    def test_requires_document_id(self):
        # Same model_validate() reasoning as AtsScoreCreate above.
        with pytest.raises(ValidationError):
            ResumeAnalysisCreate.model_validate({})


class TestResumeAnalysisUpdate:
    def test_analysis_name_is_optional(self):
        payload = ResumeAnalysisUpdate()
        assert payload.analysis_name is None

    def test_accepts_a_new_analysis_name(self):
        payload = ResumeAnalysisUpdate(analysis_name="my_custom_name")
        assert payload.analysis_name == "my_custom_name"

    def test_rejects_analysis_name_over_max_length(self):
        with pytest.raises(ValidationError):
            ResumeAnalysisUpdate(analysis_name="x" * 256)
