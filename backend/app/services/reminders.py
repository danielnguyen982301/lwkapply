"""
Keeps `interview_reminders` rows in sync with an `Interview`'s
scheduled_at/result. Called from the interview CRUD endpoints
(app/api/v1/endpoints/interviews.py) on create/update - not a Celery
task itself, this just writes the rows the beat task
(app/tasks/reminders.py) later reads and sends.

MVP behaviour (see TODO.md - multi-lead-time is explicitly deferred):
one *pending* (unsent) EMAIL reminder per interview at any time, at
`settings.REMINDER_LEAD_HOURS` before `scheduled_at`. Already-sent
reminders (`sent_at IS NOT NULL`) are historical record and are never
touched here - only the pending one gets created/moved/removed.
"""

from datetime import datetime, timedelta, timezone as dt_timezone

from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.interview import Interview, InterviewResult
from app.models.interview_reminder import InterviewReminder, ReminderChannel


def _compute_remind_at(scheduled_at: datetime) -> datetime:
    return scheduled_at - timedelta(hours=settings.REMINDER_LEAD_HOURS)


def _get_pending_reminder(db: Session, interview_id) -> InterviewReminder | None:
    return (
        db.query(InterviewReminder)
        .filter(
            InterviewReminder.interview_id == interview_id,
            InterviewReminder.sent_at.is_(None),
        )
        .first()
    )


def sync_interview_reminders(db: Session, interview: Interview) -> None:
    """Call after every create/update of an Interview, inside the same
    transaction the caller is about to commit (this function itself
    calls db.add()/db.delete() but not db.commit() - the endpoint's
    existing commit covers it, same as any other field change)."""
    pending = _get_pending_reminder(db, interview.id)

    if interview.result == InterviewResult.CANCELLED:
        if pending:
            db.delete(pending)
        return

    remind_at = _compute_remind_at(interview.scheduled_at)
    now = datetime.now(dt_timezone.utc)

    if remind_at <= now:
        # Either a same-day/short-notice interview, or one rescheduled to
        # be sooner than the lead time - too late for this lead time to
        # mean anything. Deliberately not sending an immediate "reminder"
        # in this case rather than firing one off right away; revisit if
        # product wants a "starting soon" variant later.
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
                channel=ReminderChannel.EMAIL,
            )
        )
