import enum
import uuid
from datetime import datetime

from sqlalchemy import DateTime, Enum, ForeignKey, Integer, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base_class import Base, TimestampMixin, UUIDMixin


class InterviewType(str, enum.Enum):
    PHONE_SCREEN = "phone_screen"
    TECHNICAL = "technical"
    BEHAVIORAL = "behavioral"
    ONSITE = "onsite"
    FINAL = "final"
    OTHER = "other"


class InterviewResult(str, enum.Enum):
    PENDING = "pending"
    PASSED = "passed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class Interview(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "interviews"

    application_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("applications.id", ondelete="CASCADE"),
        nullable=False, index=True,
    )
    type: Mapped[InterviewType] = mapped_column(
        Enum(InterviewType, name="interview_type"), nullable=False
    )
    scheduled_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    duration_minutes: Mapped[int | None] = mapped_column(Integer, nullable=True)
    feedback: Mapped[str | None] = mapped_column(Text, nullable=True)
    result: Mapped[InterviewResult] = mapped_column(
        Enum(InterviewResult, name="interview_result"), default=InterviewResult.PENDING
    )

    application: Mapped["Application"] = relationship(back_populates="interviews")
