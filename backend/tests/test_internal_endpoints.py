"""
Tests for /internal/reminders/run (app/api/v1/endpoints/internal.py).

Mocking strategy: send_due_reminders itself is covered by
test_reminders_inline.py - these tests only verify the endpoint's
secret-header auth and that it calls through and echoes the count, so
send_due_reminders is patched rather than exercised for real (same
"verify dispatch, not the pipeline" split test_ai_endpoints.py uses for
process_resume_analysis/process_ats_score).
"""

from unittest.mock import MagicMock

import pytest

import app.api.v1.endpoints.internal as internal_endpoints_module

RUN_REMINDERS_URL = "/api/v1/internal/reminders/run"


@pytest.fixture()
def cron_secret(monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "INTERNAL_CRON_SECRET", "test-secret")
    return "test-secret"


@pytest.fixture()
def fake_send_due_reminders(monkeypatch):
    fake = MagicMock(return_value=3)
    monkeypatch.setattr(internal_endpoints_module, "send_due_reminders", fake)
    return fake


class TestNotConfigured:
    def test_503_when_secret_unset(self, client):
        # INTERNAL_CRON_SECRET defaults to "" - the cron_secret fixture
        # isn't used here, so this hits that default.
        response = client.post(
            RUN_REMINDERS_URL, headers={"X-Internal-Cron-Secret": "anything"}
        )
        assert response.status_code == 503


class TestAuth:
    def test_401_when_header_missing(self, client, cron_secret):
        response = client.post(RUN_REMINDERS_URL)
        assert response.status_code == 401

    def test_401_when_header_wrong(self, client, cron_secret):
        response = client.post(
            RUN_REMINDERS_URL, headers={"X-Internal-Cron-Secret": "wrong-secret"}
        )
        assert response.status_code == 401

    def test_200_when_header_correct(
        self, client, cron_secret, fake_send_due_reminders
    ):
        response = client.post(
            RUN_REMINDERS_URL, headers={"X-Internal-Cron-Secret": cron_secret}
        )
        assert response.status_code == 200


class TestDispatch:
    def test_calls_send_due_reminders_and_echoes_count(
        self, client, cron_secret, fake_send_due_reminders
    ):
        response = client.post(
            RUN_REMINDERS_URL, headers={"X-Internal-Cron-Secret": cron_secret}
        )

        fake_send_due_reminders.assert_called_once_with()
        assert response.json() == {"sent_count": 3}
