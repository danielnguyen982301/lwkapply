"""
Integration tests for the Application.status -> application_status_history
write path (app/services/application_history.py, wired into
app/api/v1/endpoints/applications.py's create/update handlers).

Deliberately does NOT test any aggregation/funnel logic reading this
table - none exists yet (see application_status_history.py's module
docstring). These tests only cover "is the audit log itself correct":
one row per real transition, no row for a no-op, and history rows are
never deduplicated even across an accidental flip-and-revert - that's
by design, since this table is meant to be a faithful record, with any
noise-filtering (e.g. a minimum-dwell-time rule) deferred to whatever
future code reads it, not to the write path.
"""

import uuid

from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.models.application import ApplicationStatus
from app.models.application_status_history import ApplicationStatusHistory
from app.models.user import User


def _history_for(
    db_session: Session, application_id: uuid.UUID
) -> list[ApplicationStatusHistory]:
    return (
        db_session.query(ApplicationStatusHistory)
        .filter(ApplicationStatusHistory.application_id == application_id)
        .order_by(ApplicationStatusHistory.created_at)
        .all()
    )


def _create_application(client: TestClient, headers: dict, **overrides) -> dict:
    payload = {"company": "Acme", "position": "Engineer", **overrides}
    resp = client.post("/api/v1/applications", json=payload, headers=headers)
    assert resp.status_code == 201, resp.text
    return resp.json()


class TestCreateWritesInitialRow:
    def test_create_writes_one_row_with_null_from_status(
        self, client: TestClient, db_session: Session, make_user, auth_headers
    ):
        user: User = make_user()
        headers = auth_headers(user)

        application = _create_application(client, headers)

        history = _history_for(db_session, uuid.UUID(application["id"]))
        assert len(history) == 1
        assert history[0].from_status is None
        assert history[0].to_status == ApplicationStatus.SAVED

    def test_create_with_explicit_status_records_that_status(
        self, client: TestClient, db_session: Session, make_user, auth_headers
    ):
        user: User = make_user()
        headers = auth_headers(user)

        application = _create_application(client, headers, status="applied")

        history = _history_for(db_session, uuid.UUID(application["id"]))
        assert len(history) == 1
        assert history[0].from_status is None
        assert history[0].to_status == ApplicationStatus.APPLIED


class TestUpdateWritesTransitionRow:
    def test_status_change_writes_a_row_with_correct_from_and_to(
        self, client: TestClient, db_session: Session, make_user, auth_headers
    ):
        user: User = make_user()
        headers = auth_headers(user)
        application = _create_application(client, headers)  # starts at SAVED

        resp = client.patch(
            f"/api/v1/applications/{application['id']}",
            json={"status": "applied"},
            headers=headers,
        )
        assert resp.status_code == 200, resp.text

        history = _history_for(db_session, uuid.UUID(application["id"]))
        assert len(history) == 2  # create row + this transition
        assert history[1].from_status == ApplicationStatus.SAVED
        assert history[1].to_status == ApplicationStatus.APPLIED

    def test_update_without_touching_status_writes_no_row(
        self, client: TestClient, db_session: Session, make_user, auth_headers
    ):
        user: User = make_user()
        headers = auth_headers(user)
        application = _create_application(client, headers)

        resp = client.patch(
            f"/api/v1/applications/{application['id']}",
            json={"notes": "Referred by a friend"},
            headers=headers,
        )
        assert resp.status_code == 200, resp.text

        history = _history_for(db_session, uuid.UUID(application["id"]))
        assert len(history) == 1  # only the create row

    def test_setting_status_to_its_current_value_writes_no_row(
        self, client: TestClient, db_session: Session, make_user, auth_headers
    ):
        user: User = make_user()
        headers = auth_headers(user)
        application = _create_application(client, headers)  # starts at SAVED

        resp = client.patch(
            f"/api/v1/applications/{application['id']}",
            json={"status": "saved"},
            headers=headers,
        )
        assert resp.status_code == 200, resp.text

        history = _history_for(db_session, uuid.UUID(application["id"]))
        assert len(history) == 1  # no-op transition isn't recorded

    def test_flip_and_revert_records_both_transitions_undeduplicated(
        self, client: TestClient, db_session: Session, make_user, auth_headers
    ):
        """The accidental-mis-click scenario: covers that this table is a
        faithful audit log, not a pre-filtered one - the write path
        never tries to guess whether a transition was "real". Any
        filtering for accidental flips belongs to a future reader of
        this table, not here - see the module docstring."""
        user: User = make_user()
        headers = auth_headers(user)
        application = _create_application(client, headers)  # starts at SAVED

        client.patch(
            f"/api/v1/applications/{application['id']}",
            json={"status": "offer"},
            headers=headers,
        )
        client.patch(
            f"/api/v1/applications/{application['id']}",
            json={"status": "saved"},
            headers=headers,
        )

        history = _history_for(db_session, uuid.UUID(application["id"]))
        assert len(history) == 3
        assert (history[1].from_status, history[1].to_status) == (
            ApplicationStatus.SAVED,
            ApplicationStatus.OFFER,
        )
        assert (history[2].from_status, history[2].to_status) == (
            ApplicationStatus.OFFER,
            ApplicationStatus.SAVED,
        )


class TestOwnershipAndCascade:
    def test_deleting_application_cascades_to_history(
        self, client: TestClient, db_session: Session, make_user, auth_headers
    ):
        user: User = make_user()
        headers = auth_headers(user)
        application = _create_application(client, headers)
        application_id = uuid.UUID(application["id"])

        assert len(_history_for(db_session, application_id)) == 1

        resp = client.delete(
            f"/api/v1/applications/{application['id']}", headers=headers
        )
        assert resp.status_code == 204

        assert _history_for(db_session, application_id) == []

    def test_history_rows_are_scoped_through_the_owning_application(
        self, client: TestClient, db_session: Session, make_user, auth_headers
    ):
        """No endpoint exposes this table directly yet, so the only
        ownership boundary that matters today is the one already
        enforced by the FK to applications - a user can only ever
        produce history rows for applications they own, since
        create/update both run through _get_owned_application()."""
        owner: User = make_user()
        other: User = make_user()
        application = _create_application(client, headers=auth_headers(owner))

        # `other` can't even reach the application to mutate its status.
        resp = client.patch(
            f"/api/v1/applications/{application['id']}",
            json={"status": "applied"},
            headers=auth_headers(other),
        )
        assert resp.status_code == 404

        history = _history_for(db_session, uuid.UUID(application["id"]))
        assert len(history) == 1  # only the owner's create row
        assert history[0].to_status == ApplicationStatus.SAVED
