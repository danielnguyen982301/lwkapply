"""
Tests for the interview-reminder pipeline: scheduling
(app/services/reminders.py::sync_interview_reminders, exercised through
the real interview create endpoint - same "integration test of a write
path wired into an endpoint" shape as test_application_status_history.py)
and sending (app/tasks/reminders.py::send_due_reminders, called directly
as a plain function - same approach test_ai_tasks.py uses, since Celery
tasks are plain callables and there's no existing precedent for routing
through the broker in this test suite).

Covers what changed in this pass: per-user reminder_lead_hours overrides
(falling back to the global settings.REMINDER_LEAD_HOURS default), the
new IN_APP channel being scheduled alongside EMAIL/PUSH, and
notification-preference enforcement at send time (app/models/user_settings.py).
"""

from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock

import pytest
from sqlalchemy.orm import sessionmaker

import app.tasks.reminders as reminders_task_module
from app.models.application import Application, ApplicationStatus
from app.models.interview import Interview, InterviewType
from app.models.interview_reminder import InterviewReminder, ReminderChannel
from app.models.notification import Notification
from app.tasks.reminders import send_due_reminders

BASE_SCHEDULED_AT_OFFSET = timedelta(hours=48)


def _applications_url() -> str:
    return "/api/v1/applications"


def _interviews_url(application_id) -> str:
    return f"{_applications_url()}/{application_id}/interviews"


def _make_application(db_session, user, **overrides):
    defaults = {
        "user_id": user.id,
        "company": "Initech",
        "position": "Backend Engineer",
        "status": ApplicationStatus.SAVED,
    }
    defaults.update(overrides)
    application = Application(**defaults)
    db_session.add(application)
    db_session.commit()
    db_session.refresh(application)
    return application


def _reminders_for(db_session, interview_id):
    return (
        db_session.query(InterviewReminder)
        .filter(InterviewReminder.interview_id == interview_id)
        .all()
    )


