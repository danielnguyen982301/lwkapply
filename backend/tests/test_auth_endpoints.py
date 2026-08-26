"""
Integration tests for /auth/login, /auth/refresh, /auth/logout
(app/api/v1/endpoints/auth.py), focused on the cookie/CSRF mechanics
rather than credential validation.

Every test here uses the `https_client` fixture below rather than
conftest.py's plain `client` - deliberately pinning settings.COOKIE_SECURE
and settings.COOKIE_SAMESITE to production's real values ("Secure;
SameSite=None") instead of relying on whatever's ambient. Locally that's
.env.local's COOKIE_SECURE=False/COOKIE_SAMESITE=lax; in CI it's
config.py's class defaults (True/"none"), since .env.local is gitignored
and never present there - so this file's tests silently behaved
differently depending on which environment ran them until this was
pinned explicitly, which is exactly the kind of fragility the CSRF fix
these tests cover was itself about hunting down. A plain http://testserver
client also can't store a Secure cookie at all (correct browser
behavior, but means these need an https base_url to exercise real
cross-origin cookie behavior at all, regardless of environment).

TestClient keeps a real cookie jar across requests made with the same
client instance (it wraps an httpx.Client), so these exercise the actual
browser-like flow: login sets cookies, refresh/logout are called with
whatever the client's jar holds - no manual cookie plumbing needed.
"""

from typing import Generator

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.core.security import hash_password
from app.db.session import get_db
from app.main import app
from app.models.user import User

REGISTER_URL = "/api/v1/auth/register"
LOGIN_URL = "/api/v1/auth/login"
REFRESH_URL = "/api/v1/auth/refresh"
LOGOUT_URL = "/api/v1/auth/logout"


@pytest.fixture()
def https_client(db_session: Session, monkeypatch) -> Generator[TestClient, None, None]:
    from app.core.config import settings

    monkeypatch.setattr(settings, "COOKIE_SECURE", True)
    monkeypatch.setattr(settings, "COOKIE_SAMESITE", "none")

    def _get_db_override() -> Generator[Session, None, None]:
        yield db_session

    app.dependency_overrides[get_db] = _get_db_override
    with TestClient(app, base_url="https://testserver") as test_client:
        yield test_client
    app.dependency_overrides.clear()


def _make_user(
    db_session, email="csrf-test@example.com", password="correct-horse-battery"
):
    user = User(
        email=email,
        password_hash=hash_password(password),
        first_name="Test",
        last_name="User",
    )
    db_session.add(user)
    db_session.commit()
    db_session.refresh(user)
    return user, password


class TestLoginReturnsCsrfToken:
    def test_login_response_includes_csrf_token(self, https_client, db_session):
        _, password = _make_user(db_session)

        response = https_client.post(
            LOGIN_URL, json={"email": "csrf-test@example.com", "password": password}
        )

        assert response.status_code == 200
        body = response.json()
        assert body["csrf_token"]
        assert isinstance(body["csrf_token"], str)


class TestRefreshDoesNotRequireCsrf:
    def test_refresh_succeeds_with_no_csrf_header(self, https_client, db_session):
        """The regression this guards against: bootstrap() on a hard
        reload has no in-memory CSRF token to send yet, so /auth/refresh
        must work from the cookie jar alone."""
        _, password = _make_user(db_session)
        https_client.post(
            LOGIN_URL, json={"email": "csrf-test@example.com", "password": password}
        )

        response = https_client.post(REFRESH_URL, headers={})

        assert response.status_code == 200
        assert response.json()["csrf_token"]

    def test_refresh_401s_with_no_session_at_all(self, https_client):
        response = https_client.post(REFRESH_URL)
        assert response.status_code == 401


class TestLogoutStillRequiresCsrf:
    def test_logout_403s_without_csrf_header(self, https_client, db_session):
        _, password = _make_user(db_session)
        https_client.post(
            LOGIN_URL, json={"email": "csrf-test@example.com", "password": password}
        )

        response = https_client.post(LOGOUT_URL)

        assert response.status_code == 403

    def test_logout_succeeds_with_csrf_token_from_login_response(
        self, https_client, db_session
    ):
        _, password = _make_user(db_session)
        login_response = https_client.post(
            LOGIN_URL, json={"email": "csrf-test@example.com", "password": password}
        )
        csrf_token = login_response.json()["csrf_token"]

        response = https_client.post(LOGOUT_URL, headers={"X-CSRF-Token": csrf_token})

        assert response.status_code == 204

    def test_logout_403s_with_wrong_csrf_token(self, https_client, db_session):
        _, password = _make_user(db_session)
        https_client.post(
            LOGIN_URL, json={"email": "csrf-test@example.com", "password": password}
        )

        response = https_client.post(
            LOGOUT_URL, headers={"X-CSRF-Token": "not-the-right-token"}
        )

        assert response.status_code == 403


class TestLogoutCookieDeletionMatchesProductionAttributes:
    """Regression test for a bug that only reproduced in production:
    Starlette's Response.delete_cookie() defaults to
    secure=False, samesite="lax" when not told otherwise, silently
    different from what set_auth_cookies() actually set the cookies
    with. Covered by the same production-shaped https_client fixture as
    the rest of this file now - see the module docstring.
    """

    def test_delete_cookie_headers_match_set_cookie_attributes(
        self, https_client, db_session
    ):
        _, password = _make_user(db_session)
        login_response = https_client.post(
            LOGIN_URL, json={"email": "csrf-test@example.com", "password": password}
        )
        csrf_token = login_response.json()["csrf_token"]

        response = https_client.post(LOGOUT_URL, headers={"X-CSRF-Token": csrf_token})

        assert response.status_code == 204
        set_cookie_headers = response.headers.get_list("set-cookie")
        assert len(set_cookie_headers) == 2
        for header in set_cookie_headers:
            lowered = header.lower()
            assert "secure" in lowered, header
            assert "samesite=none" in lowered, header
