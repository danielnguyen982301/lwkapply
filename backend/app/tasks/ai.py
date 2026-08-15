"""
Celery tasks for the AI features (Resume Parser + ATS Score - TODO.md
"AI Features"). First per-request-dispatched Celery tasks in this
codebase - app/tasks/reminders.py's send_due_reminders is beat-scheduled,
not triggered by an API call (see app/api/v1/endpoints/ai.py, which
calls .delay() on both tasks below right after creating a pending row).

Same shape as app/tasks/reminders.py: opens/closes its own
SessionLocal() (runs outside a request, can't use the get_db FastAPI
dependency), and commits at each status transition rather than once at
the end - one bad run shouldn't leave a row stuck on `processing`
forever without at least a `failed` stamp attempt.
"""

import logging
import uuid

from app.core.celery_app import celery_app
from app.db.session import SessionLocal
from app.models.application import Application
from app.models.ats_score import AtsScore
from app.models.document import Document
from app.models.resume_analysis import AIJobStatus, ResumeAnalysis
from app.services.ai.ats_scorer import score_resume_against_job
from app.services.ai.job_description_fetcher import fetch_job_description
from app.services.ai.resume_parser import (
    UnsupportedResumeFormatError,
    extract_text,
    parse_resume,
)
from app.services.r2 import download_document

logger = logging.getLogger(__name__)


class JobDescriptionUnavailableError(Exception):
    """Raised when job_description wasn't pasted and job_url is blank or
    couldn't be fetched/extracted - caught below and turned into a
    status=failed row whose error_message tells the caller to resubmit
    with job_description pasted directly. Reuses the existing
    failed/error_message convention rather than a new API shape for this
    fallback signal."""


@celery_app.task(name="app.tasks.ai.parse_resume_task")
def parse_resume_task(resume_analysis_id: str) -> None:
    db = SessionLocal()
    try:
        analysis = db.get(ResumeAnalysis, uuid.UUID(resume_analysis_id))
        if analysis is None:
            return

        analysis.status = AIJobStatus.PROCESSING
        db.commit()

        try:
            document = db.get(Document, analysis.document_id)
            if document is None:
                # Shouldn't happen - document_id is a NOT NULL FK with
                # ondelete="CASCADE", so a deleted Document would have
                # cascade-deleted this ResumeAnalysis row too. Guarded
                # explicitly anyway (satisfies the type checker on
                # Session.get()'s Optional return, and fails clearly
                # rather than crashing with a confusing AttributeError
                # if this invariant is ever violated some other way).
                raise RuntimeError(
                    f"Document {analysis.document_id} not found for "
                    f"ResumeAnalysis {analysis.id}"
                )
            file_bytes = download_document(document.file_url)
            text = extract_text(file_bytes, document.file_name)
            parsed = parse_resume(text)

            analysis.raw_text = text
            analysis.parsed_data = parsed.model_dump()
            analysis.status = AIJobStatus.COMPLETED
        except UnsupportedResumeFormatError as exc:
            analysis.status = AIJobStatus.FAILED
            analysis.error_message = str(exc)
        except Exception:
            logger.exception(
                "Resume parsing failed for resume_analysis_id=%s",
                resume_analysis_id,
            )
            analysis.status = AIJobStatus.FAILED
            analysis.error_message = "Resume parsing failed. Please try again."

        db.commit()
    finally:
        db.close()


@celery_app.task(name="app.tasks.ai.score_ats_task")
def score_ats_task(ats_score_id: str) -> None:
    db = SessionLocal()
    try:
        ats_score = db.get(AtsScore, uuid.UUID(ats_score_id))
        if ats_score is None:
            return

        ats_score.status = AIJobStatus.PROCESSING
        db.commit()

        try:
            job_description = ats_score.job_description
            if job_description is None:
                # Not pasted at creation time - resolve from the linked
                # application's job_url (validated to exist by the
                # endpoint at creation time, but re-checked here since
                # the application/job_url could theoretically have
                # changed between request and task run).
                application = (
                    db.get(Application, ats_score.application_id)
                    if ats_score.application_id
                    else None
                )
                fetched = (
                    fetch_job_description(application.job_url)
                    if application and application.job_url
                    else None
                )
                if not fetched:
                    raise JobDescriptionUnavailableError(
                        "Couldn't extract a job description from the saved "
                        "job URL. Resubmit this request with "
                        "job_description set to paste it manually."
                    )
                job_description = fetched
                ats_score.job_description = fetched
                ats_score.job_description_source = "url"

            resume_analysis = db.get(ResumeAnalysis, ats_score.resume_analysis_id)
            if resume_analysis is None:
                # Shouldn't happen - same FK/cascade-delete reasoning as
                # parse_resume_task's Document check above.
                raise RuntimeError(
                    f"ResumeAnalysis {ats_score.resume_analysis_id} not "
                    f"found for AtsScore {ats_score.id}"
                )
            result = score_resume_against_job(
                resume_analysis.raw_text or "", job_description
            )

            ats_score.score = result.score
            ats_score.feedback = result.model_dump()
            ats_score.status = AIJobStatus.COMPLETED
        except JobDescriptionUnavailableError as exc:
            ats_score.status = AIJobStatus.FAILED
            ats_score.error_message = str(exc)
        except Exception:
            logger.exception("ATS scoring failed for ats_score_id=%s", ats_score_id)
            ats_score.status = AIJobStatus.FAILED
            ats_score.error_message = "ATS scoring failed. Please try again."

        db.commit()
    finally:
        db.close()
