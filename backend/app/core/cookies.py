"""app/core/cookies.py — new file.

Small, self-contained module for the refresh-token/CSRF cookie pair so
auth.py stays focused on request handling rather than cookie mechanics.
"""

import secrets

from fastapi import Response

from app.core.config import settings

REFRESH_COOKIE_NAME = "refresh_token"
CSRF_COOKIE_NAME = "csrf_token"

# Scoped to the auth routes only — the browser never needs to send this
# cookie to /applications, /interviews, etc., which use the bearer token
# instead. Narrower cookie scope = smaller attack surface.
REFRESH_COOKIE_PATH = "/api/v1/auth"


def generate_csrf_token() -> str:
    return secrets.token_urlsafe(32)


def set_auth_cookies(response: Response, refresh_token: str, csrf_token: str) -> None:
    """Set both the httpOnly refresh-token cookie and the JS-readable
    CSRF cookie. Call this on login, register->login, and refresh."""
    response.set_cookie(
        key=REFRESH_COOKIE_NAME,
        value=refresh_token,
        httponly=True,
        secure=settings.COOKIE_SECURE,
        samesite=settings.COOKIE_SAMESITE,
        path=REFRESH_COOKIE_PATH,
        max_age=settings.REFRESH_TOKEN_COOKIE_MAX_AGE,
    )
    response.set_cookie(
        key=CSRF_COOKIE_NAME,
        value=csrf_token,
        # httpOnly - the frontend gets its own copy of this value from
        # the /login and /refresh JSON response bodies now (see
        # TokenResponse.csrf_token), not by reading this cookie via JS,
        # since a frontend on a different origin than this API (e.g.
        # Vercel vs Render) can never read this cookie under the
        # same-origin policy regardless of this flag. Nothing reads it
        # via document.cookie anymore, so there's no reason to leave it
        # JS-accessible - the cookie only needs to keep existing so the
        # browser sends it back for the server-side double-submit
        # comparison in app/api/deps.py::verify_csrf.
        httponly=True,
        secure=settings.COOKIE_SECURE,
        samesite=settings.COOKIE_SAMESITE,
        path="/",  # sent alongside the request regardless of current path
        max_age=settings.REFRESH_TOKEN_COOKIE_MAX_AGE,
    )


def clear_auth_cookies(response: Response) -> None:
    """Starlette's Response.delete_cookie() defaults to
    secure=False, samesite="lax" when not told otherwise - silently
    different from what set_auth_cookies() above actually set
    (secure=settings.COOKIE_SECURE, samesite=settings.COOKIE_SAMESITE,
    "Secure; SameSite=None" in production). A deletion Set-Cookie with
    mismatched attributes from the cookie it's trying to overwrite is a
    well-known source of "logout doesn't actually clear the cookie"
    bugs - cookie storage matches on (name, domain, path), so it should
    still work in theory, but real browsers are inconsistent enough
    about this exact mismatch that relying on it isn't worth the risk.
    Passing the same attributes used to set it removes any ambiguity.
    """
    response.delete_cookie(
        REFRESH_COOKIE_NAME,
        path=REFRESH_COOKIE_PATH,
        secure=settings.COOKIE_SECURE,
        samesite=settings.COOKIE_SAMESITE,
    )
    response.delete_cookie(
        CSRF_COOKIE_NAME,
        path="/",
        secure=settings.COOKIE_SECURE,
        samesite=settings.COOKIE_SAMESITE,
    )
