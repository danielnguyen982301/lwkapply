"""
Resume Parser (TODO.md "AI Features") - structured extraction from an
already-uploaded resume Document, via Gemini (app/services/ai/).

A top-level, user-owned resource - not nested under /applications/{id}/
the way Interview/Contact/Document are, so ownership is a direct
user_id FK rather than a join through Document -> Application -> User.
Deliberate divergence from the nested-resource convention documented in
BACKEND_SUMMARY.md: this and AtsScore aren't reached via an
application-scoped URL, so anchoring ownership directly to user_id is
actually more consistent with Application's own pattern, not less.

Async by design: created with status=pending, processed by
app/tasks/ai.py::parse_resume_task (Celery), polled via
GET /ai/resume-analyses/{id} until status is completed/failed. See
app/models/ats_score.py, which depends on parsed_data here and reuses
this module's AIJobStatus enum.
"""

import enum
import uuid
from typing import TYPE_CHECKING

from sqlalchemy import Enum, ForeignKey, Text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base_class import Base, TimestampMixin, UUIDMixin

if TYPE_CHECKING:
    from app.models.document import Document
    from app.models.user import User


class AIJobStatus(str, enum.Enum):
    PENDING = "pending"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"


class ResumeAnalysis(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "resume_analyses"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    document_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("documents.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    status: Mapped[AIJobStatus] = mapped_column(
        Enum(
            AIJobStatus,
            name="ai_job_status",
            values_callable=lambda enum_cls: [e.value for e in enum_cls],
        ),
        server_default=AIJobStatus.PENDING,
        nullable=False,
    )
    # Full text extracted from the resume file (app/services/ai/
    # resume_parser.py::extract_text), stored alongside the structured
    # summary below so ATS Score (app/tasks/ai.py::score_ats_task) can
    # match against the actual resume content/keywords rather than a
    # paraphrased structured summary that may have dropped nuance
    # ParsedResume's fixed schema doesn't have a slot for.
    raw_text: Mapped[str | None] = mapped_column(Text, nullable=True)
    # {full_name, email, phone, summary, skills[], work_experience[],
    # education[], total_years_experience} - see ParsedResume
    # (app/schemas/ai.py), which both produces and validates this shape.
    parsed_data: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    error_message: Mapped[str | None] = mapped_column(Text, nullable=True)

    user: Mapped["User"] = relationship()
    document: Mapped["Document"] = relationship()
