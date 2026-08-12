"""
Registered push-notification device tokens (Phase B — see TODO.md's
reminder-system plan). One row per physical device install, keyed by the
FCM token itself rather than by (user_id, platform), since:

- `token` is already globally unique per app install (FCM's contract).
- The same physical device can log out and a different user can log
  into it - the upsert in app/api/v1/endpoints/users.py reassigns
  `user_id` on that token rather than accumulating stale rows for the
  previous owner.

No cross-application ownership check needed here (unlike
Interview/Document/Contact) - device tokens belong directly to a User,
one hop, same as `Application.user_id`.
"""

import enum
import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, Enum, ForeignKey, String
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base_class import Base, TimestampMixin, UUIDMixin

if TYPE_CHECKING:
    from app.models.user import User


class DevicePlatform(str, enum.Enum):
    ANDROID = "android"
    IOS = "ios"  # accepted by the schema/model now; no mobile client sends
    # it yet - iOS push is deferred on the paid Apple Developer Program
    # requirement, see TODO.md. Modeling it here now avoids a second
    # migration once iOS support lands.


class DeviceToken(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "device_tokens"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    platform: Mapped[DevicePlatform] = mapped_column(
        Enum(
            DevicePlatform,
            name="device_platform",
            values_callable=lambda enum_cls: [e.value for e in enum_cls],
        ),
        nullable=False,
    )
    # Unique, not (user_id, token) unique - see module docstring for why
    # a token is reassigned to whichever user most recently registered it
    # rather than living twice.
    token: Mapped[str] = mapped_column(String(4096), nullable=False, unique=True)
    last_seen_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )

    user: Mapped["User"] = relationship(back_populates="device_tokens")
