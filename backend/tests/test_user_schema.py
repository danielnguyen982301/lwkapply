"""
Unit tests for app.schemas.user validation rules.
"""

import pytest
from pydantic import ValidationError

from app.schemas.user import UserCreate


def _base_payload(**overrides):
    payload = {
        "email": "jane@example.com",
        "first_name": "Jane",
        "last_name": "Doe",
        "password": "a-strong-password",
    }
    payload.update(overrides)
    return payload


class TestUserCreateValidation:
    def test_valid_payload_is_accepted(self):
        user = UserCreate(**_base_payload())
        assert user.email == "jane@example.com"

    def test_invalid_email_is_rejected(self):
        with pytest.raises(ValidationError):
            UserCreate(**_base_payload(email="not-an-email"))

    def test_password_shorter_than_minimum_is_rejected(self):
        with pytest.raises(ValidationError):
            UserCreate(**_base_payload(password="short"))

    def test_password_at_minimum_length_is_accepted(self):
        user = UserCreate(**_base_payload(password="12345678"))
        assert len(user.password) == 8

    def test_empty_first_name_is_rejected(self):
        with pytest.raises(ValidationError):
            UserCreate(**_base_payload(first_name=""))
