"""
Resume Parser (TODO.md "AI Features") - structured extraction from an
already-uploaded resume Document, via Gemini (app/services/ai/).

A top-level, user-owned resource - not nested under /applications/{id}/
the way Interview is, so ownership is a direct user_id FK rather than a
join through Application -> User.
Deliberate divergence from the nested-resource convention documented in
BACKEND_SUMMARY.md: this and AtsScore aren't reached via an
application-scoped URL, so anchoring ownership directly to user_id is
actually more consistent with Application's own pattern, not less.

Async by design: created with status=pending, processed by
app/tasks/ai_celery.py::parse_resume_task (Celery), polled via
GET /ai/resume-analyses/{id} until status is completed/failed. See
app/models/ats_score.py, which depends on parsed_data here and reuses
this module's AIJobStatus enum.
"""

import enum
import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, Enum, ForeignKey, String, Text
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
    # summary below so ATS Score (app/tasks/ai_celery.py::score_ats_task) can
    # match against the actual resume content/keywords rather than a
    # paraphrased structured summary that may have dropped nuance
    # ParsedResume's fixed schema doesn't have a slot for.
    raw_text: Mapped[str | None] = mapped_column(Text, nullable=True)
    # {full_name, email, phone, summary, skills[], work_experience[],
    # education[], total_years_experience} - see ParsedResume
    # (app/schemas/ai.py), which both produces and validates this shape.
    parsed_data: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    error_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    # Set only when status transitions to COMPLETED (app/tasks/ai_celery.py::
    # parse_resume_task) - distinct from created_at (when the request was
    # submitted), since parsing is async and the two can be seconds or
    # minutes apart. Stays NULL on a failed run.
    completed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    # Auto-generated from the source document's file name + completion
    # timestamp when status transitions to COMPLETED (app/tasks/ai_celery.py::
    # parse_resume_task::_generate_analysis_name) - stays NULL on a failed
    # run, same as completed_at. User-editable afterwards (PATCH
    # /ai/resume-analyses/{id}), so no DB-level uniqueness is enforced -
    # the generated value is merely unique-by-construction at creation
    # time.
    analysis_name: Mapped[str | None] = mapped_column(String(255), nullable=True)

    user: Mapped["User"] = relationship()
    document: Mapped["Document"] = relationship()

    @property
    def document_file_name(self) -> str:
        """Convenience accessor for ResumeAnalysisRead (app/schemas/ai.py)
        - lets the API hand back the source document's file_name directly
        instead of making the caller separately fetch Document by
        document_id just to build a label. Always resolvable: document_id
        is a NOT NULL FK with ondelete="CASCADE", so `document` can never
        be missing. List endpoints must eager-load `document` (see
        app/api/v1/endpoints/ai.py's joinedload usage) to avoid one
        lazy-load query per row."""
        return self.document.file_name
