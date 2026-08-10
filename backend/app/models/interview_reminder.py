"""
Interview reminder rows — Phase A of the reminder system (see TODO.md's
"Reminder system" plan under Backend > Interviews).

One row per (interview, lead time, channel). Deliberately a separate
table rather than a single `reminder_sent_at` column on `Interview`:

- Supports more than one reminder per interview (e.g. 24h and 1h before)
  without a schema change later.
- `channel` (`email` today, `push` in Phase B) carries straight through
  into Phase B's FCM work with no migration needed then either — the
  Celery beat task added in this pass already dispatches on `channel`,
  it just only ever inserts `EMAIL` rows for now.

`sent_at` is nullable and stamped by the beat task once a send succeeds.
It is the idempotency guard: the task only ever selects
`remind_at <= now() AND sent_at IS NULL`, so a re-run (e.g. beat firing
twice in the same window, or a retried task) can't double-send. This is
NOT safe against two *concurrent* beat workers on different nodes racing
the same row — see TODO.md's note that Celery-beat-on-multiple-nodes
protection is out of scope until this is ever run horizontally scaled
(would need a single scheduler or a Redis lock).
"""

import enum
import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, Enum, ForeignKey
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base_class import Base, TimestampMixin, UUIDMixin

if TYPE_CHECKING:
    from app.models.interview import Interview


class ReminderChannel(str, enum.Enum):
    EMAIL = "email"
    PUSH = "push"  # unused until Phase B (FCM) - see TODO.md


class InterviewReminder(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "interview_reminders"

    interview_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("interviews.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    remind_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, index=True
    )
    sent_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    channel: Mapped[ReminderChannel] = mapped_column(
        Enum(
            ReminderChannel,
            name="reminder_channel",
            values_callable=lambda enum_cls: [e.value for e in enum_cls],
        ),
        server_default=ReminderChannel.EMAIL,
        nullable=False,
    )

    interview: Mapped["Interview"] = relationship(back_populates="reminders")
