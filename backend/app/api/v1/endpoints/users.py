import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, status
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from app.api.deps import get_current_user, get_db
from app.models.device_token import DeviceToken, DevicePlatform
from app.models.user import User
from app.schemas.device_token import DeviceTokenRegister
from app.schemas.user import UserRead

logger = logging.getLogger(__name__)
router = APIRouter()


@router.get("/me", response_model=UserRead)
def read_current_user(current_user: User = Depends(get_current_user)):
    return current_user


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
    now = datetime.now(timezone.utc)
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
