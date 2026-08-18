import enum
import uuid
from typing import TYPE_CHECKING

from sqlalchemy import Enum, ForeignKey, String
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base_class import Base, TimestampMixin, UUIDMixin

if TYPE_CHECKING:
    from app.models.application_document import ApplicationDocument
    from app.models.user import User


class DocumentType(str, enum.Enum):
    RESUME = "resume"
    COVER_LETTER = "cover_letter"
    OTHER = "other"


class Document(Base, UUIDMixin, TimestampMixin):
    """
    Top-level, user-owned resource - like ResumeAnalysis/AtsScore, not
    nested under a single Application. A document can be attached to zero,
    one, or several applications (see ApplicationDocument); ownership is
    therefore a direct user_id FK rather than derived through an
    application join, since an unattached document has no application to
    derive it from.
    """

    __tablename__ = "documents"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    file_name: Mapped[str] = mapped_column(String(500), nullable=False)
    file_url: Mapped[str] = mapped_column(String(1000), nullable=False)
    file_type: Mapped[DocumentType] = mapped_column(
        Enum(
            DocumentType,
            name="document_type",
            values_callable=lambda enum_cls: [e.value for e in enum_cls],
        ),
        server_default=DocumentType.OTHER,
    )

    user: Mapped["User"] = relationship()
    # Deleting a document should drop its application links, not the
    # applications themselves - delete-orphan only, no cascade onto
    # Application (mirrors the ondelete="CASCADE" FK on
    # ApplicationDocument.document_id).
    application_documents: Mapped[list["ApplicationDocument"]] = relationship(
        back_populates="document", cascade="all, delete-orphan"
    )
