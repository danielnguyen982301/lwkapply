"""
Attach/detach endpoints linking a Document to an Application - mounted at
/applications/{application_id}/documents (app/api/v1/router.py). A
document is created standalone via POST /documents
(app/api/v1/endpoints/documents.py) and attached here afterward; detaching
only removes the link (ApplicationDocument row), it never deletes the
document itself - see app/models/application_document.py.
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.application import Application
from app.models.application_document import ApplicationDocument
from app.models.document import Document
from app.models.user import User
from app.schemas.document import (
    ApplicationDocumentCreate,
    DocumentListResponse,
    DocumentRead,
)

router = APIRouter()


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


@router.get("", response_model=DocumentListResponse)
def list_attached_documents(
    application_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
):
    _get_owned_application(db, application_id, current_user)

    stmt = (
        select(Document)
        .join(ApplicationDocument, ApplicationDocument.document_id == Document.id)
        .where(ApplicationDocument.application_id == application_id)
    )

    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    items = (
        db.execute(
            stmt.order_by(ApplicationDocument.created_at.desc())
            .offset((page - 1) * page_size)
            .limit(page_size)
        )
        .scalars()
        .all()
    )

    return DocumentListResponse(
        items=[DocumentRead.model_validate(item) for item in items],
        total=total,
        page=page,
        page_size=page_size,
    )


@router.post("", response_model=DocumentRead, status_code=status.HTTP_201_CREATED)
def attach_document(
    application_id: uuid.UUID,
    payload: ApplicationDocumentCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    application = _get_owned_application(db, application_id, current_user)
    document = _get_owned_document(db, payload.document_id, current_user)

    existing = (
        db.execute(
            select(ApplicationDocument).where(
                ApplicationDocument.application_id == application.id,
                ApplicationDocument.document_id == document.id,
            )
        )
        .scalars()
        .first()
    )
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This document is already attached to this application.",
        )

    link = ApplicationDocument(application_id=application.id, document_id=document.id)
    db.add(link)
    db.commit()
    db.refresh(document)
    return document


@router.delete("/{document_id}", status_code=status.HTTP_204_NO_CONTENT)
def detach_document(
    application_id: uuid.UUID,
    document_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _get_owned_application(db, application_id, current_user)

    link = (
        db.execute(
            select(ApplicationDocument).where(
                ApplicationDocument.application_id == application_id,
                ApplicationDocument.document_id == document_id,
            )
        )
        .scalars()
        .first()
    )
    if not link:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="This document isn't attached to this application.",
        )

    db.delete(link)
    db.commit()
    return None
