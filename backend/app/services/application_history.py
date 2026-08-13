"""
Records Application.status transitions into application_status_history.

Called from the Application create/update endpoints
(app/api/v1/endpoints/applications.py), inside the same transaction as
the write that caused the transition - mirrors
app/services/reminders.py's sync_interview_reminders() pattern: this
module only ever calls db.add(), never db.commit(); the caller's
existing commit covers it.

See app/models/application_status_history.py's module docstring for why
this table exists and what it's deliberately NOT used for yet.
"""

from sqlalchemy.orm import Session

from app.models.application import Application, ApplicationStatus
from app.models.application_status_history import ApplicationStatusHistory


def record_status_change(
    db: Session,
    application: Application,
    from_status: ApplicationStatus | None,
    to_status: ApplicationStatus,
) -> None:
    """Insert one history row for a status transition.

    `from_status=None` marks the row written when an application is
    first created - see ApplicationStatusHistory's own docstring.

    A no-op call (from_status == to_status) is silently ignored rather
    than inserting a row. Call sites should already be filtering this
    out themselves (only calling when status is actually present in an
    update payload and differs from the stored value) - this is a
    second line of defense, not the primary guard, so a future call
    site can't accidentally spam identical rows.
    """
    if from_status == to_status:
        return

    db.add(
        ApplicationStatusHistory(
            application_id=application.id,
            from_status=from_status,
            to_status=to_status,
        )
    )
