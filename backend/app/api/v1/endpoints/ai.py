"""
AI feature endpoints: Resume Parser (POST/GET /ai/resume-analyses) and
ATS Score (POST/GET /ai/ats-scores) - TODO.md "AI Features".

Both resources are async: a POST creates a `pending` row and dispatches a
FastAPI BackgroundTasks job (app/tasks/ai_inline.py), returning 202
immediately; the client polls GET .../{id} for status to become
completed/failed. A Celery-based equivalent (app/tasks/ai_celery.py) also
exists, kept for local dev/study - see BACKEND_SUMMARY.md's "Background
job execution" section for why the default here is BackgroundTasks
instead.

Both are top-level, user-owned resources (like Application), not nested
under /applications/{id}/ the way Interview is - see
app/models/resume_analysis.py's module docstring for why ownership here
is a direct user_id equality check rather than a join through
Application.

Both POST routes are also rate-limited (_enforce_ai_rate_limit, below) -
a shared free-tier daily budget (app/services/rate_limit.py) across both
endpoints, since both trigger real Gemini calls. The check runs before
any row is created for the request, not right before .delay() - so a
rejected request never leaves an orphaned `pending` row behind, and
never fires before validation (owned-resource checks, file_type, etc.)
or the dedup-reuse path, so a request that either fails validation or
just reuses an in-flight analysis never consumes budget either.
"""

import uuid

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session, joinedload

from app.api.deps import get_current_user
from app.core.config import settings
from app.db.session import get_db
from app.models.ats_score import AtsScore
from app.models.document import Document, DocumentType
from app.models.resume_analysis import AIJobStatus, ResumeAnalysis
from app.models.user import User
from app.schemas.ai import (
    AtsScoreCreate,
    AtsScoreListResponse,
    AtsScoreRead,
    ResumeAnalysisCreate,
    ResumeAnalysisListResponse,
    ResumeAnalysisRead,
    ResumeAnalysisUpdate,
)
from app.services.ai.client import is_ai_configured
from app.services.rate_limit import (
    RateLimitExceeded,
    ai_usage_key,
    check_and_increment,
)
from app.tasks.ai_inline import process_ats_score, process_resume_analysis

router = APIRouter()


def _require_ai_configured() -> None:
    if not is_ai_configured():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="AI features are not configured.",
        )


def _enforce_ai_rate_limit(user: User) -> None:
    """Called immediately before dispatching a *new* Gemini-triggering
    Celery task, not as a blanket guard at the top of an endpoint - the
    in-flight dedup-reuse path and requests that fail validation first
    never reach here, so neither consumes budget. Shared across
    resume-analyses and ats-scores (see ai_usage_key's docstring): one
    daily budget per user, not one per endpoint. Free-tier limit for
    every user today - no premium tier exists yet (see
    app/core/config.py's AI_FREE_TIER_DAILY_LIMIT); this is the one
    place a future premium tier would branch on user.role instead of
    always using the free-tier setting.
    """
    try:
        check_and_increment(ai_usage_key(user.id), settings.AI_FREE_TIER_DAILY_LIMIT)
    except RateLimitExceeded as exc:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Daily AI usage limit reached. Try again tomorrow.",
            headers={"Retry-After": str(exc.retry_after_seconds)},
        ) from exc


def _get_owned_document(db: Session, document_id: uuid.UUID, user: User) -> Document:
    document = (
        db.execute(
            select(Document).where(
                Document.id == document_id, Document.user_id == user.id
            )
        )
        .scalars()
        .first()
    )
    if not document:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Document not found"
        )
    return document


def _get_owned_resume_analysis(
    db: Session, resume_analysis_id: uuid.UUID, user: User
) -> ResumeAnalysis:
    analysis = (
        db.execute(
            select(ResumeAnalysis)
            .options(joinedload(ResumeAnalysis.document))
            .where(
                ResumeAnalysis.id == resume_analysis_id,
                ResumeAnalysis.user_id == user.id,
            )
        )
        .scalars()
        .first()
    )
    if not analysis:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Resume analysis not found"
        )
    return analysis


def _get_owned_ats_score(db: Session, ats_score_id: uuid.UUID, user: User) -> AtsScore:
    ats_score = (
        db.execute(
            select(AtsScore)
            .options(
                joinedload(AtsScore.resume_analysis).joinedload(ResumeAnalysis.document)
            )
            .where(AtsScore.id == ats_score_id, AtsScore.user_id == user.id)
        )
        .scalars()
        .first()
    )
    if not ats_score:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="ATS score not found"
        )
    return ats_score


# --- Resume analyses ---------------------------------------------------------


