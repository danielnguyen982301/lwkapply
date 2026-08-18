"""
Integration tests for /users/me and its sub-resources
(app/api/v1/endpoints/users.py): profile update, password change, avatar
upload/delete, notification settings, and account deletion.

Uses the same fixtures as the other endpoint test files (client,
db_session, make_user, auth_headers - see conftest.py), plus a local,
file-scoped `fake_r2_client` fixture mirroring test_documents_endpoints.py's
mocking strategy - only app.services.r2._r2_client (the actual boto3
client factory) is patched, so validate_avatar_upload's content-type
check and the chunked size enforcement still run for real.
"""

import uuid
from unittest.mock import MagicMock

import pytest

import app.services.r2 as r2_service
from app.core.security import verify_password
from app.models.document import Document, DocumentType
from app.models.user import User

USERS_URL = "/api/v1/users"
PNG_BYTES = b"\x89PNG\r\n\x1a\nfake png content for testing"


def _make_document(db_session, user, **overrides):
    defaults = {
        "user_id": user.id,
        "file_name": "resume.pdf",
        "file_url": f"users/{user.id}/documents/{uuid.uuid4().hex[:12]}-resume.pdf",
        "file_type": DocumentType.RESUME,
    }
    defaults.update(overrides)
    document = Document(**defaults)
    db_session.add(document)
    db_session.commit()
    db_session.refresh(document)
    return document


@pytest.fixture(autouse=True)
def fake_r2_client(monkeypatch):
    fake_client = MagicMock()
    fake_client.put_object.return_value = {}
    fake_client.delete_object.return_value = {}
    fake_client.generate_presigned_url.return_value = (
        "https://fake-bucket.r2.cloudflarestorage.com/presigned-fake-key"
    )
    monkeypatch.setattr(r2_service, "_r2_client", lambda: fake_client)
    return fake_client


class TestUsersAuth:
    def test_read_me_requires_authentication(self, client):
        response = client.get(f"{USERS_URL}/me")
        assert response.status_code == 401


