"""
Integration tests for /auth/login, /auth/refresh, /auth/logout
(app/api/v1/endpoints/auth.py), focused on the cookie/CSRF mechanics
rather than credential validation.

TestClient keeps a real cookie jar across requests made with the same
client instance (it wraps an httpx.Client), so these exercise the actual
browser-like flow: login sets cookies, refresh/logout are called with
whatever the client's jar holds - no manual cookie plumbing needed.
"""

from app.core.security import hash_password
from app.models.user import User

REGISTER_URL = "/api/v1/auth/register"
LOGIN_URL = "/api/v1/auth/login"
REFRESH_URL = "/api/v1/auth/refresh"
LOGOUT_URL = "/api/v1/auth/logout"


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
    def test_login_response_includes_csrf_token(self, client, db_session):
        _, password = _make_user(db_session)

        response = client.post(
            LOGIN_URL, json={"email": "csrf-test@example.com", "password": password}
        )

        assert response.status_code == 200
        body = response.json()
        assert body["csrf_token"]
        assert isinstance(body["csrf_token"], str)


class TestRefreshDoesNotRequireCsrf:
    def test_refresh_succeeds_with_no_csrf_header(self, client, db_session):
        """The regression this guards against: bootstrap() on a hard
        reload has no in-memory CSRF token to send yet, so /auth/refresh
        must work from the cookie jar alone."""
        _, password = _make_user(db_session)
        client.post(
            LOGIN_URL, json={"email": "csrf-test@example.com", "password": password}
        )

        response = client.post(REFRESH_URL, headers={})

        assert response.status_code == 200
        assert response.json()["csrf_token"]

    def test_refresh_401s_with_no_session_at_all(self, client):
        response = client.post(REFRESH_URL)
        assert response.status_code == 401


class TestLogoutStillRequiresCsrf:
    def test_logout_403s_without_csrf_header(self, client, db_session):
        _, password = _make_user(db_session)
        client.post(
            LOGIN_URL, json={"email": "csrf-test@example.com", "password": password}
        )

        response = client.post(LOGOUT_URL)

        assert response.status_code == 403

    def test_logout_succeeds_with_csrf_token_from_login_response(
        self, client, db_session
    ):
        _, password = _make_user(db_session)
        login_response = client.post(
            LOGIN_URL, json={"email": "csrf-test@example.com", "password": password}
        )
        csrf_token = login_response.json()["csrf_token"]

        response = client.post(LOGOUT_URL, headers={"X-CSRF-Token": csrf_token})

        assert response.status_code == 204

    def test_logout_403s_with_wrong_csrf_token(self, client, db_session):
        _, password = _make_user(db_session)
        client.post(
            LOGIN_URL, json={"email": "csrf-test@example.com", "password": password}
        )

        response = client.post(
            LOGOUT_URL, headers={"X-CSRF-Token": "not-the-right-token"}
        )

        assert response.status_code == 403
