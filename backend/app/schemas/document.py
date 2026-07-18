import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

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
