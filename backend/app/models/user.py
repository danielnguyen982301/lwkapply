import enum

from typing import TYPE_CHECKING

from sqlalchemy import Enum, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base_class import Base, TimestampMixin, UUIDMixin

if TYPE_CHECKING:
    # Import only for type-checkers (Pylance/mypy). Doing this at runtime
    # would create a circular import, since Application imports User back.
    from app.models.application import Application


class UserRole(str, enum.Enum):
    USER = "user"
    ADMIN = "admin"


class User(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "users"

    email: Mapped[str] = mapped_column(
        String(255), unique=True, index=True, nullable=False
    )
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    first_name: Mapped[str] = mapped_column(String(100), nullable=False)
    last_name: Mapped[str] = mapped_column(String(100), nullable=False)
    avatar_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    role: Mapped[UserRole] = mapped_column(
        Enum(
            UserRole,
            name="user_role",
            values_callable=lambda enum_cls: [e.value for e in enum_cls],
        ),
        default=UserRole.USER,
        nullable=False,
    )
    is_active: Mapped[bool] = mapped_column(default=True, nullable=False)
    # IANA tz name (e.g. "America/New_York"), reported by the client's own
    # Intl.DateTimeFormat()/flutter_timezone at register/login/refresh -
    # see TODO.md's reminder-system plan for why (client-reported beats
    # IP-geolocation inference, and needs no dedicated UI). Nullable; code
    # that reads this always falls back to UTC rather than assuming it's
    # set (e.g. accounts created before this column existed).
    timezone: Mapped[str | None] = mapped_column(String(64), nullable=True)

    applications: Mapped[list["Application"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )
