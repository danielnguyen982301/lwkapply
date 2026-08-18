"""
Integration tests for /notifications (app/api/v1/endpoints/notifications.py).

Read-mostly, top-level, user-owned resource - same DataTable/Paginator
shape as documents.py. The only real producer is
app/tasks/reminders.py::send_due_reminders (covered in
test_reminders.py); these tests insert Notification rows directly via
the ORM, same "these tests are about GET/POST /notifications, not about
how a row gets created" reasoning make_user uses for registration.
"""

import uuid
from datetime import datetime, timedelta, timezone

from app.models.notification import Notification, NotificationType

NOTIFICATIONS_URL = "/api/v1/notifications"


def _make_notification(db_session, user, **overrides):
    defaults = {
        "user_id": user.id,
        "type": NotificationType.INTERVIEW_REMINDER,
        "title": "Upcoming Technical interview at Acme",
        "body": "Engineer - tomorrow at 2pm",
    }
    defaults.update(overrides)
    notification = Notification(**defaults)
    db_session.add(notification)
    db_session.commit()
    db_session.refresh(notification)
    return notification


class TestNotificationsAuth:
    def test_list_requires_authentication(self, client):
        response = client.get(NOTIFICATIONS_URL)
        assert response.status_code == 401


class TestListNotifications:
    def test_lists_only_the_current_users_notifications(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        other_user = make_user()
        _make_notification(db_session, user, title="Mine")
        _make_notification(db_session, other_user, title="Not mine")

        response = client.get(NOTIFICATIONS_URL, headers=auth_headers(user))

        assert response.status_code == 200
        body = response.json()
        assert body["total"] == 1
        assert body["items"][0]["title"] == "Mine"

    def test_orders_newest_first(self, client, db_session, make_user, auth_headers):
        user = make_user()
        base = datetime.now(timezone.utc)
        _make_notification(
            db_session, user, title="Older", created_at=base - timedelta(hours=1)
        )
        _make_notification(db_session, user, title="Newer", created_at=base)

        response = client.get(NOTIFICATIONS_URL, headers=auth_headers(user))

        titles = [item["title"] for item in response.json()["items"]]
        assert titles == ["Newer", "Older"]

    def test_unread_only_filter(self, client, db_session, make_user, auth_headers):
        user = make_user()
        _make_notification(db_session, user, title="Unread")
        _make_notification(
            db_session,
            user,
            title="Already read",
            read_at=datetime.now(timezone.utc),
        )

        response = client.get(
            f"{NOTIFICATIONS_URL}?unread_only=true", headers=auth_headers(user)
        )

        body = response.json()
        assert body["total"] == 1
        assert body["items"][0]["title"] == "Unread"


class TestUnreadCount:
    def test_counts_only_unread(self, client, db_session, make_user, auth_headers):
        user = make_user()
        _make_notification(db_session, user)
        _make_notification(db_session, user)
        _make_notification(db_session, user, read_at=datetime.now(timezone.utc))

        response = client.get(
            f"{NOTIFICATIONS_URL}/unread-count", headers=auth_headers(user)
        )

        assert response.status_code == 200
        assert response.json()["unread_count"] == 2

    def test_zero_when_none_exist(self, client, make_user, auth_headers):
        user = make_user()

        response = client.get(
            f"{NOTIFICATIONS_URL}/unread-count", headers=auth_headers(user)
        )

        assert response.json()["unread_count"] == 0


class TestMarkRead:
    def test_marks_a_notification_read(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        notification = _make_notification(db_session, user)

        response = client.post(
            f"{NOTIFICATIONS_URL}/{notification.id}/read", headers=auth_headers(user)
        )

        assert response.status_code == 200
        assert response.json()["read_at"] is not None

    def test_marking_an_already_read_notification_is_idempotent(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        notification = _make_notification(
            db_session, user, read_at=datetime.now(timezone.utc)
        )
        notification_id = notification.id
        original_read_at = notification.read_at

        response = client.post(
            f"{NOTIFICATIONS_URL}/{notification_id}/read", headers=auth_headers(user)
        )

        assert response.status_code == 200
        refreshed = (
            db_session.query(Notification)
            .filter(Notification.id == notification_id)
            .first()
        )
        assert refreshed.read_at == original_read_at

    def test_cannot_mark_another_users_notification_read(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        other_user = make_user()
        notification = _make_notification(db_session, other_user)

        response = client.post(
            f"{NOTIFICATIONS_URL}/{notification.id}/read", headers=auth_headers(user)
        )

        assert response.status_code == 404

    def test_marking_nonexistent_notification_is_404(
        self, client, make_user, auth_headers
    ):
        user = make_user()

        response = client.post(
            f"{NOTIFICATIONS_URL}/{uuid.uuid4()}/read", headers=auth_headers(user)
        )

        assert response.status_code == 404


class TestMarkAllRead:
    def test_marks_every_unread_notification_read(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        first = _make_notification(db_session, user)
        second = _make_notification(db_session, user)

        response = client.post(
            f"{NOTIFICATIONS_URL}/read-all", headers=auth_headers(user)
        )

        assert response.status_code == 204
        db_session.refresh(first)
        db_session.refresh(second)
        assert first.read_at is not None
        assert second.read_at is not None

    def test_does_not_touch_another_users_notifications(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        other_user = make_user()
        others_notification = _make_notification(db_session, other_user)

        client.post(f"{NOTIFICATIONS_URL}/read-all", headers=auth_headers(user))

        db_session.refresh(others_notification)
        assert others_notification.read_at is None