class TestUpdateProfile:
    def test_updates_first_and_last_name(self, client, make_user, auth_headers):
        user = make_user()

        response = client.patch(
            f"{USERS_URL}/me",
            json={"first_name": "Updated", "last_name": "Name"},
            headers=auth_headers(user),
        )

        assert response.status_code == 200
        body = response.json()
        assert body["first_name"] == "Updated"
        assert body["last_name"] == "Name"

    def test_valid_timezone_is_applied_and_marked_manual(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()

        response = client.patch(
            f"{USERS_URL}/me",
            json={"timezone": "America/New_York"},
            headers=auth_headers(user),
        )

        assert response.status_code == 200
        db_session.refresh(user)
        assert user.timezone == "America/New_York"
        assert user.timezone_is_manual is True

    def test_invalid_timezone_is_silently_ignored(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()

        response = client.patch(
            f"{USERS_URL}/me",
            json={"timezone": "Not/A_Real_Zone"},
            headers=auth_headers(user),
        )

        assert response.status_code == 200
        db_session.refresh(user)
        assert user.timezone is None
        assert user.timezone_is_manual is False

    def test_explicit_null_timezone_releases_manual_flag(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        client.patch(
            f"{USERS_URL}/me",
            json={"timezone": "America/New_York"},
            headers=auth_headers(user),
        )

        response = client.patch(
            f"{USERS_URL}/me", json={"timezone": None}, headers=auth_headers(user)
        )

        assert response.status_code == 200
        db_session.refresh(user)
        # The stored value is untouched - only the manual lock is released,
        # so the next login/refresh's auto-detect can resume writing it.
        assert user.timezone == "America/New_York"
        assert user.timezone_is_manual is False


class TestChangePassword:
    def test_wrong_current_password_is_rejected(self, client, make_user, auth_headers):
        user = make_user(password="correct-horse-battery-staple")

        response = client.post(
            f"{USERS_URL}/me/password",
            json={
                "current_password": "wrong-password",
                "new_password": "new-password-123",
            },
            headers=auth_headers(user),
        )

        assert response.status_code == 400

    def test_correct_current_password_updates_the_hash(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user(password="correct-horse-battery-staple")

        response = client.post(
            f"{USERS_URL}/me/password",
            json={
                "current_password": "correct-horse-battery-staple",
                "new_password": "new-password-123",
            },
            headers=auth_headers(user),
        )

        assert response.status_code == 204
        db_session.refresh(user)
        assert verify_password("new-password-123", user.password_hash)
        assert not verify_password("correct-horse-battery-staple", user.password_hash)


class TestAvatar:
    def test_upload_sets_avatar_and_returns_presigned_url(
        self, client, db_session, make_user, auth_headers, fake_r2_client
    ):
        user = make_user()

        response = client.post(
            f"{USERS_URL}/me/avatar",
            files={"file": ("avatar.png", PNG_BYTES, "image/png")},
            headers=auth_headers(user),
        )

        assert response.status_code == 200
        assert response.json()["avatar_url"].startswith("https://")
        db_session.refresh(user)
        assert user.avatar_url == f"users/{user.id}/avatar"
        fake_r2_client.put_object.assert_called_once()

    def test_upload_rejects_unsupported_content_type(
        self, client, make_user, auth_headers, fake_r2_client
    ):
        user = make_user()

        response = client.post(
            f"{USERS_URL}/me/avatar",
            files={"file": ("resume.pdf", b"%PDF-1.4", "application/pdf")},
            headers=auth_headers(user),
        )

        assert response.status_code == 415
        fake_r2_client.put_object.assert_not_called()

    def test_delete_clears_avatar(
        self, client, db_session, make_user, auth_headers, fake_r2_client
    ):
        user = make_user()
        client.post(
            f"{USERS_URL}/me/avatar",
            files={"file": ("avatar.png", PNG_BYTES, "image/png")},
            headers=auth_headers(user),
        )

        response = client.delete(f"{USERS_URL}/me/avatar", headers=auth_headers(user))

        assert response.status_code == 200
        assert response.json()["avatar_url"] is None
        db_session.refresh(user)
        assert user.avatar_url is None
        fake_r2_client.delete_object.assert_called_once()


class TestSettings:
    def test_read_returns_defaults(self, client, make_user, auth_headers):
        user = make_user()

        response = client.get(f"{USERS_URL}/me/settings", headers=auth_headers(user))

        assert response.status_code == 200
        body = response.json()
        assert body["reminder_lead_hours"] is None
        assert body["notifications_enabled"] is True
        assert body["email_notifications_enabled"] is True
        assert body["push_notifications_enabled"] is True

    def test_patch_updates_reminder_lead_hours(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()

        response = client.patch(
            f"{USERS_URL}/me/settings",
            json={"reminder_lead_hours": 2},
            headers=auth_headers(user),
        )

        assert response.status_code == 200
        assert response.json()["reminder_lead_hours"] == 2
        db_session.refresh(user)
        assert user.settings.reminder_lead_hours == 2

    def test_patch_out_of_bounds_reminder_lead_hours_is_rejected(
        self, client, make_user, auth_headers
    ):
        user = make_user()

        response = client.patch(
            f"{USERS_URL}/me/settings",
            json={"reminder_lead_hours": 200},
            headers=auth_headers(user),
        )

        assert response.status_code == 422

    def test_patch_explicit_null_resets_reminder_lead_hours(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        client.patch(
            f"{USERS_URL}/me/settings",
            json={"reminder_lead_hours": 2},
            headers=auth_headers(user),
        )

        response = client.patch(
            f"{USERS_URL}/me/settings",
            json={"reminder_lead_hours": None},
            headers=auth_headers(user),
        )

        assert response.status_code == 200
        assert response.json()["reminder_lead_hours"] is None

    def test_patch_toggles_notification_channels(self, client, make_user, auth_headers):
        user = make_user()

        response = client.patch(
            f"{USERS_URL}/me/settings",
            json={
                "notifications_enabled": False,
                "email_notifications_enabled": False,
                "push_notifications_enabled": False,
            },
            headers=auth_headers(user),
        )

        assert response.status_code == 200
        body = response.json()
        assert body["notifications_enabled"] is False
        assert body["email_notifications_enabled"] is False
        assert body["push_notifications_enabled"] is False


class TestDeleteAccount:
    def test_wrong_password_is_rejected(self, client, make_user, auth_headers):
        user = make_user(password="correct-horse-battery-staple")

        response = client.request(
            "DELETE",
            f"{USERS_URL}/me",
            json={"password": "wrong-password"},
            headers=auth_headers(user),
        )

        assert response.status_code == 400

    def test_correct_password_deletes_the_account_and_cleans_up_r2(
        self, client, db_session, make_user, auth_headers, fake_r2_client
    ):
        user = make_user(password="correct-horse-battery-staple")
        document = _make_document(db_session, user)
        # Captured before the delete request - `user`/`document` become a
        # deleted+expired instance afterward (expire_on_commit), and
        # further attribute access on those specific Python objects would
        # raise ObjectDeletedError rather than return stale data.
        user_id = user.id
        document_file_url = document.file_url
        client.post(
            f"{USERS_URL}/me/avatar",
            files={"file": ("avatar.png", PNG_BYTES, "image/png")},
            headers=auth_headers(user),
        )
        fake_r2_client.delete_object.reset_mock()
        headers = auth_headers(user)

        response = client.request(
            "DELETE",
            f"{USERS_URL}/me",
            json={"password": "correct-horse-battery-staple"},
            headers=headers,
        )

        assert response.status_code == 204
        assert db_session.query(User).filter(User.id == user_id).first() is None

        deleted_keys = {
            call.kwargs["Key"] for call in fake_r2_client.delete_object.call_args_list
        }
        assert document_file_url in deleted_keys
        assert f"users/{user_id}/avatar" in deleted_keys

        follow_up = client.get(f"{USERS_URL}/me", headers=headers)
        assert follow_up.status_code == 401
