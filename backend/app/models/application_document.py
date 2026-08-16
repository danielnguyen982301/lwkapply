"""
Join row linking a Document to an Application - many-to-many, since the
same resume/cover letter can now be reused across multiple applications
and a Document no longer belongs to exactly one Application (see
app/models/document.py's module docstring for the rationale).

An explicit mapped class rather than a plain `secondary=` table so it
gets its own id/timestamps (attached_at = created_at) and can be queried
directly (e.g. "documents attached to this application, most-recently-
attached first") without complicating Document/Application's own
relationships.
"""

import uuid
from typing import TYPE_CHECKING

from sqlalchemy import ForeignKey, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base_class import Base, TimestampMixin, UUIDMixin

if TYPE_CHECKING:
    from app.models.application import Application
    from app.models.document import Document


class ApplicationDocument(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "application_documents"
    __table_args__ = (
        UniqueConstraint(
            "application_id", "document_id", name="uq_application_document"
        ),
    )

    application_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("applications.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    document_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("documents.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    application: Mapped["Application"] = relationship(
        back_populates="application_documents"
    )
    document: Mapped["Document"] = relationship(back_populates="application_documents")
