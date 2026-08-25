"""
Join row linking a Contact to an Application - many-to-many, since the
same real person (e.g. a recruiter reaching out about two different
roles) can now be linked to multiple applications and a Contact no
longer belongs to exactly one Application (see app/models/contact.py's
module docstring for the rationale).

An explicit mapped class rather than a plain `secondary=` table so it
gets its own id/timestamps (attached_at = created_at) and can be queried
directly (e.g. "contacts attached to this application, most-recently-
attached first") without complicating Contact/Application's own
relationships. Mirrors app/models/application_document.py exactly.
"""

import uuid
from typing import TYPE_CHECKING

from sqlalchemy import ForeignKey, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base_class import Base, TimestampMixin, UUIDMixin

if TYPE_CHECKING:
    from app.models.application import Application
    from app.models.contact import Contact


class ApplicationContact(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "application_contacts"
    __table_args__ = (
        UniqueConstraint("application_id", "contact_id", name="uq_application_contact"),
    )

    application_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("applications.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    contact_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("contacts.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    application: Mapped["Application"] = relationship(
        back_populates="application_contacts"
    )
    contact: Mapped["Contact"] = relationship(back_populates="application_contacts")
