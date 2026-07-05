"""
Unit tests for app.schemas.interview.

Focus: enum coercion (type/result) and the duration_minutes bounds,
since those are the only non-trivial validation in this schema.
"""

from datetime import datetime, timezone
from typing import Any

import pytest
from pydantic import ValidationError

from app.models.interview import InterviewResult, InterviewType
from app.schemas.interview import InterviewCreate, InterviewUpdate


def _base_payload(**overrides: Any) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "type": "technical",
        "scheduled_at": datetime(2026, 8, 1, 14, 0, tzinfo=timezone.utc),
    }
    payload.update(overrides)
    return payload


class TestInterviewCreate:
    def test_minimal_payload_is_accepted(self):
        interview = InterviewCreate(**_base_payload())
        assert interview.type == InterviewType.TECHNICAL
        assert interview.result == InterviewResult.PENDING

    def test_invalid_type_is_rejected(self):
        with pytest.raises(ValidationError):
            InterviewCreate(**_base_payload(type="not_a_real_type"))

    def test_missing_scheduled_at_is_rejected(self):
        with pytest.raises(ValidationError):
            InterviewCreate(type="technical")  # pyright: ignore[reportCallIssue]

    def test_zero_duration_is_rejected(self):
        with pytest.raises(ValidationError):
            InterviewCreate(**_base_payload(duration_minutes=0))

    def test_duration_over_24h_is_rejected(self):
        with pytest.raises(ValidationError):
            InterviewCreate(**_base_payload(duration_minutes=1441))

    def test_reasonable_duration_is_accepted(self):
        interview = InterviewCreate(**_base_payload(duration_minutes=45))
        assert interview.duration_minutes == 45

    def test_explicit_result_overrides_default(self):
        interview = InterviewCreate(**_base_payload(result="passed"))
        assert interview.result == InterviewResult.PASSED


class TestInterviewUpdate:
    def test_partial_update_only_sets_provided_fields(self):
        update = InterviewUpdate(result=InterviewResult.FAILED)
        dumped = update.model_dump(exclude_unset=True)
        assert dumped == {"result": InterviewResult.FAILED}

    def test_empty_update_is_valid_but_dumps_empty(self):
        update = InterviewUpdate()
        assert update.model_dump(exclude_unset=True) == {}
