"""
FastAPI BackgroundTasks equivalents of app/tasks/ai_celery.py's
parse_resume_task / score_ats_task, for deployments that skip running a
Celery worker (Render has no free tier for an always-on background
worker - see BACKEND_SUMMARY.md's "Background job execution" section).
Dispatched via
BackgroundTasks.add_task() from app/api/v1/endpoints/ai.py instead of
Celery's .delay() - same status-machine, same error handling, just no
broker/worker process in between.

Deliberately a separate, self-contained module rather than a shared
helper the Celery tasks also call: keeps app/tasks/ai_celery.py fully
intact as a standalone reference/study copy (see that file), at the
cost of the two staying in sync by hand if the pipeline itself changes.

Trade-offs vs. the Celery version:
- No retry on crash. A worker restart (e.g. a Render deploy) mid-run
  leaves the row on PROCESSING forever instead of FAILED - the Celery
  version has the same exposure for an actual process kill, but a
  redeploy is a much more routine event here than there.
- Runs in the same process as the web server. Starlette runs a sync
  BackgroundTasks callable in the shared threadpool (not the event
  loop), so it doesn't block other requests outright, but a burst of
  submissions queues up behind that threadpool's size rather than
  scaling out via separate Celery worker concurrency.
"""

import logging
import re
import uuid
from datetime import datetime, timezone
from pathlib import PurePosixPath

from app.db.session import SessionLocal
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
    """See app.tasks.ai_celery's identical class - same fallback signal,
    duplicated rather than imported to keep this module self-contained."""


def _generate_analysis_name(file_name: str, completed_at: datetime) -> str:
    """Same as app.tasks.ai_celery._generate_analysis_name - see there."""
    stem = PurePosixPath(file_name).stem or "resume"
    slug = re.sub(r"[^a-zA-Z0-9]+", "_", stem).strip("_").lower() or "resume"
    return f"{slug}_{completed_at.strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:6]}"


def process_resume_analysis(resume_analysis_id: str) -> None:
    """In-process equivalent of app.tasks.ai_celery.parse_resume_task."""
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
                raise RuntimeError(
                    f"Document {analysis.document_id} not found for "
                    f"ResumeAnalysis {analysis.id}"
                )
            file_bytes = download_document(document.file_url)
            text = extract_text(file_bytes, document.file_name)
            parsed = parse_resume(text)

            completed_at = datetime.now(timezone.utc)
            analysis.raw_text = text
            analysis.parsed_data = parsed.model_dump()
            analysis.status = AIJobStatus.COMPLETED
            analysis.completed_at = completed_at
            analysis.analysis_name = _generate_analysis_name(
                document.file_name, completed_at
            )
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


def process_ats_score(ats_score_id: str) -> None:
    """In-process equivalent of app.tasks.ai_celery.score_ats_task."""
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
                fetched = (
                    fetch_job_description(ats_score.job_url)
                    if ats_score.job_url
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
            ats_score.scored_at = datetime.now(timezone.utc)
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
