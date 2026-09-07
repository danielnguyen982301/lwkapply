import enum
import uuid
from datetime import date
from typing import TYPE_CHECKING

from sqlalchemy import Date, Enum, ForeignKey, Index, Integer, String, Text, text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base_class import Base, TimestampMixin, UUIDMixin

if TYPE_CHECKING:
    from app.models.application_contact import ApplicationContact
    from app.models.application_document import ApplicationDocument
    from app.models.application_status_history import ApplicationStatusHistory
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


class SalaryCurrency(str, enum.Enum):
    USD = "USD"
    EUR = "EUR"
    GBP = "GBP"
    CAD = "CAD"
    AUD = "AUD"
    NZD = "NZD"
    CHF = "CHF"
    SEK = "SEK"
    NOK = "NOK"
    DKK = "DKK"
    ISK = "ISK"
    PLN = "PLN"
    CZK = "CZK"
    HUF = "HUF"
    RON = "RON"
    UAH = "UAH"
    RUB = "RUB"
    TRY = "TRY"
    ILS = "ILS"
    AED = "AED"
    SAR = "SAR"
    EGP = "EGP"
    NGN = "NGN"
    KES = "KES"
    ZAR = "ZAR"
    INR = "INR"
    PKR = "PKR"
    BDT = "BDT"
    CNY = "CNY"
    JPY = "JPY"
    KRW = "KRW"
    TWD = "TWD"
    HKD = "HKD"
    SGD = "SGD"
    MYR = "MYR"
    THB = "THB"
    VND = "VND"
    IDR = "IDR"
    PHP = "PHP"
    BRL = "BRL"
    MXN = "MXN"
    ARS = "ARS"
    CLP = "CLP"
    COP = "COP"


class Application(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "applications"
    __table_args__ = (
        # At most one row per (user, source, external_id) - only
        # enforced where both are actually set, so ordinary manually
        # created rows (both null) are never compared against each
        # other. Lets PUT /applications/by-external-id treat a unique
        # violation as "someone already created this concurrently"
        # rather than trusting a check-then-insert alone.
        Index(
            "ix_applications_user_source_external_id",
            "user_id",
            "source",
            "external_id",
            unique=True,
            postgresql_where=text("source IS NOT NULL AND external_id IS NOT NULL"),
        ),
    )

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
    # Where this row was created from - "manual" (or null) for the normal
    # in-app create flow, otherwise a free-form site slug like
    # "vietnamworks" or "linkedin" from a browser-extension quick-capture.
    # Deliberately a free string rather than an enum: new sites should be
    # addable on the client side without a migration.
    source: Mapped[str | None] = mapped_column(String(100), nullable=True)
    # The source system's own identifier for this posting (e.g.
    # VietnamWorks' internal job id) - paired with `source` as the real
    # identity of a row a browser extension is tracking, since job_url
    # is not a reliable natural key on its own (query strings vary by
    # referral path for the same posting, and a site could someday
    # regenerate its slug for the same id). Only meaningful alongside a
    # non-null `source`; a plain manual row leaves both null. See the
    # (user_id, source, external_id) partial unique index below and
    # PUT/PATCH/DELETE /applications/by-external-id.
    external_id: Mapped[str | None] = mapped_column(String(255), nullable=True)
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
    salary_currency: Mapped[SalaryCurrency] = mapped_column(
        Enum(
            SalaryCurrency,
            name="salary_currency",
            values_callable=lambda enum_cls: [e.value for e in enum_cls],
        ),
        default=SalaryCurrency.USD,
        server_default=SalaryCurrency.USD.value,
        nullable=False,
    )
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
    # Deleting an application detaches its contacts (drops the join
    # rows) - it never deletes the contacts themselves. Contacts are
    # user-owned resources in their own right (see app/models/contact.py)
    # and live on in the user's contact directory regardless of what
    # happens to any application they were ever attached to.
    application_contacts: Mapped[list["ApplicationContact"]] = relationship(
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
