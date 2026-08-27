"""
Authentication endpoints.

Design notes:
- Registration and login return both an access token (short-lived,
  used on every request) and a refresh token (long-lived, used only
  to mint new access tokens). This limits the blast radius if an
  access token leaks.
- Password reset uses a signed, time-limited JWT emailed to the user
  rather than a DB-stored token, so no extra table is needed - see
  app/services/password_reset.py for how the token is built and sent.
  It's also the only way to change a password at all: there's no
  authenticated "change password" endpoint requiring the current
  password, on either client (see PasswordSettingsCard.vue /
  ChangePasswordScreen.dart's "reset password" button) - proof of
  identity here is possession of the inbox, not the old password.
- We never reveal whether an email exists in the system on the
  "forgot password" endpoint, to avoid user enumeration. Rate limited
  by email and IP (app/services/rate_limit.py) for the same reason: an
  attacker who can't tell success from failure could otherwise still
  infer existence by spamming one address until it 429s.
- Confirming a reset bumps User.token_version, which (a) invalidates
  every other access/refresh token already issued to that user - see
  app/api/deps.py::get_current_user and this module's /refresh - and
  (b) makes the reset token itself single-use, since a replayed token
  carries the now-stale version.
"""

import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.cookies import (
    REFRESH_COOKIE_NAME,
    generate_csrf_token,
    set_auth_cookies,
    clear_auth_cookies,
)
from app.api.deps import is_mobile_client, verify_csrf_unless_mobile
from app.core.security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    hash_password,
    verify_password,
)
from app.db.session import get_db
from app.models.user import User
from app.models.user_settings import UserSettings
from app.schemas.auth import (
    LoginRequest,
    PasswordResetConfirm,
    PasswordResetRequest,
    RefreshRequest,
    TokenResponse,
)
from app.schemas.user import UserCreate, UserRead
from app.services.password_reset import send_password_reset_email
from app.services.rate_limit import (
    RateLimitExceeded,
    check_and_increment,
    password_reset_email_key,
    password_reset_ip_key,
)
from app.utils.timezone import is_valid_timezone

logger = logging.getLogger(__name__)
router = APIRouter()


def _issue_tokens(
    user_id,
    token_version: int,
    csrf_token: str,
    refresh_token: Optional[str] = None,
) -> TokenResponse:
    """Builds the JSON response body for /login and /refresh.

    `refresh_token` must only ever be passed by mobile call sites (see
    `is_mobile_client`) - never pass it unconditionally, or web's fetch
    response would carry the refresh token in plaintext JSON, defeating
    the httpOnly-cookie protection entirely. `csrf_token` is the opposite
    - always pass it, both client types - see TokenResponse.csrf_token's
    docstring for why.
    """
    return TokenResponse(
        access_token=create_access_token(str(user_id), token_version=token_version),
        refresh_token=refresh_token,
        csrf_token=csrf_token,
    )


def _maybe_update_timezone(db: Session, user: User, timezone: Optional[str]) -> None:
    """Silently re-report User.timezone on register/login/refresh (see
    TODO.md's reminder-system plan). Deliberately quiet on failure -
    a missing or malformed tz string should never fail the surrounding
    auth request, it just leaves the column as it was. Also skips the
    write entirely when the value hasn't actually changed, since this
    runs on *every* login and refresh - not worth a DB round-trip for a
    no-op UPDATE on every single request.
    """
    if user.timezone_is_manual:
        # User explicitly set this via PATCH /users/me
        # (app/api/v1/endpoints/users.py) - don't let the browser's
        # auto-detected value silently overwrite that choice.
        return
    if not timezone or timezone == user.timezone:
        return
    if not is_valid_timezone(timezone):
        logger.warning(
            "Ignoring invalid client-reported timezone for user_id=%s: %r",
            user.id,
            timezone,
        )
        return
    user.timezone = timezone
    db.add(user)
    db.commit()


