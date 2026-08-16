import enum
import uuid
from datetime import date
from typing import TYPE_CHECKING

from sqlalchemy import Date, Enum, ForeignKey, Integer, String, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base_class import Base, TimestampMixin, UUIDMixin

if TYPE_CHECKING:
    from app.models.application_document import ApplicationDocument
    from app.models.application_status_history import ApplicationStatusHistory
    from app.models.contact import Contact
    from app.models.interview import Interview
    from app.models.user import User


class ApplicationStatus(str, enum.Enum):
    SAVED = "saved"
    APPLIED = "applied"
    PHONE_SCREEN = "phone_screen"
    INTERVIEWING = "interviewing"
    OFFER = "offer"
    REJECTED = "rejected"
    WITHDRAWN = "withdrawn"
    ACCEPTED = "accepted"


class Application(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "applications"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    company: Mapped[str] = mapped_column(String(255), nullable=False)
    position: Mapped[str] = mapped_column(String(255), nullable=False)
    # Optional user-chosen label to tell apart multiple applications to the
    # same company/position (e.g. re-applying after a rejection, or two
    # different postings with the same title) - falls back to
    # "company - position" for display wherever it's blank, purely a
    # client-side concern (see webapp's application-ui.ts).
    application_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    location: Mapped[str | None] = mapped_column(String(255), nullable=True)
    status: Mapped[ApplicationStatus] = mapped_column(
        Enum(
            ApplicationStatus,
            name="application_status",
            values_callable=lambda enum_cls: [e.value for e in enum_cls],
        ),
        default=ApplicationStatus.SAVED,
        nullable=False,
        index=True,
    )
    salary_min: Mapped[int | None] = mapped_column(Integer, nullable=True)
    salary_max: Mapped[int | None] = mapped_column(Integer, nullable=True)
    applied_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    job_url: Mapped[str | None] = mapped_column(String(1000), nullable=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)

    user: Mapped["User"] = relationship(back_populates="applications")
    interviews: Mapped[list["Interview"]] = relationship(
        back_populates="application", cascade="all, delete-orphan"
    )
    # Deleting an application detaches its documents (drops the join
    # rows) - it never deletes the documents themselves. Documents are
    # user-owned resources in their own right (see app/models/document.py)
    # and live on in the user's document library regardless of what
    # happens to any application they were ever attached to.
    application_documents: Mapped[list["ApplicationDocument"]] = relationship(
        back_populates="application", cascade="all, delete-orphan"
    )
    contacts: Mapped[list["Contact"]] = relationship(
        back_populates="application", cascade="all, delete-orphan"
    )
    # Append-only audit log of status transitions - see
    # app/models/application_status_history.py's module docstring.
    # Ordered oldest-first so a timeline render doesn't need to reverse
    # it; nothing currently reads this relationship (the endpoints write
    # history rows directly via app/services/application_history.py,
    # not through this collection), but it's here for parity with the
    # other three and for any future timeline endpoint.
    status_history: Mapped[list["ApplicationStatusHistory"]] = relationship(
        back_populates="application",
        cascade="all, delete-orphan",
        order_by="ApplicationStatusHistory.created_at",
    )
