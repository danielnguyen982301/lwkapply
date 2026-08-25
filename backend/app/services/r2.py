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
- Object keys are namespaced by user_id so a bucket listing (if ever
  misconfigured) doesn't trivially expose one user's files next to
  another's, and so we can reason about/clean up a user's files by prefix
  if they delete their account. No application_id in the key - a
  document is no longer created in the context of one application (it
  can be attached to several, or none - see app/models/document.py).

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

# Separate allow-list for avatar uploads (app/api/v1/endpoints/users.py) -
# images, not resume/cover-letter documents.
AVATAR_ALLOWED_CONTENT_TYPES = {
    "image/jpeg",
    "image/png",
    "image/webp",
}

_PRESIGNED_URL_EXPIRY_SECONDS = 300  # 5 minutes
# An avatar backs a persistent <img> tag, not a one-shot download link, so
# it needs to stay valid meaningfully longer than a document download URL.
# An avatar is also much lower-sensitivity than a resume, so the longer
# life is an acceptable trade - see BACKEND_SUMMARY.md/plan notes.
_AVATAR_URL_EXPIRY_SECONDS = 3600  # 1 hour


def _r2_client():
    return boto3.client(
        "s3",
        endpoint_url=f"https://{settings.R2_ACCOUNT_ID}.r2.cloudflarestorage.com",
        aws_access_key_id=settings.R2_ACCESS_KEY_ID or None,
        aws_secret_access_key=settings.R2_SECRET_ACCESS_KEY or None,
        region_name="auto",
    )


def _build_object_key(user_id: uuid.UUID, filename: str) -> str:
    # A random suffix (not just the original filename) prevents key
    # collisions when a user uploads two files with the same name, and
    # avoids leaking any meaning from the filename itself into the key.
    safe_suffix = uuid.uuid4().hex[:12]
    return f"users/{user_id}/documents/{safe_suffix}-{filename}"


def _build_avatar_object_key(user_id: uuid.UUID) -> str:
    # Fixed per user (no random suffix, unlike documents) - an avatar is
    # 1:1 with a user, so a re-upload should just overwrite the same
    # object rather than leaving the previous one to separately clean up.
    return f"users/{user_id}/avatar"


def validate_upload(file: UploadFile) -> None:
    if file.content_type not in ALLOWED_CONTENT_TYPES:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Only PDF and Word documents are supported",
        )


def validate_avatar_upload(file: UploadFile) -> None:
    if file.content_type not in AVATAR_ALLOWED_CONTENT_TYPES:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Only JPEG, PNG, and WebP images are supported",
        )


def upload_document(
    file: UploadFile,
    user_id: uuid.UUID,
) -> tuple[str, str]:
    """
    Streams `file` to R2, enforcing MAX_UPLOAD_SIZE_MB without loading
    the whole file into memory at once. Returns (object_key, file_name).
    """
    validate_upload(file)

    max_bytes = settings.MAX_UPLOAD_SIZE_MB * 1024 * 1024
    object_key = _build_object_key(user_id, file.filename or "upload")

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


def upload_avatar(file: UploadFile, user_id: uuid.UUID) -> str:
    """
    Streams `file` to R2 under a fixed per-user key, enforcing
    MAX_AVATAR_SIZE_MB. Returns the object_key. A re-upload silently
    overwrites the previous avatar (same key every time - see
    _build_avatar_object_key) rather than needing a separate
    delete-the-old-one step.
    """
    validate_avatar_upload(file)

    max_bytes = settings.MAX_AVATAR_SIZE_MB * 1024 * 1024
    object_key = _build_avatar_object_key(user_id)

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
                detail=f"Image exceeds the {settings.MAX_AVATAR_SIZE_MB}MB limit",
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
        logger.exception("R2 avatar upload failed for key=%s", object_key)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Failed to store image. Please try again.",
        )

    return object_key


def delete_avatar(user_id: uuid.UUID) -> None:
    try:
        _r2_client().delete_object(
            Bucket=settings.R2_BUCKET, Key=_build_avatar_object_key(user_id)
        )
    except (BotoCoreError, ClientError):
        # Same fire-and-log-don't-fail pattern as delete_document - the
        # DB's User.avatar_url is the source of truth for "does this user
        # have an avatar" from the client's perspective.
        logger.exception(
            "Failed to delete R2 avatar for user_id=%s (orphaned)", user_id
        )


def delete_document(object_key: str) -> None:
    try:
        _r2_client().delete_object(Bucket=settings.R2_BUCKET, Key=object_key)
    except (BotoCoreError, ClientError):
        # Don't fail the request if R2 cleanup fails - the DB row is the
        # source of truth for "does this document exist" from the user's
        # perspective. Log loudly so orphaned objects can be swept later.
        logger.exception("Failed to delete R2 object key=%s (orphaned)", object_key)


def download_document(object_key: str) -> bytes:
    """Fetches an object's raw bytes for server-side processing (Resume
    Parser - app/tasks/ai_celery.py). Everything else in this module only ever
    hands the client a presigned URL; this is the first caller that needs
    the actual file content in-process."""
    try:
        response = _r2_client().get_object(Bucket=settings.R2_BUCKET, Key=object_key)
        return response["Body"].read()
    except (BotoCoreError, ClientError):
        logger.exception("R2 download failed for key=%s", object_key)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Failed to retrieve document. Please try again.",
        )


def generate_download_url(
    object_key: str, expires_in: int = _PRESIGNED_URL_EXPIRY_SECONDS
) -> str:
    try:
        return _r2_client().generate_presigned_url(
            "get_object",
            Params={"Bucket": settings.R2_BUCKET, "Key": object_key},
            ExpiresIn=expires_in,
        )
    except (BotoCoreError, ClientError):
        logger.exception("Failed to presign download URL for key=%s", object_key)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Failed to generate download link. Please try again.",
        )


PRESIGNED_URL_EXPIRY_SECONDS = _PRESIGNED_URL_EXPIRY_SECONDS
AVATAR_URL_EXPIRY_SECONDS = _AVATAR_URL_EXPIRY_SECONDS