@router.post(
    "/resume-analyses",
    response_model=ResumeAnalysisRead,
    status_code=status.HTTP_202_ACCEPTED,
)
def create_resume_analysis(
    payload: ResumeAnalysisCreate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _require_ai_configured()
    document = _get_owned_document(db, payload.document_id, current_user)
    if document.file_type != DocumentType.RESUME:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Only a document with file_type=resume can be parsed.",
        )

    # Light dedup/cost guard: reuse an in-flight analysis for the same
    # document rather than dispatching a duplicate Gemini call.
    existing = (
        db.execute(
            select(ResumeAnalysis)
            .options(joinedload(ResumeAnalysis.document))
            .where(
                ResumeAnalysis.document_id == document.id,
                ResumeAnalysis.status.in_(
                    [AIJobStatus.PENDING, AIJobStatus.PROCESSING]
                ),
            )
        )
        .scalars()
        .first()
    )
    if existing:
        return existing

    _enforce_ai_rate_limit(current_user)

    analysis = ResumeAnalysis(user_id=current_user.id, document_id=document.id)
    db.add(analysis)
    db.commit()
    db.refresh(analysis)

    background_tasks.add_task(process_resume_analysis, str(analysis.id))
    return analysis


@router.get("/resume-analyses/{resume_analysis_id}", response_model=ResumeAnalysisRead)
def get_resume_analysis(
    resume_analysis_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return _get_owned_resume_analysis(db, resume_analysis_id, current_user)


@router.patch(
    "/resume-analyses/{resume_analysis_id}", response_model=ResumeAnalysisRead
)
def update_resume_analysis(
    resume_analysis_id: uuid.UUID,
    payload: ResumeAnalysisUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    analysis = _get_owned_resume_analysis(db, resume_analysis_id, current_user)
    updates = payload.model_dump(exclude_unset=True)
    for field, value in updates.items():
        setattr(analysis, field, value)

    db.add(analysis)
    db.commit()
    db.refresh(analysis)
    return analysis


@router.get("/resume-analyses", response_model=ResumeAnalysisListResponse)
def list_resume_analyses(
    document_id: uuid.UUID | None = None,
    # status_filter, not status - `status` would shadow the fastapi.status
    # module imported above (same reasoning as applications.py's
    # list_applications).
    status_filter: AIJobStatus | None = Query(default=None, alias="status"),
    search: str | None = Query(default=None, description="Search analysis_name"),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    stmt = (
        select(ResumeAnalysis)
        .options(joinedload(ResumeAnalysis.document))
        .where(ResumeAnalysis.user_id == current_user.id)
    )
    if document_id:
        stmt = stmt.where(ResumeAnalysis.document_id == document_id)
    if status_filter:
        stmt = stmt.where(ResumeAnalysis.status == status_filter)
    if search:
        stmt = stmt.where(ResumeAnalysis.analysis_name.ilike(f"%{search}%"))

    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    items = (
        db.execute(
            stmt.order_by(ResumeAnalysis.created_at.desc())
            .offset((page - 1) * page_size)
            .limit(page_size)
        )
        .scalars()
        .all()
    )

    return ResumeAnalysisListResponse(
        items=[ResumeAnalysisRead.model_validate(item) for item in items],
        total=total,
        page=page,
        page_size=page_size,
    )


# --- ATS scores ----------------------------------------------------------


@router.post(
    "/ats-scores",
    response_model=AtsScoreRead,
    status_code=status.HTTP_202_ACCEPTED,
)
def create_ats_score(
    payload: AtsScoreCreate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _require_ai_configured()
    resume_analysis = _get_owned_resume_analysis(
        db, payload.resume_analysis_id, current_user
    )
    if resume_analysis.status != AIJobStatus.COMPLETED:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This resume hasn't finished parsing yet (or parsing failed) - "
            "wait for resume_analysis.status to be 'completed' before scoring it.",
        )

    if not payload.job_description and not payload.job_url:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Provide job_description or job_url.",
        )

    _enforce_ai_rate_limit(current_user)

    ats_score = AtsScore(
        user_id=current_user.id,
        resume_analysis_id=resume_analysis.id,
        job_description=payload.job_description,
        job_description_source="pasted" if payload.job_description else "url",
        job_url=payload.job_url if not payload.job_description else None,
    )
    db.add(ats_score)
    db.commit()
    db.refresh(ats_score)

    background_tasks.add_task(process_ats_score, str(ats_score.id))
    return ats_score


@router.get("/ats-scores/{ats_score_id}", response_model=AtsScoreRead)
def get_ats_score(
    ats_score_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return _get_owned_ats_score(db, ats_score_id, current_user)


@router.get("/ats-scores", response_model=AtsScoreListResponse)
def list_ats_scores(
    resume_analysis_id: uuid.UUID | None = None,
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    stmt = (
        select(AtsScore)
        .options(
            joinedload(AtsScore.resume_analysis).joinedload(ResumeAnalysis.document)
        )
        .where(AtsScore.user_id == current_user.id)
    )
    if resume_analysis_id:
        stmt = stmt.where(AtsScore.resume_analysis_id == resume_analysis_id)

    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    items = (
        db.execute(
            stmt.order_by(AtsScore.created_at.desc())
            .offset((page - 1) * page_size)
            .limit(page_size)
        )
        .scalars()
        .all()
    )

    return AtsScoreListResponse(
        items=[AtsScoreRead.model_validate(item) for item in items],
        total=total,
        page=page,
        page_size=page_size,
    )
