"""
Celery beat task: find interview_reminders rows that are due and unsent,
dispatch each on its `channel` (email, push, or in_app), stamp sent_at on
success. A channel the user has turned off (app/models/user_settings.py)
is resolved without dispatching - see _channel_enabled.

Runs outside a request, so it can't use the `get_db` FastAPI dependency
(that's a request-scoped generator) - opens/closes its own session
per run instead, same as any other out-of-band Celery job would.
"""

import logging
from datetime import datetime, timezone as dt_timezone
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.orm import Session, joinedload

from app.core.celery_app import celery_app
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
    """Returns (interview_type_label, when, company, position) - the four
    pieces both _build_email and _build_push format into their own
    channel-appropriate shape."""
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
    """Returns (title, body) for the Notification row (app/models/notification.py)
    - same interview_type/when/company/position pieces _build_email/
    _build_push already format, just into the bell feed's shorter shape."""
    interview_type, when, company, position = _interview_summary(reminder)
    title = f"Upcoming {interview_type} interview at {company}"
    body = f"{position} - {when}"
    return title, body


def _build_push(reminder: InterviewReminder) -> tuple[str, str, dict[str, str]]:
    """Returns (title, body, data). `data` drives the mobile client's
    tap-to-deep-link (see MOBILE_SUMMARY.md's push section) - keep keys
    stable, the client parses them by name."""
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
    """Whether `user` has this delivery channel turned on
    (app/models/user_settings.py). Checked at send time, not schedule
    time - see app/services/reminders.py's module docstring for why.

    IN_APP has no per-channel flag of its own, only EMAIL/PUSH do - both
    of those reach the user *outside* this app (an inbox, a device buzz/
    badge), so opting out of that intrusion independently of
    "notifications at all" is a real, distinct choice. The in-app feed is
    purely pull-based (a list you only see if you open the bell), so it's
    on whenever `notifications_enabled` (the master switch) is."""
    settings_row = user.settings
    if settings_row is None:
        # Fail-open only on a genuinely missing row (shouldn't happen -
        # every user gets one at registration/via migration backfill) -
        # never block a reminder just because the settings join came back
        # empty.
        return True
    if not settings_row.notifications_enabled:
        return False
    if channel == ReminderChannel.EMAIL:
        return settings_row.email_notifications_enabled
    if channel == ReminderChannel.PUSH:
        return settings_row.push_notifications_enabled
    return True


def _send_in_app_reminder(db: Session, reminder: InterviewReminder) -> bool:
    """Creates the Notification row the bell feed reads. Unlike email/push
    there's no external provider to fail against - a DB error propagates
    and the reminder stays unsent for retry next tick, same as any other
    exception in this loop."""
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
    """Returns True if this reminder should be marked sent (nothing left
    to retry), False if it should stay pending for the next beat tick.

    Fans out to every device the user has registered (Option A: the
    reminder row exists regardless of whether any device is registered -
    see sync_interview_reminders' docstring). Zero devices is treated as
    "nothing to send, nothing to retry" - True - not a failure; a token
    FCM reports as no-longer-valid gets pruned from device_tokens right
    here, so a stale install can't cause every future reminder to retry
    forever against a token that will never work again.
    """
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

    db.commit()  # persists any pruned (deleted) tokens above regardless
    # of the reminder's own outcome.

    if any_sent:
        return True
    # No successful send: either everything failed transiently (retry
    # next tick), or every token was invalid and just got pruned above
    # (nothing left to retry against - True).
    return not any_transient_failure


@celery_app.task(name="app.tasks.reminders_celery.send_due_reminders")
def send_due_reminders() -> int:
    """Returns the number of reminders successfully sent/resolved
    (across all channels), for logging / test assertions."""
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
                # User has this channel (or notifications overall) turned
                # off - mark resolved without dispatching, same shape as
                # the "zero devices -> nothing to send, nothing to retry"
                # handling below for push, just gated on a preference
                # instead of device-token existence.
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
                # Commit per-reminder rather than batching the whole loop:
                # one bad send (or a crash mid-loop) shouldn't leave every
                # other already-sent reminder in this run un-stamped,
                # which would re-send them all on the next tick.
                db.commit()
                sent_count += 1

        return sent_count
    finally:
        db.close()
