import logging
from datetime import datetime, timezone as dt_timezone

from fastapi import (
    APIRouter,
    Depends,
    File,
    HTTPException,
    Response,
    UploadFile,
    status,
)
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from app.api.deps import get_current_user, get_db
from app.core.cookies import clear_auth_cookies
from app.core.security import hash_password, verify_password
from app.models.device_token import DeviceToken, DevicePlatform
from app.models.user import User
from app.models.user_settings import UserSettings
from app.schemas.device_token import DeviceTokenRegister
from app.schemas.user import (
    AccountDeleteRequest,
    PasswordChangeRequest,
    UserProfileUpdate,
    UserRead,
)
from app.schemas.user_settings import UserSettingsRead, UserSettingsUpdate
from app.services import r2
from app.utils.timezone import is_valid_timezone

logger = logging.getLogger(__name__)
router = APIRouter()


def _serialize_user(user: User) -> UserRead:
    """User.avatar_url stores the R2 object key, not a public URL (same
    private-bucket convention as Document.file_url) - swap it for a
    presigned GET URL before handing the response back to a client.
    Longer-lived than a document download link (AVATAR_URL_EXPIRY_SECONDS
    vs PRESIGNED_URL_EXPIRY_SECONDS) since this backs a persistent <img>
    tag, not a one-shot download."""
    data = UserRead.model_validate(user)
    if user.avatar_url:
        data.avatar_url = r2.generate_download_url(
            user.avatar_url, expires_in=r2.AVATAR_URL_EXPIRY_SECONDS
        )
    return data


@router.get("/me", response_model=UserRead)
def read_current_user(current_user: User = Depends(get_current_user)):
    return _serialize_user(current_user)


