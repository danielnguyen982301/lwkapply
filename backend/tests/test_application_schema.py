"""
Unit tests for the Pydantic validation logic in app.schemas.application.

Focus: the salary_min <= salary_max cross-field validator, since that's
the one piece of non-trivial business logic living in the schema layer.
"""

from typing import Any

import pytest
from pydantic import ValidationError

from app.models.application import ApplicationStatus
from app.schemas.application import ApplicationCreate, ApplicationUpdate


def _base_payload(**overrides: Any) -> dict[str, Any]:
    # Explicitly typed as dict[str, Any] - without this, Pylance infers
    # dict[str, str] from the literal below (both initial values are
    # strings) and then flags every call site that overrides a numeric
    # field (e.g. salary_min=80_000) as a type mismatch against
    # ApplicationCreate's int fields, even though it's correct at runtime.
    payload: dict[str, Any] = {"company": "Acme Corp", "position": "Backend Engineer"}
    payload.update(overrides)
    return payload


class TestSalaryRangeValidation:
    def test_valid_salary_range_is_accepted(self):
        app = ApplicationCreate(**_base_payload(salary_min=80_000, salary_max=120_000))
        assert app.salary_min == 80_000
        assert app.salary_max == 120_000

    def test_equal_min_and_max_is_valid(self):
        app = ApplicationCreate(**_base_payload(salary_min=100_000, salary_max=100_000))
        assert app.salary_min == app.salary_max

    def test_min_greater_than_max_is_rejected(self):
        with pytest.raises(
            ValidationError, match="salary_min cannot be greater than salary_max"
        ):
            ApplicationCreate(**_base_payload(salary_min=150_000, salary_max=100_000))

    def test_only_min_provided_is_valid(self):
        app = ApplicationCreate(**_base_payload(salary_min=80_000))
        assert app.salary_max is None

    def test_only_max_provided_is_valid(self):
        app = ApplicationCreate(**_base_payload(salary_max=120_000))
        assert app.salary_min is None

    def test_negative_salary_is_rejected(self):
        with pytest.raises(ValidationError):
            ApplicationCreate(**_base_payload(salary_min=-1))


class TestRequiredFields:
    def test_missing_company_is_rejected(self):
        with pytest.raises(ValidationError):
            ApplicationCreate(position="Backend Engineer")  # pyright: ignore[reportCallIssue]

    def test_missing_position_is_rejected(self):
        with pytest.raises(ValidationError):
            ApplicationCreate(company="Acme Corp")  # pyright: ignore[reportCallIssue]

    def test_default_status_is_saved(self):
        app = ApplicationCreate(**_base_payload())
        assert app.status == ApplicationStatus.SAVED


class TestApplicationUpdateSalaryValidation:
    """ApplicationUpdate previously had its own salary_min/salary_max
    fields with no cross-field check (it isn't a subclass of
    ApplicationBase, so ApplicationBase's validator never applied to it).
    Both schemas now share SalaryRangeValidationMixin, so this mirrors
    TestSalaryRangeValidation above but against ApplicationUpdate."""

    def test_valid_salary_range_is_accepted(self):
        update = ApplicationUpdate(salary_min=80_000, salary_max=120_000)
        assert update.salary_min == 80_000
        assert update.salary_max == 120_000

    def test_equal_min_and_max_is_valid(self):
        update = ApplicationUpdate(salary_min=100_000, salary_max=100_000)
        assert update.salary_min == update.salary_max

    def test_min_greater_than_max_is_rejected(self):
        with pytest.raises(
            ValidationError, match="salary_min cannot be greater than salary_max"
        ):
            ApplicationUpdate(salary_min=150_000, salary_max=100_000)

    def test_only_min_provided_is_valid(self):
        """Partial updates are the normal case for PATCH - providing just
        one side of the range must not trip the cross-field check."""
        update = ApplicationUpdate(salary_min=80_000)
        assert update.salary_max is None

    def test_only_max_provided_is_valid(self):
        update = ApplicationUpdate(salary_max=120_000)
        assert update.salary_min is None

    def test_negative_salary_is_rejected(self):
        with pytest.raises(ValidationError):
            ApplicationUpdate(salary_min=-1)

    def test_neither_field_provided_is_valid(self):
        """An update touching unrelated fields (e.g. just `notes`) must
        not be blocked by a validator neither field participates in."""
        update = ApplicationUpdate(notes="Following up next week")
        assert update.salary_min is None
        assert update.salary_max is None
