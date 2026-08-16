"""
Document endpoints - top-level, user-owned resource (like Application),
mounted at /documents. A document is no longer created in the context of
one application: it's uploaded standalone here, then optionally attached
to any number of applications via
app/api/v1/endpoints/application_documents.py (mounted at
/applications/{application_id}/documents). See app/models/document.py's
module docstring for the ownership rationale.

Unlike Interview/Contact, Document creation isn't a plain JSON POST - it's
a multipart file upload that we stream to Cloudflare R2 (see
app/services/r2.py) before writing the resulting object key to the DB in
the same request. Reads never return a permanent file_url; GET
/{document_id}/download mints a short-lived presigned R2 URL instead, so a
leaked API response can't be used to fetch someone's resume indefinitely.
"""

import uuid

from fastapi import (
    APIRouter,
    Depends,
    File,
    Form,
    HTTPException,
    Query,
    UploadFile,
    status,
)
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.document import Document, DocumentType
from app.models.user import User
from app.schemas.document import (
    DocumentDownloadResponse,
    DocumentListResponse,
    DocumentRead,
    DocumentUpdate,
)
from app.services.r2 import (
    PRESIGNED_URL_EXPIRY_SECONDS,
    delete_document,
    generate_download_url,
    upload_document,
)

router = APIRouter()


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
def list_documents(
    search: str | None = None,
    file_type: DocumentType | None = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
):
    # Built without order_by/offset/limit - reused as-is for the count
    # below (via .subquery()) and extended with those three only for the
    # items fetch.
    stmt = select(Document).where(Document.user_id == current_user.id)

    if search:
        stmt = stmt.where(Document.file_name.ilike(f"%{search}%"))
    if file_type:
        stmt = stmt.where(Document.file_type == file_type)

    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    items = (
        db.execute(
            stmt.order_by(Document.created_at.desc())
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
def upload_document_endpoint(
    file: UploadFile = File(...),
    file_type: DocumentType = Form(default=DocumentType.OTHER),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    object_key, original_filename = upload_document(file=file, user_id=current_user.id)

    document = Document(
        user_id=current_user.id,
        file_name=original_filename,
        file_url=object_key,  # stores the S3 object key, not a public URL
        file_type=file_type,
    )
    db.add(document)
    db.commit()
    db.refresh(document)
    return document


@router.get("/{document_id}", response_model=DocumentRead)
def get_document(
    document_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return _get_owned_document(db, document_id, current_user)


@router.get("/{document_id}/download", response_model=DocumentDownloadResponse)
def download_document(
    document_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    document = _get_owned_document(db, document_id, current_user)
    url = generate_download_url(document.file_url)
    return DocumentDownloadResponse(
        download_url=url, expires_in_seconds=PRESIGNED_URL_EXPIRY_SECONDS
    )


@router.patch("/{document_id}", response_model=DocumentRead)
def update_document(
    document_id: uuid.UUID,
    payload: DocumentUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    document = _get_owned_document(db, document_id, current_user)
    updates = payload.model_dump(exclude_unset=True)
    for field, value in updates.items():
        setattr(document, field, value)

    db.add(document)
    db.commit()
    db.refresh(document)
    return document


@router.delete("/{document_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_document_endpoint(
    document_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    document = _get_owned_document(db, document_id, current_user)
    # Best-effort S3 cleanup; the DB row is what actually gates access, so
    # we don't roll back the delete if the S3 side fails (see service docstring).
    delete_document(document.file_url)
    db.delete(document)
    db.commit()
    return None