@router.patch("/me", response_model=UserRead)
def update_profile(
    payload: UserProfileUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    updates = payload.model_dump(exclude_unset=True, exclude={"timezone"})
    for field, value in updates.items():
        setattr(current_user, field, value)

    if "timezone" in payload.model_fields_set:
        if payload.timezone is None:
            # Explicit null = "go back to auto-detect", same
            # explicit-reset convention as UserSettingsUpdate.reminder_lead_hours.
            # Releases the manual lock without touching the stored value -
            # the next login/refresh's auto-detect resumes writing it.
            current_user.timezone_is_manual = False
        elif is_valid_timezone(payload.timezone):
            current_user.timezone = payload.timezone
            # Marks this as an explicit user choice so
            # _maybe_update_timezone (app/api/v1/endpoints/auth.py) stops
            # silently overwriting it with the browser's auto-detected
            # value on the next login/refresh.
            current_user.timezone_is_manual = True
        else:
            logger.warning(
                "Ignoring invalid client-supplied timezone for user_id=%s: %r",
                current_user.id,
                payload.timezone,
            )

    db.add(current_user)
    db.commit()
    db.refresh(current_user)
    return _serialize_user(current_user)


@router.post("/me/password", status_code=status.HTTP_204_NO_CONTENT)
def change_password(
    payload: PasswordChangeRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if not verify_password(payload.current_password, current_user.password_hash):
        raise HTTPException(status_code=400, detail="Incorrect password")

    current_user.password_hash = hash_password(payload.new_password)
    db.add(current_user)
    db.commit()
    return None


@router.post("/me/avatar", response_model=UserRead)
def upload_avatar(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    object_key = r2.upload_avatar(file=file, user_id=current_user.id)
    current_user.avatar_url = object_key
    db.add(current_user)
    db.commit()
    db.refresh(current_user)
    return _serialize_user(current_user)


@router.delete("/me/avatar", response_model=UserRead)
def delete_avatar(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    r2.delete_avatar(current_user.id)
    current_user.avatar_url = None
    db.add(current_user)
    db.commit()
    db.refresh(current_user)
    return _serialize_user(current_user)


@router.delete("/me", status_code=status.HTTP_204_NO_CONTENT)
def delete_account(
    payload: AccountDeleteRequest,
    response: Response,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if not verify_password(payload.password, current_user.password_hash):
        raise HTTPException(status_code=400, detail="Incorrect password")

    # The DB cascade (User's relationships - applications, device_tokens,
    # settings, notifications) cleans up Postgres rows once the user row
    # itself is deleted below, but does nothing about files actually
    # sitting in R2. Clean those up first - skipping this would
    # permanently orphan every uploaded resume (real PII) in the bucket.
    for document in current_user.documents:
        r2.delete_document(document.file_url)
    if current_user.avatar_url:
        r2.delete_avatar(current_user.id)

    db.delete(current_user)
    db.commit()

    # The refresh-token cookie shouldn't linger client-side pointing at a
    # now-deleted account - same helper POST /auth/logout uses.
    clear_auth_cookies(response)
    return None


@router.get("/me/settings", response_model=UserSettingsRead)
def read_settings(current_user: User = Depends(get_current_user)):
    return current_user.settings


@router.patch("/me/settings", response_model=UserSettingsRead)
def update_settings(
    payload: UserSettingsUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    settings_row = current_user.settings
    if settings_row is None:
        # Defensive fallback only - every user should already have one
        # (created at registration, backfilled by the migration that
        # introduced this table). Cheap insurance against a genuinely
        # missing row rather than surprising the client with a 500.
        settings_row = UserSettings(user_id=current_user.id)
        db.add(settings_row)

    updates = payload.model_dump(exclude_unset=True)
    for field, value in updates.items():
        setattr(settings_row, field, value)

    db.add(settings_row)
    db.commit()
    db.refresh(settings_row)
    return settings_row


@router.post(
    "/me/device-tokens",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Register (or re-confirm) this device's FCM token for push reminders",
)
def register_device_token(
    payload: DeviceTokenRegister,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Upserts by `token`, not by (user_id, token) - a token is globally
    unique per app install (FCM's own contract), so if this exact token
    already exists under a *different* user (e.g. someone logged out and
    a different person logged into the same physical device), it gets
    reassigned here rather than left orphaned under the old owner. Called
    on every login/register/silent-refresh from the mobile client (see
    MOBILE_SUMMARY.md's push-notification section), which is also why
    this only ever updates `last_seen_at` rather than erroring on a
    duplicate register of the same token by the same user.
    """
    existing = (
        db.execute(select(DeviceToken).where(DeviceToken.token == payload.token))
        .scalars()
        .first()
    )
    now = datetime.now(dt_timezone.utc)
    platform = DevicePlatform(payload.platform)

    if existing:
        existing.user_id = current_user.id
        existing.platform = platform
        existing.last_seen_at = now
        db.add(existing)
    else:
        db.add(
            DeviceToken(
                user_id=current_user.id,
                token=payload.token,
                platform=platform,
                last_seen_at=now,
            )
        )
    db.commit()


@router.delete(
    "/me/device-tokens/{token}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Deregister this device's FCM token (called on logout)",
)
def delete_device_token(
    token: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    # Scoped to the current user, same ownership shape as everything else
    # in this API - a signed-out device stops receiving pushes, but only
    # for the user actually making this call. Deliberately a no-op
    # (still 204) rather than a 404 if the token is already gone/was
    # never registered/belongs to someone else - logout shouldn't be able
    # to fail visibly over this.
    #
    # A bulk delete() construct, not Session.delete(instance) - there's no
    # loaded instance to hand it (and no need to load one just to delete
    # it). synchronize_session defaults to "auto" here, which is fine:
    # nothing else in this request loads or holds a DeviceToken afterward
    # that would need its in-memory state kept in sync with the DELETE.
    db.execute(
        delete(DeviceToken).where(
            DeviceToken.token == token, DeviceToken.user_id == current_user.id
        )
    )
    db.commit()