class TestSyncInterviewRemindersLeadHours:
    def test_uses_the_global_default_with_no_user_override(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)
        scheduled_at = datetime.now(timezone.utc) + BASE_SCHEDULED_AT_OFFSET

        response = client.post(
            _interviews_url(application.id),
            json={
                "type": InterviewType.TECHNICAL.value,
                "scheduled_at": scheduled_at.isoformat(),
            },
            headers=auth_headers(user),
        )

        assert response.status_code == 201
        reminders = _reminders_for(db_session, response.json()["id"])
        assert len(reminders) == 3
        for reminder in reminders:
            assert reminder.remind_at == scheduled_at - timedelta(hours=24)

    def test_uses_the_users_override_when_set(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        client.patch(
            "/api/v1/users/me/settings",
            json={"reminder_lead_hours": 2},
            headers=auth_headers(user),
        )
        application = _make_application(db_session, user)
        scheduled_at = datetime.now(timezone.utc) + BASE_SCHEDULED_AT_OFFSET

        response = client.post(
            _interviews_url(application.id),
            json={
                "type": InterviewType.TECHNICAL.value,
                "scheduled_at": scheduled_at.isoformat(),
            },
            headers=auth_headers(user),
        )

        reminders = _reminders_for(db_session, response.json()["id"])
        assert len(reminders) == 3
        for reminder in reminders:
            assert reminder.remind_at == scheduled_at - timedelta(hours=2)

    def test_schedules_all_three_channels(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)
        scheduled_at = datetime.now(timezone.utc) + BASE_SCHEDULED_AT_OFFSET

        response = client.post(
            _interviews_url(application.id),
            json={
                "type": InterviewType.TECHNICAL.value,
                "scheduled_at": scheduled_at.isoformat(),
            },
            headers=auth_headers(user),
        )

        channels = {
            r.channel for r in _reminders_for(db_session, response.json()["id"])
        }
        assert channels == {
            ReminderChannel.EMAIL,
            ReminderChannel.PUSH,
            ReminderChannel.IN_APP,
        }


@pytest.fixture()
def patch_reminders_task_session(monkeypatch, db_session):
    """send_due_reminders opens its own SessionLocal() (it runs outside a
    request) - bind a second Session to db_session's own connection so
    its commits become SAVEPOINT release/restart within the same
    transaction this test rolls back, same approach
    test_ai_tasks.py::patch_ai_tasks_session uses for app.tasks.ai."""
    connection = db_session.connection()
    task_session_factory = sessionmaker(
        bind=connection, join_transaction_mode="create_savepoint"
    )
    monkeypatch.setattr(reminders_task_module, "SessionLocal", task_session_factory)
    return task_session_factory


def _make_due_interview_reminder(
    db_session, user, channel, application_overrides=None, interview_overrides=None
):
    application = _make_application(db_session, user, **(application_overrides or {}))
    interview_defaults = {
        "application_id": application.id,
        "type": InterviewType.TECHNICAL,
        "scheduled_at": datetime.now(timezone.utc) + timedelta(hours=1),
    }
    interview_defaults.update(interview_overrides or {})
    interview = Interview(**interview_defaults)
    db_session.add(interview)
    db_session.commit()
    db_session.refresh(interview)

    reminder = InterviewReminder(
        interview_id=interview.id,
        channel=channel,
        remind_at=datetime.now(timezone.utc) - timedelta(minutes=1),
    )
    db_session.add(reminder)
    db_session.commit()
    db_session.refresh(reminder)
    return interview, reminder


class TestSendDueRemindersInApp:
    def test_due_in_app_reminder_creates_a_notification_and_marks_sent(
        self, db_session, make_user, patch_reminders_task_session
    ):
        user = make_user()
        interview, reminder = _make_due_interview_reminder(
            db_session, user, ReminderChannel.IN_APP
        )

        sent_count = send_due_reminders()

        assert sent_count == 1
        db_session.refresh(reminder)
        assert reminder.sent_at is not None
        notification = (
            db_session.query(Notification)
            .filter(Notification.interview_id == interview.id)
            .first()
        )
        assert notification is not None
        assert notification.application_id == interview.application_id
        assert "Technical" in notification.title

    def test_disabled_in_app_channel_marks_sent_without_creating_a_notification(
        self, client, db_session, make_user, auth_headers, patch_reminders_task_session
    ):
        user = make_user()
        client.patch(
            "/api/v1/users/me/settings",
            json={"in_app_notifications_enabled": False},
            headers=auth_headers(user),
        )
        interview, reminder = _make_due_interview_reminder(
            db_session, user, ReminderChannel.IN_APP
        )

        sent_count = send_due_reminders()

        assert sent_count == 1
        db_session.refresh(reminder)
        assert reminder.sent_at is not None
        assert (
            db_session.query(Notification)
            .filter(Notification.interview_id == interview.id)
            .first()
            is None
        )

    def test_master_switch_off_suppresses_every_channel(
        self, client, db_session, make_user, auth_headers, patch_reminders_task_session
    ):
        user = make_user()
        client.patch(
            "/api/v1/users/me/settings",
            json={"notifications_enabled": False},
            headers=auth_headers(user),
        )
        interview, reminder = _make_due_interview_reminder(
            db_session, user, ReminderChannel.IN_APP
        )

        send_due_reminders()

        db_session.refresh(reminder)
        assert reminder.sent_at is not None
        assert (
            db_session.query(Notification)
            .filter(Notification.interview_id == interview.id)
            .first()
            is None
        )


class TestSendDueRemindersEmail:
    def test_disabled_email_channel_marks_sent_without_sending(
        self,
        client,
        db_session,
        make_user,
        auth_headers,
        patch_reminders_task_session,
        monkeypatch,
    ):
        user = make_user()
        client.patch(
            "/api/v1/users/me/settings",
            json={"email_notifications_enabled": False},
            headers=auth_headers(user),
        )
        _, reminder = _make_due_interview_reminder(
            db_session, user, ReminderChannel.EMAIL
        )
        send_email_mock = MagicMock()
        monkeypatch.setattr(reminders_task_module, "send_email", send_email_mock)

        sent_count = send_due_reminders()

        assert sent_count == 1
        send_email_mock.assert_not_called()
        db_session.refresh(reminder)
        assert reminder.sent_at is not None

    def test_enabled_email_channel_still_sends(
        self,
        client,
        db_session,
        make_user,
        auth_headers,
        patch_reminders_task_session,
        monkeypatch,
    ):
        user = make_user()
        _, reminder = _make_due_interview_reminder(
            db_session, user, ReminderChannel.EMAIL
        )
        send_email_mock = MagicMock(return_value=True)
        monkeypatch.setattr(reminders_task_module, "send_email", send_email_mock)

        sent_count = send_due_reminders()

        assert sent_count == 1
        send_email_mock.assert_called_once()
        db_session.refresh(reminder)
        assert reminder.sent_at is not None
