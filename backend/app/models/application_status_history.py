"""
Append-only audit log of Application.status transitions.

Not currently read by any analytics endpoint. Phase 5's funnel/summary
metrics query Application.status directly - a current-state snapshot,
which is immune to a user accidentally toggling status back and forth
(e.g. dragging the wrong Kanban column, then dragging it back): the
snapshot just reflects wherever the application ended up, same as if
the mis-click never happened.

This table exists so that decision isn't permanent. If a future metric
needs a true funnel ("did this application ever reach interviewing",
not just "is it currently there"), a per-application timeline, or
time-in-stage duration, the data is already being collected rather than
needing a backfill from a point where it wasn't. Any aggregation that
reads this table later should account for accidental multi-flip
sequences (e.g. a minimum-dwell-time / debounce rule before counting a
transition as "real") rather than naively counting every row - a
same-session correction shouldn't count as ever having reached that
stage. See the Phase 5 analytics planning discussion (not written down
elsewhere) for the full reasoning.

One row per transition, written by
app/services/application_history.py::record_status_change(), called
from the Application create/update endpoints in the same transaction as
the write that caused it - mirrors app/services/reminders.py's
sync_interview_reminders() pattern: the service only calls db.add(),
the endpoint's existing db.commit() covers it.

`created_at` (from TimestampMixin) IS the transition timestamp - there's
no separate `changed_at` column, since these rows are never updated
after insert. `updated_at` is unused but kept for consistency with
every other model in this codebase using both mixins together (see
InterviewReminder for the same treatment).
"""

import uuid
from typing import TYPE_CHECKING

from sqlalchemy import ForeignKey
from sqlalchemy.dialects.postgresql import ENUM, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base_class import Base, TimestampMixin, UUIDMixin
from app.models.application import ApplicationStatus

if TYPE_CHECKING:
    from app.models.application import Application

# Reuses the "application_status" Postgres enum type Application.status
# already declares - same name, same values_callable, and critically
# create_type=False, since this type already exists in the database.
#
# Must be sqlalchemy.dialects.postgresql.ENUM here, not the generic
# sqlalchemy.Enum - create_type is only formally defined on the
# Postgres-specific class. The generic Enum accepts create_type as a
# stray kwarg and stores it, but doesn't reliably carry it through when
# adapting itself into the Postgres-native DDL implementation that
# actually emits (or skips) CREATE TYPE - confirmed the hard way: using
# generic Enum here reproduced the exact "type already exists" failure
# this comment is warning about, even with create_type=False set.
# postgresql.ENUM IS the class that implements the create_type gate, so
# there's no adaptation step to lose it across.
_application_status_enum = ENUM(
    ApplicationStatus,
    name="application_status",
    values_callable=lambda enum_cls: [e.value for e in enum_cls],
    create_type=False,
)


class ApplicationStatusHistory(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "application_status_history"

    application_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("applications.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    # Null only on the row written when an application is first created
    # - there's no "from" status for a brand-new application, only a
    # starting to_status (whatever ApplicationCreate.status resolved to,
    # default ApplicationStatus.SAVED - see ApplicationBase).
    from_status: Mapped[ApplicationStatus | None] = mapped_column(
        _application_status_enum, nullable=True
    )
    to_status: Mapped[ApplicationStatus] = mapped_column(
        _application_status_enum, nullable=False
    )

    application: Mapped["Application"] = relationship(back_populates="status_history")
