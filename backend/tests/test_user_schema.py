"""
Unit tests for app.schemas.user validation rules.
"""

import pytest
from pydantic import ValidationError

from app.schemas.user import (
    AccountDeleteRequest,
    PasswordChangeRequest,
    UserCreate,
    UserProfileUpdate,
)


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


class TestUserProfileUpdateValidation:
    def test_all_fields_optional(self):
        payload = UserProfileUpdate()
        assert payload.first_name is None
        assert payload.last_name is None
        assert payload.timezone is None

    def test_empty_first_name_is_rejected(self):
        with pytest.raises(ValidationError):
            UserProfileUpdate(first_name="")

    def test_does_not_accept_avatar_url(self):
        # UserProfileUpdate deliberately can't even express avatar_url -
        # only POST/DELETE /users/me/avatar may set it. Pydantic's default
        # config ignores unknown fields rather than erroring, so this
        # confirms the field is simply absent from the model, not just
        # unused.
        payload = UserProfileUpdate(**{"first_name": "Jane", "avatar_url": "evil-key"})
        assert not hasattr(payload, "avatar_url")


class TestPasswordChangeRequestValidation:
    def test_valid_payload_is_accepted(self):
        payload = PasswordChangeRequest(
            current_password="old-password", new_password="new-password-123"
        )
        assert payload.new_password == "new-password-123"

    def test_new_password_shorter_than_minimum_is_rejected(self):
        with pytest.raises(ValidationError):
            PasswordChangeRequest(current_password="old-password", new_password="short")


class TestAccountDeleteRequestValidation:
    def test_requires_password(self):
        with pytest.raises(ValidationError):
            AccountDeleteRequest()

    def test_valid_payload_is_accepted(self):
        payload = AccountDeleteRequest(password="whatever-it-is")
        assert payload.password == "whatever-it-is"
