"""
In-app notification feed (the "bell icon") - distinct from UserSettings:
that table holds delivery *preferences*, this table holds the actual
notification *events* shown to a user, each with its own read/unread
state.

Only one producer exists today: app/tasks/reminders.py's
send_due_reminders, which creates one row per due IN_APP-channel
InterviewReminder (see ReminderChannel in app/models/interview_reminder.py)
- same scheduling/idempotency machinery as the email/push channels,
just writing a Notification row instead of calling an external
provider. NotificationType is deliberately a single value for now
rather than a speculative set - add more as real producers appear.
"""

import enum
import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, Enum, ForeignKey, Index, String, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base_class import Base, TimestampMixin, UUIDMixin

if TYPE_CHECKING:
    from app.models.user import User


class NotificationType(str, enum.Enum):
    INTERVIEW_REMINDER = "interview_reminder"


class Notification(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "notifications"
    __table_args__ = (
        # The bell badge's unread-count query and the list view's
        # status=unread/read filter both filter on exactly this pair - a
        # plain user_id index alone would still need a filter scan over
        # every already-/not-yet-read notification too.
        Index("ix_notifications_user_id_read_at", "user_id", "read_at"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    type: Mapped[NotificationType] = mapped_column(
        Enum(
            NotificationType,
            name="notification_type",
            values_callable=lambda enum_cls: [e.value for e in enum_cls],
        ),
        nullable=False,
    )
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    # Optional deep-link targets for the bell UI. Nullable/independent
    # rather than a single polymorphic "entity_id" - only interview_id/
    # application_id exist today since INTERVIEW_REMINDER is the only
    # producer; add more FKs here if/when a second type needs them, not
    # preemptively.
    application_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("applications.id", ondelete="CASCADE"),
        nullable=True,
    )
    interview_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("interviews.id", ondelete="CASCADE"),
        nullable=True,
    )
    read_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    user: Mapped["User"] = relationship(back_populates="notifications")
