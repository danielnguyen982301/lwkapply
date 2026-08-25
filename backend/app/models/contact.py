"""
Top-level, user-owned resource - like Document (see its module docstring
for the parallel rationale). A contact can be attached to zero, one, or
several applications (see ApplicationContact); ownership is therefore a
direct user_id FK rather than derived through an application join, since
a contact kept around after its only application was deleted has no
application left to derive it from.
"""

import uuid
from typing import TYPE_CHECKING

from sqlalchemy import ForeignKey, String
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base_class import Base, TimestampMixin, UUIDMixin

if TYPE_CHECKING:
    from app.models.application_contact import ApplicationContact
    from app.models.user import User


class Contact(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "contacts"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    title: Mapped[str | None] = mapped_column(String(255), nullable=True)
    email: Mapped[str | None] = mapped_column(String(255), nullable=True)
    linkedin_url: Mapped[str | None] = mapped_column(String(500), nullable=True)

    user: Mapped["User"] = relationship()
    # Deleting a contact should drop its application links, not the
    # applications themselves - delete-orphan only, no cascade onto
    # Application (mirrors the ondelete="CASCADE" FK on
    # ApplicationContact.contact_id).
    application_contacts: Mapped[list["ApplicationContact"]] = relationship(
        back_populates="contact", cascade="all, delete-orphan"
    )
