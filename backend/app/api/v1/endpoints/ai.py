"""
AI feature endpoints: Resume Parser (POST/GET /ai/resume-analyses) and
ATS Score (POST/GET /ai/ats-scores) - TODO.md "AI Features".

Both resources are async: a POST creates a `pending` row and dispatches a
Celery task (app/tasks/ai.py), returning 202 immediately; the client
polls GET .../{id} for status to become completed/failed. First
per-request-dispatched Celery tasks in this codebase - see that file's
own docstring.

Both are top-level, user-owned resources (like Application), not nested
under /applications/{id}/ the way Interview/Contact/Document are - see
app/models/resume_analysis.py's module docstring for why ownership here
is a direct user_id equality check rather than a join through
Document/Application.
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.application import Application
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
)
from app.services.ai.client import is_ai_configured
from app.tasks.ai import parse_resume_task, score_ats_task

router = APIRouter()


def _require_ai_configured() -> None:
    if not is_ai_configured():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="AI features are not configured.",
        )


def _get_owned_document(db: Session, document_id: uuid.UUID, user: User) -> Document:
    document = (
        db.execute(
            select(Document)
            .join(Application, Document.application_id == Application.id)
            .where(Document.id == document_id, Application.user_id == user.id)
        )
        .scalars()
        .first()
    )
    if not document:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Document not found"
        )
    return document


def _get_owned_application(
    db: Session, application_id: uuid.UUID, user: User
) -> Application:
    application = (
        db.execute(
            select(Application).where(
                Application.id == application_id, Application.user_id == user.id
            )
        )
        .scalars()
        .first()
    )
    if not application:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Application not found"
        )
    return application


def _get_owned_resume_analysis(
    db: Session, resume_analysis_id: uuid.UUID, user: User
) -> ResumeAnalysis:
    analysis = (
        db.execute(
            select(ResumeAnalysis).where(
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
            select(AtsScore).where(
                AtsScore.id == ats_score_id, AtsScore.user_id == user.id
            )
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
            select(ResumeAnalysis).where(
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

    analysis = ResumeAnalysis(user_id=current_user.id, document_id=document.id)
    db.add(analysis)
    db.commit()
    db.refresh(analysis)

    parse_resume_task.delay(str(analysis.id))
    return analysis


@router.get("/resume-analyses/{resume_analysis_id}", response_model=ResumeAnalysisRead)
def get_resume_analysis(
    resume_analysis_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return _get_owned_resume_analysis(db, resume_analysis_id, current_user)


@router.get("/resume-analyses", response_model=ResumeAnalysisListResponse)
def list_resume_analyses(
    document_id: uuid.UUID | None = None,
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    stmt = select(ResumeAnalysis).where(ResumeAnalysis.user_id == current_user.id)
    if document_id:
        stmt = stmt.where(ResumeAnalysis.document_id == document_id)

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

    application = None
    if payload.application_id:
        application = _get_owned_application(db, payload.application_id, current_user)

    has_job_url = bool(application and application.job_url)
    if not payload.job_description and not has_job_url:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Provide job_description, or an application_id whose "
            "job_url is set.",
        )

    ats_score = AtsScore(
        user_id=current_user.id,
        resume_analysis_id=resume_analysis.id,
        application_id=application.id if application else None,
        job_description=payload.job_description,
        job_description_source="pasted" if payload.job_description else None,
    )
    db.add(ats_score)
    db.commit()
    db.refresh(ats_score)

    score_ats_task.delay(str(ats_score.id))
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
    application_id: uuid.UUID | None = None,
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    stmt = select(AtsScore).where(AtsScore.user_id == current_user.id)
    if application_id:
        stmt = stmt.where(AtsScore.application_id == application_id)

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
