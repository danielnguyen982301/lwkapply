"""
Shared FastAPI dependencies: DB session passthrough and
current-user resolution from a Bearer JWT.
"""

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
import secrets

from app.core.security import decode_token
from app.db.session import get_db
from app.models.user import User, UserRole
from app.core.cookies import CSRF_COOKIE_NAME

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")

CREDENTIALS_EXCEPTION = HTTPException(
    status_code=status.HTTP_401_UNAUTHORIZED,
    detail="Could not validate credentials",
    headers={"WWW-Authenticate": "Bearer"},
)


def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
) -> User:
    payload = decode_token(token)
    if payload is None or payload.get("type") != "access":
        raise CREDENTIALS_EXCEPTION

    user_id = payload.get("sub")
    if user_id is None:
        raise CREDENTIALS_EXCEPTION

    user = db.query(User).filter(User.id == user_id).first()
    if user is None or not user.is_active:
        raise CREDENTIALS_EXCEPTION

    return user


def get_current_active_user(user: User = Depends(get_current_user)) -> User:
    if not user.is_active:
        raise HTTPException(status_code=400, detail="Inactive user")
    return user


def require_admin(user: User = Depends(get_current_user)) -> User:
    if user.role != UserRole.ADMIN:
        raise HTTPException(status_code=403, detail="Admin privileges required")
    return user


def verify_csrf(request: Request) -> None:
    """Double-submit CSRF check for the two cookie-authenticated
    endpoints (/auth/refresh, /auth/logout). Every other endpoint
    authenticates via the Authorization header, which a cross-site form
    or script can't forge, so it doesn't need this.

    Requires the frontend to read the (non-httpOnly) csrf_token cookie
    and echo its value back in an X-CSRF-Token header — something only
    same-origin JS can do, since a different origin's script can't read
    our cookies under the browser's same-origin policy.
    """
    cookie_value = request.cookies.get(CSRF_COOKIE_NAME)
    header_value = request.headers.get("x-csrf-token")

    if (
        not cookie_value
        or not header_value
        or not secrets.compare_digest(cookie_value, header_value)
    ):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Missing or invalid CSRF token",
        )
