"""
Unit tests for app.schemas.contact.

Focus: EmailStr validation (matches the LoginRequest/PasswordResetRequest
convention already used in app.schemas.auth) and required-field checks.

ApplicationSummary/ContactWithApplicationRead/ContactWithApplicationListResponse
are gone along with the old cross-application directory they backed (see
app/schemas/contact.py) - a contact can now belong to zero, one, or
several applications, so there's no single parent application left to
embed. ContactRead is unit-tested directly here instead, same treatment
test_document_schema.py gives DocumentRead.
"""

from typing import Any

import pytest
from pydantic import ValidationError

from app.schemas.contact import ContactCreate, ContactRead


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


class TestContactReadShape:
    def test_application_id_is_not_a_field(self):
        # A contact is a standalone resource reusable across zero or more
        # applications (see ApplicationContact) - it no longer has a
        # single owning application_id.
        assert "application_id" not in ContactRead.model_fields
