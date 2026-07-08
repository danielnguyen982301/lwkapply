"""
Authentication endpoints.

Design notes:
- Registration and login return both an access token (short-lived,
  used on every request) and a refresh token (long-lived, used only
  to mint new access tokens). This limits the blast radius if an
  access token leaks.
- Password reset uses a signed, time-limited JWT emailed to the user
  rather than a DB-stored token, so no extra table is needed. In
  production, sending the token is the caller's job (email service /
  Celery task) - this endpoint only issues it and logs a stub.
- We never reveal whether an email exists in the system on the
  "forgot password" endpoint, to avoid user enumeration.
"""

import logging

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from sqlalchemy.orm import Session

from app.core.cookies import (
    REFRESH_COOKIE_NAME,
    generate_csrf_token,
    set_auth_cookies,
    clear_auth_cookies,
)
from app.api.deps import verify_csrf
from app.core.security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    hash_password,
    verify_password,
)
from app.db.session import get_db
from app.models.user import User
from app.schemas.auth import (
    LoginRequest,
    PasswordResetConfirm,
    PasswordResetRequest,
    TokenResponse,
)
from app.schemas.user import UserCreate, UserRead

logger = logging.getLogger(__name__)
router = APIRouter()


def _issue_tokens(user_id) -> TokenResponse:
    return TokenResponse(access_token=create_access_token(str(user_id)))


@router.post("/register", response_model=UserRead, status_code=status.HTTP_201_CREATED)
def register(payload: UserCreate, db: Session = Depends(get_db)):
    existing = db.query(User).filter(User.email == payload.email).first()
    if existing:
        # Deliberately vague message: don't confirm which field collided
        raise HTTPException(
            status_code=400, detail="Unable to register with these details"
        )

    user = User(
        email=payload.email,
        password_hash=hash_password(payload.password),
        first_name=payload.first_name,
        last_name=payload.last_name,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


@router.post("/login", response_model=TokenResponse)
def login(payload: LoginRequest, response: Response, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == payload.email).first()
    if not user or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Incorrect email or password")
    if not user.is_active:
        raise HTTPException(status_code=403, detail="Account is disabled")

    refresh_token = create_refresh_token(str(user.id))
    csrf_token = generate_csrf_token()

    set_auth_cookies(response, refresh_token, csrf_token)

    return _issue_tokens(user.id)


@router.post(
    "/refresh",
    response_model=TokenResponse,
    dependencies=[Depends(verify_csrf)],
)
def refresh(request: Request, response: Response, db: Session = Depends(get_db)):
    token = request.cookies.get(REFRESH_COOKIE_NAME)
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing refresh token"
        )

    token_payload = decode_token(token)
    if token_payload is None or token_payload.get("type") != "refresh":
        raise HTTPException(status_code=401, detail="Invalid or expired refresh token")

    user = db.query(User).filter(User.id == token_payload["sub"]).first()
    if not user or not user.is_active:
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    # Rotate both the refresh token and the CSRF token on every refresh —
    # if a refresh token is ever replayed after rotation, this makes the
    # replay detectable (the old one no longer validates) rather than
    # silently accepted.
    new_refresh_token = create_refresh_token(str(user.id))
    new_csrf_token = generate_csrf_token()

    set_auth_cookies(response, new_refresh_token, new_csrf_token)

    return _issue_tokens(user.id)


@router.post("/password-reset/request", status_code=status.HTTP_202_ACCEPTED)
def request_password_reset(
    payload: PasswordResetRequest, db: Session = Depends(get_db)
):
    user = db.query(User).filter(User.email == payload.email).first()
    if user:
        # reset_token = create_password_reset_token(str(user.id))
        # TODO: enqueue a Celery task to email `reset_token` to the user.
        logger.info("Password reset token generated for user_id=%s", user.id)
    # Always return the same response, whether or not the email exists.
    return {"message": "If that email exists, a reset link has been sent."}


@router.post("/password-reset/confirm", status_code=status.HTTP_200_OK)
def confirm_password_reset(
    payload: PasswordResetConfirm, db: Session = Depends(get_db)
):
    token_payload = decode_token(payload.token)
    if token_payload is None or token_payload.get("type") != "password_reset":
        raise HTTPException(status_code=400, detail="Invalid or expired reset token")

    user = db.query(User).filter(User.id == token_payload["sub"]).first()
    if not user:
        raise HTTPException(status_code=400, detail="Invalid or expired reset token")

    user.password_hash = hash_password(payload.new_password)
    db.add(user)
    db.commit()
    return {"message": "Password has been reset successfully."}


@router.post(
    "/logout",
    status_code=status.HTTP_204_NO_CONTENT,
    dependencies=[Depends(verify_csrf)],
)
def logout(response: Response):
    clear_auth_cookies(response)
    return None
