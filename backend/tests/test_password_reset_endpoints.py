"""
Integration tests for POST /auth/password-reset/request and
POST /auth/password-reset/confirm (app/api/v1/endpoints/auth.py), plus
POST /users/me/password-reset/request (app/api/v1/endpoints/users.py).

send_password_reset_email is monkeypatched at every call site rather
than exercised for real - it ultimately reaches a real network call
(Resend/Gmail API) or a local MailHog SMTP connection depending on
config, neither of which belongs in this suite. check_and_increment is
also monkeypatched to a no-op in every test except
TestRateLimiting.test_exceeding_the_limit_returns_429 - the app's
Redis-backed limiter is real infra shared across test runs (see
test_rate_limit.py's own docstring on why counters aren't rolled back
like the DB is), so without this, repeated suite runs on the same UTC
day would eventually make every other test here start seeing 429s from
counters left over by earlier runs.
"""

from unittest.mock import MagicMock

import pytest

import app.api.v1.endpoints.auth as auth_module
import app.api.v1.endpoints.users as users_module
from app.core.security import create_password_reset_token
from app.services.rate_limit import RateLimitExceeded

REQUEST_URL = "/api/v1/auth/password-reset/request"
CONFIRM_URL = "/api/v1/auth/password-reset/confirm"
OWN_REQUEST_URL = "/api/v1/users/me/password-reset/request"


@pytest.fixture(autouse=True)
def no_op_rate_limit(monkeypatch):
    """Applies to every test in this file except the one that
    deliberately overrides it - see module docstring."""
    monkeypatch.setattr(auth_module, "check_and_increment", MagicMock())


class TestRequestPasswordReset:
    def test_unknown_email_still_returns_202(self, client, monkeypatch):
        send_mock = MagicMock(return_value=True)
        monkeypatch.setattr(auth_module, "send_password_reset_email", send_mock)

        response = client.post(REQUEST_URL, json={"email": "nobody@example.com"})

        assert response.status_code == 202
        send_mock.assert_not_called()

    def test_known_email_sends_email_and_returns_202(
        self, client, make_user, monkeypatch
    ):
        send_mock = MagicMock(return_value=True)
        monkeypatch.setattr(auth_module, "send_password_reset_email", send_mock)
        user = make_user(email="reset-me@example.com")

        response = client.post(REQUEST_URL, json={"email": "reset-me@example.com"})

        assert response.status_code == 202
        send_mock.assert_called_once_with(user)

    def test_response_body_is_identical_for_known_and_unknown_email(
        self, client, make_user, monkeypatch
    ):
        monkeypatch.setattr(
            auth_module, "send_password_reset_email", MagicMock(return_value=True)
        )
        make_user(email="known@example.com")

        known_response = client.post(REQUEST_URL, json={"email": "known@example.com"})
        unknown_response = client.post(
            REQUEST_URL, json={"email": "unknown@example.com"}
        )

        assert known_response.json() == unknown_response.json()


class TestRateLimiting:
    def test_exceeding_the_limit_returns_429(self, client, monkeypatch):
        # Overrides the autouse no-op fixture for this one test, to
        # exercise the actual 429 mapping.
        monkeypatch.setattr(
            auth_module,
            "check_and_increment",
            MagicMock(side_effect=RateLimitExceeded(retry_after_seconds=42)),
        )
        monkeypatch.setattr(
            auth_module, "send_password_reset_email", MagicMock(return_value=True)
        )

        response = client.post(REQUEST_URL, json={"email": "anyone@example.com"})

        assert response.status_code == 429
        assert response.headers["retry-after"] == "42"


class TestConfirmPasswordReset:
    def test_valid_token_updates_password_and_returns_200(
        self, client, db_session, make_user
    ):
        user = make_user(password="old-password-123")
        token = create_password_reset_token(
            str(user.id), token_version=user.token_version
        )

        response = client.post(
            CONFIRM_URL, json={"token": token, "new_password": "new-password-456"}
        )

        assert response.status_code == 200
        db_session.refresh(user)
        from app.core.security import verify_password

        assert verify_password("new-password-456", user.password_hash)

    def test_garbage_token_returns_400(self, client):
        response = client.post(
            CONFIRM_URL,
            json={"token": "not-a-real-token", "new_password": "whatever123"},
        )
        assert response.status_code == 400

    def test_token_cannot_be_reused(self, client, make_user):
        user = make_user()
        token = create_password_reset_token(
            str(user.id), token_version=user.token_version
        )

        first = client.post(
            CONFIRM_URL, json={"token": token, "new_password": "first-password-1"}
        )
        second = client.post(
            CONFIRM_URL, json={"token": token, "new_password": "second-password-2"}
        )

        assert first.status_code == 200
        assert second.status_code == 400

    def test_confirming_invalidates_existing_access_token(
        self, client, make_user, auth_headers
    ):
        """Regression guard for User.token_version: a session that was
        already logged in before the reset must be logged out by it,
        not just future logins."""
        user = make_user()
        stale_headers = auth_headers(user)
        token = create_password_reset_token(
            str(user.id), token_version=user.token_version
        )

        client.post(
            CONFIRM_URL, json={"token": token, "new_password": "new-password-789"}
        )
        response = client.get("/api/v1/users/me", headers=stale_headers)

        assert response.status_code == 401


class TestRequestOwnPasswordResetIsUnrateLimited:
    def test_authenticated_request_does_not_touch_the_rate_limiter(
        self, client, make_user, auth_headers, monkeypatch
    ):
        # If this endpoint ever starts calling check_and_increment, this
        # mock (distinct from auth_module's) would need patching too -
        # its absence here is itself the assertion that users.py's
        # endpoint never touches app.api.v1.endpoints.auth's limiter.
        monkeypatch.setattr(
            users_module, "send_password_reset_email", MagicMock(return_value=True)
        )
        user = make_user()

        response = client.post(OWN_REQUEST_URL, headers=auth_headers(user))

        assert response.status_code == 202
