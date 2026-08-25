"""
Tests for app/tasks/reminders_inline.py::send_due_reminders - the
in-process equivalent of app/tasks/reminders_celery.py::send_due_reminders,
covered by test_reminders_celery.py. Scheduling
(app/services/reminders.py::sync_interview_reminders) is provider-agnostic
and already covered there too - only the sending half is duplicated here,
same subset test_ai_inline.py mirrors from test_ai_celery_tasks.py.
"""

from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock

import pytest
from sqlalchemy.orm import sessionmaker

import app.tasks.reminders_inline as reminders_inline_module
from app.models.application import Application, ApplicationStatus
from app.models.interview import Interview, InterviewType
from app.models.interview_reminder import InterviewReminder, ReminderChannel
from app.models.notification import Notification
from app.tasks.reminders_inline import send_due_reminders


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


@pytest.fixture()
def patch_reminders_inline_session(monkeypatch, db_session):
    """send_due_reminders opens its own SessionLocal() (it runs outside a
    request) - bind a second Session to db_session's own connection so
    its commits become SAVEPOINT release/restart within the same
    transaction this test rolls back, same approach
    test_reminders_celery.py::patch_reminders_task_session uses."""
    connection = db_session.connection()
    task_session_factory = sessionmaker(
        bind=connection, join_transaction_mode="create_savepoint"
    )
    monkeypatch.setattr(reminders_inline_module, "SessionLocal", task_session_factory)
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
        self, db_session, make_user, patch_reminders_inline_session
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

    def test_master_switch_off_suppresses_every_channel(
        self,
        client,
        db_session,
        make_user,
        auth_headers,
        patch_reminders_inline_session,
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
        patch_reminders_inline_session,
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
        monkeypatch.setattr(reminders_inline_module, "send_email", send_email_mock)

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
        patch_reminders_inline_session,
        monkeypatch,
    ):
        user = make_user()
        _, reminder = _make_due_interview_reminder(
            db_session, user, ReminderChannel.EMAIL
        )
        send_email_mock = MagicMock(return_value=True)
        monkeypatch.setattr(reminders_inline_module, "send_email", send_email_mock)

        sent_count = send_due_reminders()

        assert sent_count == 1
        send_email_mock.assert_called_once()
        db_session.refresh(reminder)
        assert reminder.sent_at is not None
