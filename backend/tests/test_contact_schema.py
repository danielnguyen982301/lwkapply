"""
Unit tests for app.schemas.contact.

Focus: EmailStr validation (matches the LoginRequest/PasswordResetRequest
convention already used in app.schemas.auth) and required-field checks.
"""

from typing import Any

import pytest
from pydantic import ValidationError

from app.schemas.contact import ContactCreate


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
