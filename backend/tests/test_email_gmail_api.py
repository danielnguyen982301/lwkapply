"""
Tests for app/services/email_gmail_api.py.

Mocking strategy: `build` (from googleapiclient.discovery) is imported
by name into this module's own namespace, so it's patched there - same
"resolved through the calling module's own globals" reasoning documented
in test_documents_endpoints.py and test_ai_celery_tasks.py. Never makes
a real network call to Google.
"""

from unittest.mock import MagicMock

import pytest
from google.auth.exceptions import RefreshError
from googleapiclient.errors import HttpError

import app.services.email_gmail_api as email_gmail_api_module
from app.services.email_gmail_api import send_email


@pytest.fixture(autouse=True)
def gmail_configured(monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "GMAIL_API_CLIENT_ID", "test-client-id")
    monkeypatch.setattr(settings, "GMAIL_API_CLIENT_SECRET", "test-client-secret")
    monkeypatch.setattr(settings, "GMAIL_API_REFRESH_TOKEN", "test-refresh-token")
    monkeypatch.setattr(settings, "GMAIL_API_SENDER_EMAIL", "sender@gmail.com")


def _http_error(status: int = 500) -> HttpError:
    resp = type("Resp", (), {"status": status, "reason": "error"})()
    return HttpError(resp, b'{"error": "boom"}')


class TestNotConfigured:
    @pytest.mark.parametrize(
        "missing_setting",
        [
            "GMAIL_API_CLIENT_ID",
            "GMAIL_API_CLIENT_SECRET",
            "GMAIL_API_REFRESH_TOKEN",
            "GMAIL_API_SENDER_EMAIL",
        ],
    )
    def test_returns_false_when_any_setting_is_missing(
        self, monkeypatch, missing_setting
    ):
        from app.core.config import settings

        monkeypatch.setattr(settings, missing_setting, "")

        result = send_email(
            to="user@example.com", subject="Hi", html="<p>hi</p>", text="hi"
        )

        assert result is False


class TestSendEmail:
    def test_success_calls_gmail_send_with_raw_message_and_returns_true(
        self, monkeypatch
    ):
        fake_send_execute = MagicMock(return_value={"id": "msg-1"})
        fake_messages = MagicMock()
        fake_messages.send.return_value.execute = fake_send_execute
        fake_service = MagicMock()
        fake_service.users.return_value.messages.return_value = fake_messages
        fake_build = MagicMock(return_value=fake_service)
        monkeypatch.setattr(email_gmail_api_module, "build", fake_build)

        result = send_email(
            to="user@example.com",
            subject="Upcoming interview",
            html="<p>reminder</p>",
            text="reminder",
        )

        assert result is True
        fake_build.assert_called_once()
        assert fake_build.call_args.args[:2] == ("gmail", "v1")
        fake_messages.send.assert_called_once()
        call_kwargs = fake_messages.send.call_args.kwargs
        assert call_kwargs["userId"] == "me"
        assert "raw" in call_kwargs["body"]
        fake_send_execute.assert_called_once()

    def test_http_error_is_swallowed_and_returns_false(self, monkeypatch):
        fake_messages = MagicMock()
        fake_messages.send.return_value.execute.side_effect = _http_error()
        fake_service = MagicMock()
        fake_service.users.return_value.messages.return_value = fake_messages
        monkeypatch.setattr(
            email_gmail_api_module, "build", MagicMock(return_value=fake_service)
        )

        result = send_email(
            to="user@example.com", subject="Hi", html="<p>hi</p>", text="hi"
        )

        assert result is False

    def test_refresh_error_is_swallowed_and_returns_false(self, monkeypatch):
        monkeypatch.setattr(
            email_gmail_api_module,
            "build",
            MagicMock(side_effect=RefreshError("token expired")),
        )

        result = send_email(
            to="user@example.com", subject="Hi", html="<p>hi</p>", text="hi"
        )

        assert result is False