@router.post("/register", response_model=UserRead, status_code=status.HTTP_201_CREATED)
def register(payload: UserCreate, db: Session = Depends(get_db)):
    existing = (
        db.execute(select(User).where(User.email == payload.email)).scalars().first()
    )
    if existing:
        # Deliberately vague message: don't confirm which field collided
        raise HTTPException(
            status_code=400, detail="Unable to register with these details"
        )

    timezone = (
        payload.timezone
        if payload.timezone and is_valid_timezone(payload.timezone)
        else None
    )
    if payload.timezone and timezone is None:
        logger.warning(
            "Ignoring invalid client-reported timezone at registration: %r",
            payload.timezone,
        )

    user = User(
        email=payload.email,
        password_hash=hash_password(payload.password),
        first_name=payload.first_name,
        last_name=payload.last_name,
        timezone=timezone,
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    # Every user should always have exactly one settings row (see
    # app/models/user_settings.py's module docstring) - created here at
    # registration; pre-existing accounts got theirs backfilled by the
    # migration that introduced the table.
    db.add(UserSettings(user_id=user.id))
    db.commit()

    return user


@router.post("/login", response_model=TokenResponse)
def login(
    payload: LoginRequest,
    request: Request,
    response: Response,
    db: Session = Depends(get_db),
):
    user = db.execute(select(User).where(User.email == payload.email)).scalars().first()
    if not user or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Incorrect email or password")
    if not user.is_active:
        raise HTTPException(status_code=403, detail="Account is disabled")

    _maybe_update_timezone(db, user, payload.timezone)

    refresh_token = create_refresh_token(str(user.id), token_version=user.token_version)
    csrf_token = generate_csrf_token()

    # Always set the cookie pair, even on a mobile request - mobile just
    # ignores it, and it keeps this one code path identical for both
    # client types. Only the JSON body branches on client type below.
    set_auth_cookies(response, refresh_token, csrf_token)

    return _issue_tokens(
        user.id,
        token_version=user.token_version,
        csrf_token=csrf_token,
        refresh_token=refresh_token if is_mobile_client(request) else None,
    )


@router.post("/refresh", response_model=TokenResponse)
def refresh(
    request: Request,
    response: Response,
    payload: Optional[RefreshRequest] = None,
    db: Session = Depends(get_db),
):
    """Deliberately *not* behind verify_csrf_unless_mobile, unlike /logout.

    This is the call app boot uses to turn a stored refresh-token cookie
    back into a session (see webapp's authStore.bootstrap()) - the whole
    point is that it has to work with zero prior in-memory state, so it
    can never be given a CSRF token sourced from an earlier response the
    way /logout's caller always has one. Dropping the check here is safe
    because a forged cross-site call can't actually gain anything: CORS
    still stops any origin but our own configured frontend from reading
    the response body, so an attacker only ever gets a blind, harmless
    token rotation - never sees the new access/CSRF token themselves,
    and refresh tokens are stateless/unrevoked JWTs, so nothing about the
    legitimate session gets invalidated by an extra rotation happening in
    the background.
    """
    mobile = is_mobile_client(request)

    if mobile:
        # Mobile has no cookie to read from - it sends the refresh token
        # explicitly in the body instead (see mobile/lib/features/auth/
        # data/auth_api.dart::refresh).
        token = payload.refresh_token if payload else None
    else:
        token = request.cookies.get(REFRESH_COOKIE_NAME)

    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing refresh token"
        )

    token_payload = decode_token(token)
    if token_payload is None or token_payload.get("type") != "refresh":
        raise HTTPException(status_code=401, detail="Invalid or expired refresh token")

    user = (
        db.execute(select(User).where(User.id == token_payload["sub"]))
        .scalars()
        .first()
    )
    if not user or not user.is_active:
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    # A stale token_version means this refresh token predates the user's
    # last password reset (see User.token_version's docstring) - without
    # this check, a reset wouldn't actually stop a device that was
    # already logged in from minting fresh access tokens forever.
    if token_payload.get("token_version") != user.token_version:
        raise HTTPException(status_code=401, detail="Invalid or expired refresh token")

    _maybe_update_timezone(db, user, payload.timezone if payload else None)

    # Rotate both the refresh token and the CSRF token on every refresh —
    # if a refresh token is ever replayed after rotation, this makes the
    # replay detectable (the old one no longer validates) rather than
    # silently accepted.
    new_refresh_token = create_refresh_token(
        str(user.id), token_version=user.token_version
    )
    new_csrf_token = generate_csrf_token()

    # Always set the cookie pair, same reasoning as /login - mobile
    # ignores it, one code path for both client types.
    set_auth_cookies(response, new_refresh_token, new_csrf_token)

    return _issue_tokens(
        user.id,
        token_version=user.token_version,
        csrf_token=new_csrf_token,
        refresh_token=new_refresh_token if mobile else None,
    )


@router.post("/password-reset/request", status_code=status.HTTP_202_ACCEPTED)
def request_password_reset(
    payload: PasswordResetRequest, request: Request, db: Session = Depends(get_db)
):
    client_ip = request.client.host if request.client else "unknown"
    try:
        check_and_increment(
            password_reset_ip_key(client_ip), settings.PASSWORD_RESET_DAILY_LIMIT_PER_IP
        )
        check_and_increment(
            password_reset_email_key(payload.email),
            settings.PASSWORD_RESET_DAILY_LIMIT_PER_EMAIL,
        )
    except RateLimitExceeded as exc:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many reset requests. Please try again later.",
            headers={"Retry-After": str(exc.retry_after_seconds)},
        )

    user = db.execute(select(User).where(User.email == payload.email)).scalars().first()
    if user:
        send_password_reset_email(user)
        logger.info("Password reset requested for user_id=%s", user.id)
    # Always return the same response, whether or not the email exists -
    # see this module's docstring on why (also why the rate limit above
    # runs regardless of whether `user` turns out to exist).
    return {"message": "If that email exists, a reset link has been sent."}


@router.post("/password-reset/confirm", status_code=status.HTTP_200_OK)
def confirm_password_reset(
    payload: PasswordResetConfirm, db: Session = Depends(get_db)
):
    token_payload = decode_token(payload.token)
    if token_payload is None or token_payload.get("type") != "password_reset":
        raise HTTPException(status_code=400, detail="Invalid or expired reset token")

    user = (
        db.execute(select(User).where(User.id == token_payload["sub"]))
        .scalars()
        .first()
    )
    if not user or token_payload.get("token_version") != user.token_version:
        # The token_version mismatch branch covers two cases: a reset
        # already happened since this token was issued (bumped by the
        # line below, last time), or this exact token was already used
        # once - either way it's stale, not just "wrong user".
        raise HTTPException(status_code=400, detail="Invalid or expired reset token")

    user.password_hash = hash_password(payload.new_password)
    user.token_version += 1
    db.add(user)
    db.commit()
    return {"message": "Password has been reset successfully."}


@router.post(
    "/logout",
    status_code=status.HTTP_204_NO_CONTENT,
    dependencies=[Depends(verify_csrf_unless_mobile)],
)
def logout(response: Response):
    # No server-side refresh-token store exists for either client type -
    # refresh tokens are stateless, signature-verified JWTs, not tracked
    # in the DB - so there's nothing to revoke here beyond the cookie.
    # Mobile's logout is effectively just deleting its local secure-
    # storage copy (see AuthRepository.logout()); this call is best-effort
    # for it and a no-op response either way.
    clear_auth_cookies(response)
    return None
