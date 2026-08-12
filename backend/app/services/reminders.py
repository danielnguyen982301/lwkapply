"""
Keeps `interview_reminders` rows in sync with an `Interview`'s
scheduled_at/result. Called from the interview CRUD endpoints
(app/api/v1/endpoints/interviews.py) on create/update - not a Celery
task itself, this just writes the rows the beat task
(app/tasks/reminders.py) later reads and sends.

MVP behaviour (see TODO.md - multi-lead-time is explicitly deferred):
one *pending* (unsent) reminder per interview **per channel**, at
`settings.REMINDER_LEAD_HOURS` before `scheduled_at`. Already-sent
reminders (`sent_at IS NOT NULL`) are historical record and are never
touched here - only each channel's pending row gets created/moved/
removed.

Phase B addition: a PUSH row is now created unconditionally alongside
EMAIL, regardless of whether the user has any registered device token
yet (Option A from the Phase B planning discussion - see git history/
conversation, not written down elsewhere). This keeps this function's
only responsibility "does this interview need a reminder", with zero
knowledge of device-token state - app/tasks/reminders.py's send loop is
what decides a channel has nothing to send to, and that's a send-time
concern, not a scheduling-time one.
"""

from datetime import datetime, timedelta, timezone as dt_timezone

from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.interview import Interview, InterviewResult
from app.models.interview_reminder import InterviewReminder, ReminderChannel

# Every channel Phase A+B support gets a pending reminder row per
# interview - see module docstring on why PUSH is unconditional here.
_ACTIVE_CHANNELS = (ReminderChannel.EMAIL, ReminderChannel.PUSH)


def _compute_remind_at(scheduled_at: datetime) -> datetime:
    return scheduled_at - timedelta(hours=settings.REMINDER_LEAD_HOURS)


def _get_pending_reminder(
    db: Session, interview_id, channel: ReminderChannel
) -> InterviewReminder | None:
    return (
        db.query(InterviewReminder)
        .filter(
            InterviewReminder.interview_id == interview_id,
            InterviewReminder.channel == channel,
            InterviewReminder.sent_at.is_(None),
        )
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
        candidate = _compute_remind_at(interview.scheduled_at)
        now = datetime.now(dt_timezone.utc)
        # Either a same-day/short-notice interview, or one rescheduled to
        # be sooner than the lead time - too late for this lead time to
        # mean anything. Deliberately not sending an immediate "reminder"
        # in this case rather than firing one off right away; revisit if
        # product wants a "starting soon" variant later.
        remind_at = candidate if candidate > now else None

    for channel in _ACTIVE_CHANNELS:
        _sync_channel(db, interview, channel, remind_at)
