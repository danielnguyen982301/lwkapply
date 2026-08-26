"""
Shared FastAPI dependencies: DB session passthrough and
current-user resolution from a Bearer JWT.
"""

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy import select
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

# Sent by the mobile client (see mobile/lib/features/auth/data/auth_api.dart)
# on every auth request, so the API can tell a native client apart from a
# browser without relying on User-Agent sniffing.
MOBILE_CLIENT_HEADER = "x-client-platform"
MOBILE_CLIENT_VALUE = "mobile"


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

    user = db.execute(select(User).where(User.id == user_id)).scalars().first()
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


def is_mobile_client(request: Request) -> bool:
    """True if this request came from the mobile app rather than the web
    app. Header lookups on `request.headers` are case-insensitive, so this
    matches regardless of how the client capitalizes it."""
    return request.headers.get(MOBILE_CLIENT_HEADER, "").lower() == MOBILE_CLIENT_VALUE


def verify_csrf(request: Request) -> None:
    """Double-submit CSRF check, currently only guarding /auth/logout
    (see that endpoint's dependencies=[...] - /auth/refresh deliberately
    doesn't use this, see its own docstring for why). Every other
    endpoint authenticates via the Authorization header, which a
    cross-site form or script can't forge, so it doesn't need this.

    Compares this cookie against an X-CSRF-Token header the frontend
    sends. The frontend's copy of that value comes from the /login or
    /refresh JSON response body (TokenResponse.csrf_token) - not from
    reading this cookie via JS. That distinction matters when frontend
    and backend are on different origins (e.g. Vercel vs Render): the
    cookie itself still round-trips to the server fine regardless of
    origin (that's just how cookies work), but a different-origin
    frontend's own document.cookie can never see a cookie that belongs
    to this API's origin, so requiring the frontend to *read the cookie
    itself* - as this used to - only ever worked when frontend and
    backend shared an origin.
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


def verify_csrf_unless_mobile(request: Request) -> None:
    """Same endpoint(s) as `verify_csrf`, but skips the check for the
    mobile client.

    CSRF double-submit exists to stop a *browser* from silently riding an
    httpOnly cookie it holds for our site into a request from some other
    site's page. The mobile app never holds that cookie meaningfully - it
    presents its refresh token explicitly in the request body instead - so
    there's no cookie for a hostile page to ride in the first place. Web
    requests still go through the full check unchanged.
    """
    if is_mobile_client(request):
        return
    verify_csrf(request)
