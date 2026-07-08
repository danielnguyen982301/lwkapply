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
        httponly=False,  # frontend JS must read this one to echo it back
        secure=settings.COOKIE_SECURE,
        samesite=settings.COOKIE_SAMESITE,
        path="/",  # frontend needs to read it regardless of current path
        max_age=settings.REFRESH_TOKEN_COOKIE_MAX_AGE,
    )


def clear_auth_cookies(response: Response) -> None:
    response.delete_cookie(REFRESH_COOKIE_NAME, path=REFRESH_COOKIE_PATH)
    response.delete_cookie(CSRF_COOKIE_NAME, path="/")
