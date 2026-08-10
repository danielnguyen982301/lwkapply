"""
Celery beat task: find interview_reminders rows that are due and unsent,
send an email for each, stamp sent_at on success.

NOTE: imports `SessionLocal` from app.db.session, following the standard
`sessionmaker(...)` naming every other FastAPI+SQLAlchemy project in this
shape uses - app/db/session.py wasn't in the files I was given for this
pass, so if it exports a differently-named sessionmaker, update this one
import accordingly. Everything downstream of that import is independent
of the exact name.

Runs outside a request, so it can't use the `get_db` FastAPI dependency
(that's a request-scoped generator) - opens/closes its own session
per run instead, same as any other out-of-band Celery job would.
"""

import logging
from datetime import datetime, timezone as dt_timezone
from zoneinfo import ZoneInfo

from sqlalchemy import and_
from sqlalchemy.orm import Session, joinedload

from app.core.celery_app import celery_app
from app.db.session import SessionLocal
from app.models.application import Application
from app.models.interview import Interview
from app.models.interview_reminder import InterviewReminder, ReminderChannel
from app.services.email import send_email

logger = logging.getLogger(__name__)


def _format_scheduled_at(scheduled_at: datetime, user_timezone: str | None) -> str:
    tz = ZoneInfo(user_timezone) if user_timezone else dt_timezone.utc
    localized = scheduled_at.astimezone(tz)
    label = "UTC" if tz is dt_timezone.utc else localized.tzname() or user_timezone
    return f"{localized.strftime('%A, %B %-d, %Y at %-I:%M %p')} ({label})"


def _build_email(reminder: InterviewReminder) -> tuple[str, str, str]:
    """Returns (subject, html, text)."""
    interview = reminder.interview
    application = interview.application
    user = application.user

    when = _format_scheduled_at(interview.scheduled_at, user.timezone)
    interview_type = interview.type.value.replace("_", " ").title()
    subject = f"Upcoming interview: {application.company} ({interview_type})"

    text = (
        f"Reminder: you have a {interview_type} interview for "
        f"{application.position} at {application.company}.\n\n"
        f"When: {when}\n\n"
        f"View details: {_application_url(application.id)}"
    )
    html = (
        f"<p>Reminder: you have a <strong>{interview_type}</strong> interview "
        f"for <strong>{application.position}</strong> at "
        f"<strong>{application.company}</strong>.</p>"
        f"<p><strong>When:</strong> {when}</p>"
        f'<p><a href="{_application_url(application.id)}">View application</a></p>'
    )
    return subject, html, text


def _application_url(application_id) -> str:
    from app.core.config import settings

    return f"{settings.FRONTEND_URL}/applications/{application_id}"


@celery_app.task(name="app.tasks.reminders.send_due_reminders")
def send_due_reminders() -> int:
    """Returns the number of reminders successfully sent, for logging /
    test assertions."""
    db: Session = SessionLocal()
    sent_count = 0
    try:
        now = datetime.now(dt_timezone.utc)
        due = (
            db.query(InterviewReminder)
            .options(
                joinedload(InterviewReminder.interview)
                .joinedload(Interview.application)
                .joinedload(Application.user)
            )
            .filter(
                and_(
                    InterviewReminder.remind_at <= now,
                    InterviewReminder.sent_at.is_(None),
                    InterviewReminder.channel == ReminderChannel.EMAIL,
                )
            )
            .all()
        )

        for reminder in due:
            application = reminder.interview.application
            user = application.user
            subject, html, text = _build_email(reminder)

            success = send_email(to=user.email, subject=subject, html=html, text=text)
            if success:
                reminder.sent_at = datetime.now(dt_timezone.utc)
                db.add(reminder)
                # Commit per-reminder rather than batching the whole loop:
                # one bad send (or a crash mid-loop) shouldn't leave every
                # other already-sent reminder in this run un-stamped,
                # which would re-send them all on the next tick.
                db.commit()
                sent_count += 1
            else:
                logger.error(
                    "Failed to send interview reminder id=%s to=%s",
                    reminder.id,
                    user.email,
                )

        return sent_count
    finally:
        db.close()
