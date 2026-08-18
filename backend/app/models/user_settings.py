"""
Per-user preferences, kept in their own 1:1 table rather than as columns
on User - see BACKEND_SUMMARY.md / the account-settings planning notes.
users is read on every authenticated request and should stay focused on
identity/auth; preferences are a separate, independently-growing concern,
same "separate table per concern" instinct as Document/ApplicationDocument
or Interview/InterviewReminder.

Every user should always have exactly one row (created at registration -
see app/api/v1/endpoints/auth.py::register - and backfilled for
pre-existing users by the migration that introduces this table), so call
sites can generally treat `user.settings` as present rather than
optional; the one place that reads it for real scheduling/send logic
(app/services/reminders.py, app/tasks/reminders.py) still fails open on a
genuinely missing row rather than trusting that invariant blindly.
"""

import uuid
from typing import TYPE_CHECKING

from sqlalchemy import ForeignKey
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base_class import Base, TimestampMixin, UUIDMixin

if TYPE_CHECKING:
    from app.models.user import User


class UserSettings(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "user_settings"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        unique=True,
        nullable=False,
        index=True,
    )
    # NULL = "use settings.REMINDER_LEAD_HOURS" (today's global default) -
    # every existing account keeps behaving exactly as it does now until a
    # user explicitly sets an override.
    reminder_lead_hours: Mapped[int | None] = mapped_column(nullable=True)

    # Master switch - False suppresses every channel (including the
    # in-app feed, which has no toggle of its own - see below) regardless
    # of the per-channel flags. All default True: existing users' behavior
    # (reminders currently always send) doesn't change until someone
    # explicitly opts out.
    notifications_enabled: Mapped[bool] = mapped_column(default=True, nullable=False)
    # Only email/push get their own toggle - both reach the user *outside*
    # this app (an inbox, a device buzz/badge), so opting out of that
    # intrusion independently of "notifications at all" is a real,
    # distinct choice. The in-app feed is purely pull-based (a list you
    # only see if you open the bell) with no external interruption to opt
    # out of, so it deliberately has no per-channel flag - it's on
    # whenever `notifications_enabled` is, same as GitHub/Slack's
    # notification center vs. their separate email/push settings.
    email_notifications_enabled: Mapped[bool] = mapped_column(
        default=True, nullable=False
    )
    push_notifications_enabled: Mapped[bool] = mapped_column(
        default=True, nullable=False
    )

    user: Mapped["User"] = relationship(back_populates="settings")
