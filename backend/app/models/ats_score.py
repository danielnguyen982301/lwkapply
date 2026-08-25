"""
ATS Score (TODO.md "AI Features") - scores an already-parsed resume
(ResumeAnalysis) against a job description, via Gemini
(app/services/ai/).

Same top-level, direct-user_id ownership model as ResumeAnalysis - see
that module's docstring.

No Application link of any kind (deliberately - see Application/Document
being decoupled into a many-to-many via ApplicationDocument): a score is
only ever a resume_analysis scored against a job_description, sourced
either as pasted text (job_description_source="pasted") or a pasted URL
scraped at run time (job_description_source="url", url stored in
job_url). Nothing here is ever cross-checked against any application's
own job_url/company/position - that check would be theater, since the
pasted text/URL is caller-supplied and unverifiable either way; the
caller is responsible for pasting the right thing. job_description
starts NULL when sourced from job_url (that's the one field here that
can't be non-null at creation, unlike every other required column in
this codebase's other models, because its value genuinely isn't known
yet) and is filled in by app/tasks/ai_celery.py::score_ats_task once fetched. A
fetch/extraction failure (dead link, JS-rendered page, blocked scraper -
see app/services/ai/job_description_fetcher.py) marks status=failed with
an error_message asking the caller to resubmit with job_description
pasted directly - reuses the existing failed/error_message convention
rather than inventing a new API shape for that fallback signal.
"""

import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.dialects.postgresql import ENUM, JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base_class import Base, TimestampMixin, UUIDMixin
from app.models.resume_analysis import AIJobStatus

if TYPE_CHECKING:
    from app.models.resume_analysis import ResumeAnalysis
    from app.models.user import User

# Reuses the "ai_job_status" Postgres enum type ResumeAnalysis.status
# already declares - same name, same values_callable, create_type=False
# since the type already exists. Must be postgresql.ENUM here, not the
# generic sqlalchemy.Enum - see ApplicationStatusHistory's identical note
# for why (create_type is only reliably honored on the Postgres-specific
# class).
_ai_job_status_enum = ENUM(
    AIJobStatus,
    name="ai_job_status",
    values_callable=lambda enum_cls: [e.value for e in enum_cls],
    create_type=False,
)


class AtsScore(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "ats_scores"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    resume_analysis_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("resume_analyses.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    job_description: Mapped[str | None] = mapped_column(Text, nullable=True)
    job_description_source: Mapped[str | None] = mapped_column(
        String(16), nullable=True
    )  # "pasted" | "url"
    # The pasted URL when job_description_source="url" - kept around (not
    # just consumed and discarded) so score_ats_task has something to
    # fetch from, and so a failed fetch can be retried/inspected later.
    job_url: Mapped[str | None] = mapped_column(String(1000), nullable=True)
    status: Mapped[AIJobStatus] = mapped_column(
        _ai_job_status_enum,
        server_default=AIJobStatus.PENDING,
        nullable=False,
    )
    score: Mapped[int | None] = mapped_column(Integer, nullable=True)
    # {summary, matched_keywords[], missing_keywords[], suggestions[]} -
    # see AtsScoreResult (app/schemas/ai.py), which both produces and
    # validates this shape.
    feedback: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    error_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    # Set only when status transitions to COMPLETED (app/tasks/ai_celery.py::
    # score_ats_task) - same rationale as ResumeAnalysis.completed_at:
    # distinct from created_at since scoring is async. Stays NULL on a
    # failed run.
    scored_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    user: Mapped["User"] = relationship()
    resume_analysis: Mapped["ResumeAnalysis"] = relationship()

    @property
    def document_file_name(self) -> str:
        """Same rationale as ResumeAnalysis.document_file_name, one hop
        further - via resume_analysis.document. Always resolvable, same
        NOT NULL/CASCADE reasoning. List endpoints must eager-load
        resume_analysis.document (see app/api/v1/endpoints/ai.py's
        joinedload chain) to avoid two lazy-load queries per row."""
        return self.resume_analysis.document.file_name

    @property
    def analysis_name(self) -> str:
        """resume_analysis.analysis_name - always resolvable despite being
        nullable on ResumeAnalysis itself: an AtsScore can only ever be
        created against a resume_analysis whose status is already
        COMPLETED (enforced in create_ats_score), and analysis_name is set
        in the same commit as that COMPLETED transition (app/tasks/ai_celery.py::
        parse_resume_task), so it's never NULL by the time an AtsScore
        exists to reference it. Already covered by the same
        joinedload(AtsScore.resume_analysis) list endpoints use for
        document_file_name - no extra eager-load needed."""
        if self.resume_analysis.analysis_name is None:
            raise RuntimeError(
                f"AtsScore {self.id} references ResumeAnalysis "
                f"{self.resume_analysis_id} with a NULL analysis_name - "
                "should be impossible, since scoring requires status=completed."
            )
        return self.resume_analysis.analysis_name
