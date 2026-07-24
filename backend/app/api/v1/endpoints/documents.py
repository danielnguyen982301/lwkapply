"""
Document endpoints.

`router` holds CRUD, nested under an application. Unlike Interview/Contact,
Document creation isn't a plain JSON POST - it's a multipart file upload
that we stream to Cloudflare R2 (see app/services/r2.py) before writing the
resulting object key to the DB in the same request. Reads never return a
permanent file_url; GET /{document_id}/download mints a short-lived
presigned R2 URL instead, so a leaked API response can't be used to fetch
someone's resume indefinitely.

`directory_router` holds one read-only route: GET /documents, a flat
listing across every application the user owns (mirrors contacts.py's /
interviews.py's directory_router pattern). A document still only ever
exists nested under one application - this doesn't change ownership or
add a new way to create one, it's just a different read path over the
same rows, scoped via the same Application.user_id join the nested routes
already use for ownership checks. Registered in router.py under the
top-level /documents prefix.

Unlike Contacts (search only) or Interviews (result filter only), Document
has both a name-like field (file_name) and an enum field (file_type), so
the directory route supports both: `search` matches file_name or the
parent application's company (same fields Contacts' search matches),
`file_type` filters the exact enum (same shape as Interviews' `result`).
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
from sqlalchemy import or_
from sqlalchemy.orm import Session, contains_eager

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.application import Application
from app.models.document import Document, DocumentType
from app.models.user import User
from app.schemas.document import (
    DocumentDownloadResponse,
    DocumentListResponse,
    DocumentRead,
    DocumentUpdate,
    DocumentWithApplicationListResponse,
    DocumentWithApplicationRead,
)
from app.services.r2 import (
    PRESIGNED_URL_EXPIRY_SECONDS,
    delete_document,
    generate_download_url,
    upload_document,
)

router = APIRouter()
directory_router = APIRouter()


def _get_owned_application(
    db: Session, application_id: uuid.UUID, user: User
) -> Application:
    application = (
        db.query(Application)
        .filter(Application.id == application_id, Application.user_id == user.id)
        .first()
    )
    if not application:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Application not found"
        )
    return application


def _get_owned_document(
    db: Session, application_id: uuid.UUID, document_id: uuid.UUID, user: User
) -> Document:
    document = (
        db.query(Document)
        .join(Application, Document.application_id == Application.id)
        .filter(
            Document.id == document_id,
            Document.application_id == application_id,
            Application.user_id == user.id,
        )
        .first()
    )
    if not document:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Document not found"
        )
    return document


@router.get("", response_model=DocumentListResponse)
def list_documents(
    application_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
):
    _get_owned_application(db, application_id, current_user)
    query = (
        db.query(Document)
        .filter(Document.application_id == application_id)
        .order_by(Document.created_at.desc())
    )
    total = query.count()
    items = query.offset((page - 1) * page_size).limit(page_size).all()

    return DocumentListResponse(
        items=[DocumentRead.model_validate(item) for item in items],
        total=total,
        page=page,
        page_size=page_size,
    )


@router.post("", response_model=DocumentRead, status_code=status.HTTP_201_CREATED)
def upload_document_endpoint(
    application_id: uuid.UUID,
    file: UploadFile = File(...),
    file_type: DocumentType = Form(default=DocumentType.OTHER),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _get_owned_application(db, application_id, current_user)

    object_key, original_filename = upload_document(
        file=file, user_id=current_user.id, application_id=application_id
    )

    document = Document(
        application_id=application_id,
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
    application_id: uuid.UUID,
    document_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return _get_owned_document(db, application_id, document_id, current_user)


@router.get("/{document_id}/download", response_model=DocumentDownloadResponse)
def download_document(
    application_id: uuid.UUID,
    document_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    document = _get_owned_document(db, application_id, document_id, current_user)
    url = generate_download_url(document.file_url)
    return DocumentDownloadResponse(
        download_url=url, expires_in_seconds=PRESIGNED_URL_EXPIRY_SECONDS
    )


@router.patch("/{document_id}", response_model=DocumentRead)
def update_document(
    application_id: uuid.UUID,
    document_id: uuid.UUID,
    payload: DocumentUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    document = _get_owned_document(db, application_id, document_id, current_user)
    updates = payload.model_dump(exclude_unset=True)
    for field, value in updates.items():
        setattr(document, field, value)

    db.add(document)
    db.commit()
    db.refresh(document)
    return document


@router.delete("/{document_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_document_endpoint(
    application_id: uuid.UUID,
    document_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    document = _get_owned_document(db, application_id, document_id, current_user)
    # Best-effort S3 cleanup; the DB row is what actually gates access, so
    # we don't roll back the delete if the S3 side fails (see service docstring).
    delete_document(document.file_url)
    db.delete(document)
    db.commit()
    return None


@directory_router.get("", response_model=DocumentWithApplicationListResponse)
def list_all_documents(
    search: str | None = None,
    file_type: DocumentType | None = None,
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # Same join Application already used for ownership on every nested
    # route above (Document -> Application -> User) - just not scoped down
    # to one application_id here. `contains_eager` reuses this join to
    # populate `Document.application` instead of firing a second query per
    # row; it relies on the join/filter below being the exact source of
    # that relationship's rows, so don't reorder without care.
    query = (
        db.query(Document)
        .join(Application, Document.application_id == Application.id)
        .options(contains_eager(Document.application))
        .filter(Application.user_id == current_user.id)
    )

    if search:
        like = f"%{search}%"
        query = query.filter(
            or_(Document.file_name.ilike(like), Application.company.ilike(like))
        )

    if file_type:
        query = query.filter(Document.file_type == file_type)

    total = query.count()
    items = (
        query.order_by(Document.created_at.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
        .all()
    )
    return DocumentWithApplicationListResponse(
        items=[DocumentWithApplicationRead.model_validate(item) for item in items],
        total=total,
        page=page,
        page_size=page_size,
    )
