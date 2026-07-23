"""
Cloudflare R2 storage service for application documents (resumes, cover
letters).

R2 implements the S3 API, so this uses boto3's "s3" client pointed at
R2's S3-compatible endpoint (https://<account_id>.r2.cloudflarestorage.com)
rather than a Cloudflare-specific SDK. Confirmed against Cloudflare's
current docs: put_object, delete_object, and generate_presigned_url are
all supported S3-API operations on R2, so this is a client-construction
change only - upload_document/delete_document/generate_download_url's
logic is unchanged from the prior S3-backed version.

Design notes (unchanged from the S3 version):
- Upload flow is server-proxied (client -> our API -> R2), not a presigned
  direct upload. This lets us validate file size/type before anything
  touches R2, at the cost of streaming bytes through the API process.
  Fine for resume/cover-letter-sized files (low MB range); if upload
  volume or file sizes grow significantly, switch to presigned PUT URLs
  issued by a new `POST /documents/upload-url` endpoint.
- Downloads are always presigned, time-limited URLs - we never return a
  permanent public R2 URL to the client, and the bucket itself should be
  private (no public-access custom domain configured for it).
- Object keys are namespaced by user_id/application_id so a bucket listing
  (if ever misconfigured) doesn't trivially expose one user's files next
  to another's, and so we can reason about/clean up a user's files by
  prefix if they delete their account.

R2-specific notes:
- `region_name` must be the literal string "auto" - R2 doesn't have AWS
  regions, this value is required by boto3's client constructor but
  otherwise ignored by R2.
- The endpoint is fully derived from R2_ACCOUNT_ID (see _r2_client below).
  If R2's jurisdiction-specific endpoints (EU/FedRAMP data residency) are
  ever needed, that's the one place to add it - not modeled today since
  nothing currently calls for it.
- Presigned URL expiry (5 min, same as before) and the chunked
  MAX_UPLOAD_SIZE_MB check are unchanged; both are plain S3-API behavior
  that R2 implements the same way.
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
# style attack against R2-backed file storage.
ALLOWED_CONTENT_TYPES = {
    "application/pdf",
    "application/msword",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
}

_PRESIGNED_URL_EXPIRY_SECONDS = 300  # 5 minutes


def _r2_client():
    return boto3.client(
        "s3",
        endpoint_url=f"https://{settings.R2_ACCOUNT_ID}.r2.cloudflarestorage.com",
        aws_access_key_id=settings.R2_ACCESS_KEY_ID or None,
        aws_secret_access_key=settings.R2_SECRET_ACCESS_KEY or None,
        region_name="auto",
    )


def _build_object_key(
    user_id: uuid.UUID, application_id: uuid.UUID, filename: str
) -> str:
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
    Streams `file` to R2, enforcing MAX_UPLOAD_SIZE_MB without loading
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
        _r2_client().put_object(
            Bucket=settings.R2_BUCKET,
            Key=object_key,
            Body=bytes(buffer),
            ContentType=file.content_type,
        )
    except (BotoCoreError, ClientError):
        logger.exception("R2 upload failed for key=%s", object_key)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Failed to store document. Please try again.",
        )

    return object_key, file.filename or "upload"


def delete_document(object_key: str) -> None:
    try:
        _r2_client().delete_object(Bucket=settings.R2_BUCKET, Key=object_key)
    except (BotoCoreError, ClientError):
        # Don't fail the request if R2 cleanup fails - the DB row is the
        # source of truth for "does this document exist" from the user's
        # perspective. Log loudly so orphaned objects can be swept later.
        logger.exception("Failed to delete R2 object key=%s (orphaned)", object_key)


def generate_download_url(object_key: str) -> str:
    try:
        return _r2_client().generate_presigned_url(
            "get_object",
            Params={"Bucket": settings.R2_BUCKET, "Key": object_key},
            ExpiresIn=_PRESIGNED_URL_EXPIRY_SECONDS,
        )
    except (BotoCoreError, ClientError):
        logger.exception("Failed to presign download URL for key=%s", object_key)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Failed to generate download link. Please try again.",
        )


PRESIGNED_URL_EXPIRY_SECONDS = _PRESIGNED_URL_EXPIRY_SECONDS
