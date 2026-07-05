"""
S3 storage service for application documents (resumes, cover letters).

Design notes:
- Upload flow is server-proxied (client -> our API -> S3), not a presigned
  direct upload. This lets us validate file size/type before anything
  touches S3, at the cost of streaming bytes through the API process.
  Fine for resume/cover-letter-sized files (low MB range); if upload
  volume or file sizes grow significantly, switch to presigned PUT URLs
  issued by a new `POST /documents/upload-url` endpoint.
- Downloads are always presigned, time-limited URLs - we never return a
  permanent public S3 URL to the client, and the bucket itself should be
  private (no public-read ACLs, no bucket policy allowing anonymous GET).
- Object keys are namespaced by user_id/application_id so a bucket listing
  (if ever misconfigured) doesn't trivially expose one user's files next
  to another's, and so we can reason about/clean up a user's files by
  prefix if they delete their account.
"""

import logging
import uuid

import boto3
from botocore.exceptions import BotoCoreError, ClientError
from fastapi import HTTPException, UploadFile, status

from app.core.config import settings

logger = logging.getLogger(__name__)

# Only these are accepted for resume/cover-letter uploads. Rejecting by
# content-type at the API layer (rather than trusting the file extension
# alone) closes off the most common "upload a .php disguised as a .pdf"
# style attack against S3-backed file storage.
ALLOWED_CONTENT_TYPES = {
    "application/pdf",
    "application/msword",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
}

_PRESIGNED_URL_EXPIRY_SECONDS = 300  # 5 minutes


def _s3_client():
    return boto3.client(
        "s3",
        aws_access_key_id=settings.AWS_ACCESS_KEY_ID or None,
        aws_secret_access_key=settings.AWS_SECRET_ACCESS_KEY or None,
        region_name=settings.AWS_REGION,
    )


def _build_object_key(user_id: uuid.UUID, application_id: uuid.UUID, filename: str) -> str:
    # A random suffix (not just the original filename) prevents key
    # collisions when a user uploads two files with the same name, and
    # avoids leaking any meaning from the filename itself into the key.
    safe_suffix = uuid.uuid4().hex[:12]
    return f"users/{user_id}/applications/{application_id}/{safe_suffix}-{filename}"


def validate_upload(file: UploadFile) -> None:
    if file.content_type not in ALLOWED_CONTENT_TYPES:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Only PDF and Word documents are supported",
        )


def upload_document(
    file: UploadFile,
    user_id: uuid.UUID,
    application_id: uuid.UUID,
) -> tuple[str, str]:
    """
    Streams `file` to S3, enforcing MAX_UPLOAD_SIZE_MB without loading
    the whole file into memory at once. Returns (object_key, file_name).
    """
    validate_upload(file)

    max_bytes = settings.MAX_UPLOAD_SIZE_MB * 1024 * 1024
    object_key = _build_object_key(user_id, application_id, file.filename or "upload")

    # Read in chunks to enforce the size limit without trusting a
    # client-supplied Content-Length header, which can be forged.
    chunk_size = 1024 * 1024
    total_bytes = 0
    buffer = bytearray()
    while True:
        chunk = file.file.read(chunk_size)
        if not chunk:
            break
        total_bytes += len(chunk)
        if total_bytes > max_bytes:
            raise HTTPException(
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                detail=f"File exceeds the {settings.MAX_UPLOAD_SIZE_MB}MB limit",
            )
        buffer.extend(chunk)

    try:
        _s3_client().put_object(
            Bucket=settings.AWS_S3_BUCKET,
            Key=object_key,
            Body=bytes(buffer),
            ContentType=file.content_type,
        )
    except (BotoCoreError, ClientError):
        logger.exception("S3 upload failed for key=%s", object_key)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Failed to store document. Please try again.",
        )

    return object_key, file.filename or "upload"


def delete_document(object_key: str) -> None:
    try:
        _s3_client().delete_object(Bucket=settings.AWS_S3_BUCKET, Key=object_key)
    except (BotoCoreError, ClientError):
        # Don't fail the request if S3 cleanup fails - the DB row is the
        # source of truth for "does this document exist" from the user's
        # perspective. Log loudly so orphaned objects can be swept later.
        logger.exception("Failed to delete S3 object key=%s (orphaned)", object_key)


def generate_download_url(object_key: str) -> str:
    try:
        return _s3_client().generate_presigned_url(
            "get_object",
            Params={"Bucket": settings.AWS_S3_BUCKET, "Key": object_key},
            ExpiresIn=_PRESIGNED_URL_EXPIRY_SECONDS,
        )
    except (BotoCoreError, ClientError):
        logger.exception("Failed to presign download URL for key=%s", object_key)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Failed to generate download link. Please try again.",
        )


PRESIGNED_URL_EXPIRY_SECONDS = _PRESIGNED_URL_EXPIRY_SECONDS