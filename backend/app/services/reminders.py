"""
Keeps `interview_reminders` rows in sync with an `Interview`'s
scheduled_at/result. Called from the interview CRUD endpoints
(app/api/v1/endpoints/interviews.py) on create/update - not a Celery
task itself, this just writes the rows the beat task
(app/tasks/reminders.py) later reads and sends.

MVP behaviour (see TODO.md - multi-lead-time is explicitly deferred):
one *pending* (unsent) reminder per interview **per channel**, at
`user.settings.reminder_lead_hours` before `scheduled_at` if the owning
user has set an override, else `settings.REMINDER_LEAD_HOURS` (the global
default - see app/models/user_settings.py). Already-sent reminders
(`sent_at IS NOT NULL`) are historical record and are never touched here -
only each channel's pending row gets created/moved/removed.

Phase B addition: a PUSH row is now created unconditionally alongside
EMAIL, regardless of whether the user has any registered device token
yet (Option A from the Phase B planning discussion - see git history/
conversation, not written down elsewhere). This keeps this function's
only responsibility "does this interview need a reminder", with zero
knowledge of device-token state - app/tasks/reminders.py's send loop is
what decides a channel has nothing to send to, and that's a send-time
concern, not a scheduling-time one. The same reasoning now extends to
IN_APP (drives the Notification feed, app/models/notification.py) and to
every channel's on/off preference (app/models/user_settings.py) - all of
it is enforced at send time, not here.
"""

from datetime import datetime, timedelta, timezone as dt_timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.interview import Interview, InterviewResult
from app.models.interview_reminder import InterviewReminder, ReminderChannel
from app.models.user import User

# Every channel Phase A+B (+ the in-app feed) support gets a pending
# reminder row per interview - see module docstring on why PUSH is
# unconditional here. IN_APP is the same story: whether a channel is
# actually *enabled* for this user (app/models/user_settings.py) is a
# send-time concern (app/tasks/reminders.py), not decided here.
_ACTIVE_CHANNELS = (ReminderChannel.EMAIL, ReminderChannel.PUSH, ReminderChannel.IN_APP)


def _compute_remind_at(scheduled_at: datetime, user: User) -> datetime:
    # NULL/unset user.settings.reminder_lead_hours falls back to the
    # global default - see app/models/user_settings.py.
    lead_hours = (
        user.settings.reminder_lead_hours
        if user.settings and user.settings.reminder_lead_hours
        else settings.REMINDER_LEAD_HOURS
    )
    return scheduled_at - timedelta(hours=lead_hours)


def _get_pending_reminder(
    db: Session, interview_id, channel: ReminderChannel
) -> InterviewReminder | None:
    return (
        db.execute(
            select(InterviewReminder).where(
                InterviewReminder.interview_id == interview_id,
                InterviewReminder.channel == channel,
                InterviewReminder.sent_at.is_(None),
            )
        )
        .scalars()
        .first()
    )


def _sync_channel(
    db: Session,
    interview: Interview,
    channel: ReminderChannel,
    remind_at: datetime | None,
) -> None:
    """`remind_at=None` means "this interview shouldn't have a pending
    reminder on this channel right now" (cancelled, or too-soon-to-mean-
    anything - see sync_interview_reminders below)."""
    pending = _get_pending_reminder(db, interview.id, channel)

    if remind_at is None:
        if pending:
            db.delete(pending)
        return

    if pending:
        pending.remind_at = remind_at
        db.add(pending)
    else:
        db.add(
            InterviewReminder(
                interview_id=interview.id,
                remind_at=remind_at,
                channel=channel,
            )
        )


def sync_interview_reminders(db: Session, interview: Interview) -> None:
    """Call after every create/update of an Interview, inside the same
    transaction the caller is about to commit (this function itself
    calls db.add()/db.delete() but not db.commit() - the endpoint's
    existing commit covers it, same as any other field change)."""
    if interview.result == InterviewResult.CANCELLED:
        remind_at = None
    else:
        candidate = _compute_remind_at(
            interview.scheduled_at, interview.application.user
        )
        now = datetime.now(dt_timezone.utc)
        # Either a same-day/short-notice interview, or one rescheduled to
        # be sooner than the lead time - too late for this lead time to
        # mean anything. Deliberately not sending an immediate "reminder"
        # in this case rather than firing one off right away; revisit if
        # product wants a "starting soon" variant later.
        remind_at = candidate if candidate > now else None

    for channel in _ACTIVE_CHANNELS:
        _sync_channel(db, interview, channel, remind_at)
