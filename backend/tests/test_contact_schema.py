"""
Unit tests for app.schemas.contact.

Focus: EmailStr validation (matches the LoginRequest/PasswordResetRequest
convention already used in app.schemas.auth) and required-field checks.
"""

import uuid
from datetime import datetime, timezone
from typing import Any

import pytest
from pydantic import ValidationError

from app.models.application import ApplicationStatus
from app.schemas.contact import (
    ApplicationSummary,
    ContactCreate,
    ContactWithApplicationListResponse,
    ContactWithApplicationRead,
)


def _base_payload(**overrides: Any) -> dict[str, Any]:
    payload: dict[str, Any] = {"name": "Jordan Lee"}
    payload.update(overrides)
    return payload


class TestContactCreate:
    def test_minimal_payload_is_accepted(self):
        contact = ContactCreate(**_base_payload())
        assert contact.name == "Jordan Lee"
        assert contact.email is None

    def test_missing_name_is_rejected(self):
        with pytest.raises(ValidationError):
            ContactCreate()  # pyright: ignore[reportCallIssue]

    def test_empty_name_is_rejected(self):
        with pytest.raises(ValidationError):
            ContactCreate(**_base_payload(name=""))

    def test_valid_email_is_accepted(self):
        contact = ContactCreate(**_base_payload(email="jordan@example.com"))
        assert contact.email == "jordan@example.com"

    def test_invalid_email_is_rejected(self):
        with pytest.raises(ValidationError):
            ContactCreate(**_base_payload(email="not-an-email"))

    def test_full_payload_is_accepted(self):
        contact = ContactCreate(
            **_base_payload(
                title="Recruiter",
                email="jordan@example.com",
                linkedin_url="https://linkedin.com/in/jordanlee",
            )
        )
        assert contact.title == "Recruiter"


# --- Cross-application contact directory ----------------------------------
# ApplicationSummary / ContactWithApplicationRead / ContactWithApplicationListResponse
# back GET /contacts (the flat "all my contacts" directory view). These are
# pure schema tests, same as above: no DB, just payload -> model validation.


def _application_summary_payload(**overrides: Any) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "id": uuid.uuid4(),
        "company": "Initech",
        "position": "Backend Engineer",
        "status": ApplicationStatus.SAVED,
    }
    payload.update(overrides)
    return payload


def _contact_with_application_payload(**overrides: Any) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "id": uuid.uuid4(),
        "application_id": uuid.uuid4(),
        "name": "Jordan Lee",
        "title": None,
        "email": None,
        "linkedin_url": None,
        "created_at": datetime.now(timezone.utc),
        "updated_at": datetime.now(timezone.utc),
        "application": _application_summary_payload(),
    }
    payload.update(overrides)
    return payload


class TestApplicationSummary:
    def test_minimal_payload_is_accepted(self):
        summary = ApplicationSummary(**_application_summary_payload())
        assert summary.company == "Initech"
        assert summary.status == ApplicationStatus.SAVED

    def test_missing_company_is_rejected(self):
        payload = _application_summary_payload()
        del payload["company"]
        with pytest.raises(ValidationError):
            ApplicationSummary(**payload)

    def test_invalid_status_is_rejected(self):
        with pytest.raises(ValidationError):
            ApplicationSummary(
                **_application_summary_payload(status="not-a-real-status")
            )

    def test_builds_from_orm_style_attributes(self):
        """model_config = from_attributes=True: this must also validate
        from an object exposing attributes (an ORM row), not just a dict,
        since that's how the /contacts endpoint actually constructs it via
        ContactWithApplicationRead.model_validate(orm_contact)."""

        class FakeApplicationRow:
            id = uuid.uuid4()
            company = "Initech"
            position = "Backend Engineer"
            status = ApplicationStatus.SAVED

        summary = ApplicationSummary.model_validate(FakeApplicationRow())
        assert summary.company == "Initech"


class TestContactWithApplicationRead:
    def test_full_payload_is_accepted(self):
        contact = ContactWithApplicationRead(**_contact_with_application_payload())
        assert contact.name == "Jordan Lee"
        assert contact.application.company == "Initech"

    def test_missing_application_is_rejected(self):
        payload = _contact_with_application_payload()
        del payload["application"]
        with pytest.raises(ValidationError):
            ContactWithApplicationRead(**payload)

    def test_malformed_nested_application_is_rejected(self):
        """A contact whose parent application summary is itself invalid
        should fail validation, not silently accept a half-formed nested
        object — this is the piece that would catch e.g. the /contacts
        endpoint's join returning an application row that's missing a
        required field."""
        payload = _contact_with_application_payload(
            application=_application_summary_payload()
        )
        del payload["application"]["company"]
        with pytest.raises(ValidationError):
            ContactWithApplicationRead(**payload)

    def test_builds_from_orm_style_attributes(self):
        """Mirrors what the endpoint actually does:
        ContactWithApplicationRead.model_validate(contact_row), where
        contact_row.application is the eager-loaded Application row."""

        class FakeApplicationRow:
            id = uuid.uuid4()
            company = "Initech"
            position = "Backend Engineer"
            status = ApplicationStatus.SAVED

        class FakeContactRow:
            id = uuid.uuid4()
            application_id = uuid.uuid4()
            name = "Jordan Lee"
            title = None
            email = None
            linkedin_url = None
            created_at = datetime.now(timezone.utc)
            updated_at = datetime.now(timezone.utc)
            application = FakeApplicationRow()

        contact = ContactWithApplicationRead.model_validate(FakeContactRow())
        assert contact.application.company == "Initech"


class TestContactWithApplicationListResponse:
    def test_empty_page_is_accepted(self):
        response = ContactWithApplicationListResponse(
            items=[], total=0, page=1, page_size=20
        )
        assert response.items == []
        assert response.total == 0

    def test_populated_page_is_accepted(self):
        response = ContactWithApplicationListResponse(
            items=[
                ContactWithApplicationRead.model_validate(
                    _contact_with_application_payload()
                ),
                ContactWithApplicationRead.model_validate(
                    _contact_with_application_payload()
                ),
            ],
            total=2,
            page=1,
            page_size=20,
        )
        assert len(response.items) == 2
        assert response.items[0].application.company == "Initech"

    def test_missing_pagination_fields_is_rejected(self):
        with pytest.raises(ValidationError):
            ContactWithApplicationListResponse(items=[], total=0)  # pyright: ignore[reportCallIssue]
