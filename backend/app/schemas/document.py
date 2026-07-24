import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

from app.models.application import ApplicationStatus
from app.models.document import DocumentType


class DocumentUpdate(BaseModel):
    """
    Only file_type is user-editable after upload (e.g. reclassifying a
    misfiled "other" document as "resume"). file_name/file_url are set
    once at upload time from the actual uploaded file and S3 key -
    letting a client rewrite them would let it point file_url at an
    arbitrary S3 object it doesn't own.
    """

    file_type: DocumentType | None = None


class DocumentRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    application_id: uuid.UUID
    file_name: str = Field(max_length=500)
    file_type: DocumentType
    created_at: datetime
    updated_at: datetime
    # Deliberately excludes the raw file_url (permanent S3 key). Clients
    # get a short-lived presigned download URL from GET .../download instead.


class DocumentListResponse(BaseModel):
    items: list[DocumentRead]
    total: int
    page: int
    page_size: int


class DocumentDownloadResponse(BaseModel):
    download_url: str
    expires_in_seconds: int


# --- Cross-application document directory ----------------------------------
# Everything below supports GET /documents
# (app/api/v1/endpoints/documents.py :: directory_router), the flat "all my
# documents" listing, mirroring ContactWithApplicationRead/
# InterviewWithApplicationRead in contact.py/interview.py. Duplicated here
# rather than shared, matching those files' own precedent - each directory
# response is a different join with its own row shape.


class ApplicationSummary(BaseModel):
    """Minimal parent-application context for a document in the directory view."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    company: str
    position: str
    status: ApplicationStatus


class DocumentWithApplicationRead(DocumentRead):
    application: ApplicationSummary


class DocumentWithApplicationListResponse(BaseModel):
    items: list[DocumentWithApplicationRead]
    total: int
    page: int
    page_size: int
