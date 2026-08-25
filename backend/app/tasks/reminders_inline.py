"""
In-process equivalent of app/tasks/reminders_celery.py's
send_due_reminders, for deployments that skip running Celery beat
(Render has no free tier for an always-on background worker - see
BACKEND_SUMMARY.md's "Background job execution" section). Triggered
over HTTP by an external scheduler (a
GitHub Actions cron workflow by default - see
.github/workflows/reminders-cron.yml) hitting
app/api/v1/endpoints/internal.py's POST /internal/reminders/run,
instead of a beat process ticking on its own schedule.

Deliberately a separate, self-contained module rather than a shared
helper the Celery task also calls: keeps app/tasks/reminders_celery.py
fully intact as a standalone reference/study copy (see that file), at
the cost of the two staying in sync by hand if the pipeline itself
changes. Idempotency (sent_at IS NULL guard, see
app/models/interview_reminder.py) is what makes a late/duplicate
external-cron tick harmless, same as it does for a duplicate beat tick.
"""

import logging
from datetime import datetime, timezone as dt_timezone
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.orm import Session, joinedload

from app.db.session import SessionLocal
from app.models.application import Application
from app.models.device_token import DeviceToken
from app.models.interview import Interview
from app.models.interview_reminder import InterviewReminder, ReminderChannel
from app.models.notification import Notification, NotificationType
from app.models.user import User
from app.services.email import send_email
from app.services.push import PushResult, send_push

logger = logging.getLogger(__name__)


def _format_scheduled_at(scheduled_at: datetime, user_timezone: str | None) -> str:
    tz = ZoneInfo(user_timezone) if user_timezone else dt_timezone.utc
    localized = scheduled_at.astimezone(tz)
    label = "UTC" if tz is dt_timezone.utc else localized.tzname() or user_timezone
    return f"{localized.strftime('%A, %B %-d, %Y at %-I:%M %p')} ({label})"


def _interview_summary(reminder: InterviewReminder) -> tuple[str, str, str, str]:
    interview = reminder.interview
    application = interview.application
    user = application.user

    when = _format_scheduled_at(interview.scheduled_at, user.timezone)
    interview_type = interview.type.value.replace("_", " ").title()
    return interview_type, when, application.company, application.position


def _build_email(reminder: InterviewReminder) -> tuple[str, str, str]:
    """Returns (subject, html, text)."""
    interview_type, when, company, position = _interview_summary(reminder)
    application_id = reminder.interview.application.id

    subject = f"Upcoming interview: {company} ({interview_type})"
    text = (
        f"Reminder: you have a {interview_type} interview for "
        f"{position} at {company}.\n\n"
        f"When: {when}\n\n"
        f"View details: {_application_url(application_id)}"
    )
    html = (
        f"<p>Reminder: you have a <strong>{interview_type}</strong> interview "
        f"for <strong>{position}</strong> at "
        f"<strong>{company}</strong>.</p>"
        f"<p><strong>When:</strong> {when}</p>"
        f'<p><a href="{_application_url(application_id)}">View application</a></p>'
    )
    return subject, html, text


def _build_in_app(reminder: InterviewReminder) -> tuple[str, str]:
    interview_type, when, company, position = _interview_summary(reminder)
    title = f"Upcoming {interview_type} interview at {company}"
    body = f"{position} - {when}"
    return title, body


def _build_push(reminder: InterviewReminder) -> tuple[str, str, dict[str, str]]:
    interview_type, when, company, position = _interview_summary(reminder)
    interview = reminder.interview

    title = f"Upcoming interview at {company}"
    body = f"{interview_type} for {position} - {when}"
    data = {
        "type": "interview_reminder",
        "application_id": str(interview.application.id),
        "interview_id": str(interview.id),
    }
    return title, body, data


def _application_url(application_id) -> str:
    from app.core.config import settings

    return f"{settings.FRONTEND_URL}/applications/{application_id}"


def _channel_enabled(user: User, channel: ReminderChannel) -> bool:
    settings_row = user.settings
    if settings_row is None:
        return True
    if not settings_row.notifications_enabled:
        return False
    if channel == ReminderChannel.EMAIL:
        return settings_row.email_notifications_enabled
    if channel == ReminderChannel.PUSH:
        return settings_row.push_notifications_enabled
    return True


def _send_in_app_reminder(db: Session, reminder: InterviewReminder) -> bool:
    interview = reminder.interview
    title, body = _build_in_app(reminder)
    db.add(
        Notification(
            user_id=interview.application.user.id,
            type=NotificationType.INTERVIEW_REMINDER,
            title=title,
            body=body,
            application_id=interview.application.id,
            interview_id=interview.id,
        )
    )
    db.commit()
    return True


def _send_email_reminder(reminder: InterviewReminder) -> bool:
    user = reminder.interview.application.user
    subject, html, text = _build_email(reminder)
    success = send_email(to=user.email, subject=subject, html=html, text=text)
    if not success:
        logger.error(
            "Failed to send interview reminder id=%s to=%s", reminder.id, user.email
        )
    return success


def _send_push_reminder(db: Session, reminder: InterviewReminder) -> bool:
    user = reminder.interview.application.user
    tokens = (
        db.execute(select(DeviceToken).where(DeviceToken.user_id == user.id))
        .scalars()
        .all()
    )

    if not tokens:
        return True

    title, body, data = _build_push(reminder)
    any_sent = False
    any_transient_failure = False

    for device_token in tokens:
        result = send_push(device_token.token, title=title, body=body, data=data)
        if result is PushResult.SENT:
            any_sent = True
        elif result is PushResult.INVALID_TOKEN:
            db.delete(device_token)
        else:
            any_transient_failure = True
            logger.error(
                "Transient FCM failure for user_id=%s device_token_id=%s",
                user.id,
                device_token.id,
            )

    db.commit()

    if any_sent:
        return True
    return not any_transient_failure


def send_due_reminders() -> int:
    """In-process equivalent of
    app.tasks.reminders_celery.send_due_reminders. Returns the number of
    reminders successfully sent/resolved, for the internal endpoint's
    response body / test assertions."""
    db: Session = SessionLocal()
    sent_count = 0
    try:
        now = datetime.now(dt_timezone.utc)
        due = (
            db.execute(
                select(InterviewReminder)
                .options(
                    joinedload(InterviewReminder.interview)
                    .joinedload(Interview.application)
                    .joinedload(Application.user)
                    .joinedload(User.settings)
                )
                .where(
                    InterviewReminder.remind_at <= now,
                    InterviewReminder.sent_at.is_(None),
                )
            )
            .scalars()
            .all()
        )

        for reminder in due:
            user = reminder.interview.application.user
            if not _channel_enabled(user, reminder.channel):
                logger.info(
                    "Skipping reminder id=%s: user %s disabled channel=%s",
                    reminder.id,
                    user.id,
                    reminder.channel.value,
                )
                success = True
            elif reminder.channel == ReminderChannel.EMAIL:
                success = _send_email_reminder(reminder)
            elif reminder.channel == ReminderChannel.PUSH:
                success = _send_push_reminder(db, reminder)
            else:
                success = _send_in_app_reminder(db, reminder)

            if success:
                reminder.sent_at = datetime.now(dt_timezone.utc)
                db.add(reminder)
                db.commit()
                sent_count += 1

        return sent_count
    finally:
        db.close()
