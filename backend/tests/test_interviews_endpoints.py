"""
Integration tests for /applications/{application_id}/interviews
(app/api/v1/endpoints/interviews.py).

Uses the same fixtures as test_applications_endpoints.py /
test_contacts_directory.py (client, db_session, make_user, auth_headers -
see conftest.py).

Two things specific to this resource, worth calling out:

1. Interview.result is declared with server_default=InterviewResult.PENDING
   (the raw enum member, not .value). BACKEND_SUMMARY.md's note on this
   actually claims the opposite (a Python-side default=), so docs and code
   disagree. create_interview() always sends `result` explicitly (the
   schema has a pydantic-level default of PENDING), so the *server*-side
   default is never exercised through the normal create path - only a
   direct DB insert omitting `result` hits it. TestInterviewResultServerDefault
   below is an isolated, clearly-flagged test of that path; if
   server_default can't compile the raw enum into valid DDL, it would
   error out at table-creation time and break the whole suite's
   session-scoped `engine` fixture, not just this file - worth running
   this file first in isolation if in doubt.

2. Interview is nested two levels deep (Interview -> Application -> User).
   Unlike Contacts' or Applications' ownership tests, this resource needs
   a *second* scoping check beyond "does this user own it": an interview
   under Application A must not be reachable via Application B's URL,
   even when the same user owns both applications. See
   TestInterviewApplicationScoping.
"""

from datetime import datetime, timedelta, timezone

from app.models.application import Application, ApplicationStatus
from app.models.interview import Interview, InterviewResult, InterviewType

BASE_SCHEDULED_AT = datetime(2026, 8, 1, 14, 0, tzinfo=timezone.utc)


def _applications_url(application_id) -> str:
    return f"/api/v1/applications/{application_id}"


def _interviews_url(application_id) -> str:
    return f"{_applications_url(application_id)}/interviews"


def _make_application(db_session, user, **overrides):
    defaults = {
        "user_id": user.id,
        "company": "Initech",
        "position": "Backend Engineer",
        "status": ApplicationStatus.SAVED,
    }
    defaults.update(overrides)
    application = Application(**defaults)
    db_session.add(application)
    db_session.commit()
    db_session.refresh(application)
    return application


def _make_interview(db_session, application, **overrides):
    # result is set explicitly here (not omitted) deliberately - see the
    # module docstring on why leaving it unset would exercise the
    # possibly-broken server_default path in every helper call, not just
    # the one test meant to check it.
    defaults = {
        "application_id": application.id,
        "type": InterviewType.TECHNICAL,
        "scheduled_at": BASE_SCHEDULED_AT,
        "result": InterviewResult.PENDING,
    }
    defaults.update(overrides)
    interview = Interview(**defaults)
    db_session.add(interview)
    db_session.commit()
    db_session.refresh(interview)
    return interview


class TestInterviewsAuth:
    def test_list_requires_authentication(self, client, db_session, make_user):
        user = make_user()
        application = _make_application(db_session, user)
        response = client.get(_interviews_url(application.id))
        assert response.status_code == 401

    def test_create_requires_authentication(self, client, db_session, make_user):
        user = make_user()
        application = _make_application(db_session, user)
        response = client.post(
            _interviews_url(application.id),
            json={"type": "technical", "scheduled_at": BASE_SCHEDULED_AT.isoformat()},
        )
        assert response.status_code == 401

    def test_rejects_invalid_token(self, client, db_session, make_user):
        user = make_user()
        application = _make_application(db_session, user)
        response = client.get(
            _interviews_url(application.id),
            headers={"Authorization": "Bearer not-a-real-token"},
        )
        assert response.status_code == 401


class TestCreateInterview:
    def test_creates_interview_for_owned_application(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)

        response = client.post(
            _interviews_url(application.id),
            json={"type": "technical", "scheduled_at": BASE_SCHEDULED_AT.isoformat()},
            headers=auth_headers(user),
        )

        assert response.status_code == 201
        body = response.json()
        assert body["type"] == "technical"
        assert body["application_id"] == str(application.id)
        assert body["result"] == "pending"
        assert "id" in body

    def test_missing_scheduled_at_is_rejected(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)

        response = client.post(
            _interviews_url(application.id),
            json={"type": "technical"},
            headers=auth_headers(user),
        )
        assert response.status_code == 422

    def test_invalid_type_is_rejected(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)

        response = client.post(
            _interviews_url(application.id),
            json={
                "type": "not-a-real-type",
                "scheduled_at": BASE_SCHEDULED_AT.isoformat(),
            },
            headers=auth_headers(user),
        )
        assert response.status_code == 422

    def test_zero_duration_is_rejected(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)

        response = client.post(
            _interviews_url(application.id),
            json={
                "type": "technical",
                "scheduled_at": BASE_SCHEDULED_AT.isoformat(),
                "duration_minutes": 0,
            },
            headers=auth_headers(user),
        )
        assert response.status_code == 422

    def test_duration_over_24h_is_rejected(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)

        response = client.post(
            _interviews_url(application.id),
            json={
                "type": "technical",
                "scheduled_at": BASE_SCHEDULED_AT.isoformat(),
                "duration_minutes": 1441,
            },
            headers=auth_headers(user),
        )
        assert response.status_code == 422

    def test_boundary_durations_are_accepted(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)

        for minutes in (1, 1440):
            response = client.post(
                _interviews_url(application.id),
                json={
                    "type": "technical",
                    "scheduled_at": BASE_SCHEDULED_AT.isoformat(),
                    "duration_minutes": minutes,
                },
                headers=auth_headers(user),
            )
            assert response.status_code == 201
            assert response.json()["duration_minutes"] == minutes

    def test_explicit_result_overrides_default(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)

        response = client.post(
            _interviews_url(application.id),
            json={
                "type": "technical",
                "scheduled_at": BASE_SCHEDULED_AT.isoformat(),
                "result": "passed",
            },
            headers=auth_headers(user),
        )
        assert response.status_code == 201
        assert response.json()["result"] == "passed"

    def test_cannot_create_under_nonexistent_application(
        self, client, make_user, auth_headers
    ):
        import uuid

        user = make_user()
        response = client.post(
            _interviews_url(uuid.uuid4()),
            json={"type": "technical", "scheduled_at": BASE_SCHEDULED_AT.isoformat()},
            headers=auth_headers(user),
        )
        assert response.status_code == 404

    def test_cannot_create_under_another_users_application(
        self, client, db_session, make_user, auth_headers
    ):
        owner = make_user()
        other_user = make_user()
        application = _make_application(db_session, owner)

        response = client.post(
            _interviews_url(application.id),
            json={"type": "technical", "scheduled_at": BASE_SCHEDULED_AT.isoformat()},
            headers=auth_headers(other_user),
        )
        assert response.status_code == 404

        remaining = (
            db_session.query(Interview)
            .filter(Interview.application_id == application.id)
            .count()
        )
        assert remaining == 0


class TestGetInterview:
    def test_returns_owned_interview(self, client, db_session, make_user, auth_headers):
        user = make_user()
        application = _make_application(db_session, user)
        interview = _make_interview(db_session, application)

        response = client.get(
            f"{_interviews_url(application.id)}/{interview.id}",
            headers=auth_headers(user),
        )

        assert response.status_code == 200
        assert response.json()["id"] == str(interview.id)

    def test_nonexistent_interview_is_404(
        self, client, db_session, make_user, auth_headers
    ):
        import uuid

        user = make_user()
        application = _make_application(db_session, user)

        response = client.get(
            f"{_interviews_url(application.id)}/{uuid.uuid4()}",
            headers=auth_headers(user),
        )
        assert response.status_code == 404

    def test_malformed_id_is_422(self, client, db_session, make_user, auth_headers):
        user = make_user()
        application = _make_application(db_session, user)

        response = client.get(
            f"{_interviews_url(application.id)}/not-a-uuid", headers=auth_headers(user)
        )
        assert response.status_code == 422


class TestInterviewOwnership:
    """Cross-user IDOR checks - see TestInterviewApplicationScoping below
    for the same-user, wrong-application variant, which is a distinct
    concern for a resource nested this deep."""

    def test_cannot_get_another_users_interview(
        self, client, db_session, make_user, auth_headers
    ):
        owner = make_user()
        other_user = make_user()
        application = _make_application(db_session, owner)
        interview = _make_interview(db_session, application)

        response = client.get(
            f"{_interviews_url(application.id)}/{interview.id}",
            headers=auth_headers(other_user),
        )
        assert response.status_code == 404

    def test_cannot_update_another_users_interview(
        self, client, db_session, make_user, auth_headers
    ):
        owner = make_user()
        other_user = make_user()
        application = _make_application(db_session, owner)
        interview = _make_interview(
            db_session, application, feedback="Original feedback"
        )

        response = client.patch(
            f"{_interviews_url(application.id)}/{interview.id}",
            json={"feedback": "Hijacked feedback"},
            headers=auth_headers(other_user),
        )
        assert response.status_code == 404

        db_session.refresh(interview)
        assert interview.feedback == "Original feedback"

    def test_cannot_delete_another_users_interview(
        self, client, db_session, make_user, auth_headers
    ):
        owner = make_user()
        other_user = make_user()
        application = _make_application(db_session, owner)
        interview = _make_interview(db_session, application)

        response = client.delete(
            f"{_interviews_url(application.id)}/{interview.id}",
            headers=auth_headers(other_user),
        )
        assert response.status_code == 404

        still_there = (
            db_session.query(Interview).filter(Interview.id == interview.id).first()
        )
        assert still_there is not None

    def test_cannot_list_another_users_interviews(
        self, client, db_session, make_user, auth_headers
    ):
        owner = make_user()
        other_user = make_user()
        application = _make_application(db_session, owner)
        _make_interview(db_session, application)

        response = client.get(
            _interviews_url(application.id), headers=auth_headers(other_user)
        )
        assert response.status_code == 404


class TestInterviewApplicationScoping:
    """A same user owning two applications must not be able to reach one
    application's interview through the *other* application's URL - the
    path's application_id has to match the interview's actual parent,
    not just pass an ownership check."""

    def test_cannot_get_interview_via_sibling_application(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application_a = _make_application(db_session, user, company="Initech")
        application_b = _make_application(db_session, user, company="Globex")
        interview = _make_interview(db_session, application_a)

        response = client.get(
            f"{_interviews_url(application_b.id)}/{interview.id}",
            headers=auth_headers(user),
        )
        assert response.status_code == 404

    def test_cannot_update_interview_via_sibling_application(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application_a = _make_application(db_session, user, company="Initech")
        application_b = _make_application(db_session, user, company="Globex")
        interview = _make_interview(db_session, application_a, feedback="Original")

        response = client.patch(
            f"{_interviews_url(application_b.id)}/{interview.id}",
            json={"feedback": "Wrong parent"},
            headers=auth_headers(user),
        )
        assert response.status_code == 404

        db_session.refresh(interview)
        assert interview.feedback == "Original"

    def test_cannot_delete_interview_via_sibling_application(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application_a = _make_application(db_session, user, company="Initech")
        application_b = _make_application(db_session, user, company="Globex")
        interview = _make_interview(db_session, application_a)

        response = client.delete(
            f"{_interviews_url(application_b.id)}/{interview.id}",
            headers=auth_headers(user),
        )
        assert response.status_code == 404

        still_there = (
            db_session.query(Interview).filter(Interview.id == interview.id).first()
        )
        assert still_there is not None

    def test_listing_one_application_does_not_include_siblings_interviews(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application_a = _make_application(db_session, user, company="Initech")
        application_b = _make_application(db_session, user, company="Globex")
        interview_a = _make_interview(db_session, application_a)
        _make_interview(db_session, application_b)

        response = client.get(
            _interviews_url(application_a.id), headers=auth_headers(user)
        )

        body = response.json()
        assert body["total"] == 1
        assert body["items"][0]["id"] == str(interview_a.id)


class TestUpdateInterview:
    def test_updates_only_provided_fields(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)
        interview = _make_interview(
            db_session, application, type=InterviewType.PHONE_SCREEN, feedback=None
        )

        response = client.patch(
            f"{_interviews_url(application.id)}/{interview.id}",
            json={"feedback": "Went well"},
            headers=auth_headers(user),
        )

        assert response.status_code == 200
        body = response.json()
        assert body["feedback"] == "Went well"
        assert body["type"] == "phone_screen"

    def test_invalid_type_is_rejected(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)
        interview = _make_interview(db_session, application)

        response = client.patch(
            f"{_interviews_url(application.id)}/{interview.id}",
            json={"type": "not-a-real-type"},
            headers=auth_headers(user),
        )
        assert response.status_code == 422

    def test_invalid_duration_is_rejected(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)
        interview = _make_interview(db_session, application)

        response = client.patch(
            f"{_interviews_url(application.id)}/{interview.id}",
            json={"duration_minutes": 1441},
            headers=auth_headers(user),
        )
        assert response.status_code == 422

    def test_updates_result(self, client, db_session, make_user, auth_headers):
        user = make_user()
        application = _make_application(db_session, user)
        interview = _make_interview(
            db_session, application, result=InterviewResult.PENDING
        )

        response = client.patch(
            f"{_interviews_url(application.id)}/{interview.id}",
            json={"result": "passed"},
            headers=auth_headers(user),
        )

        assert response.status_code == 200
        assert response.json()["result"] == "passed"

    def test_updating_nonexistent_interview_is_404(
        self, client, db_session, make_user, auth_headers
    ):
        import uuid

        user = make_user()
        application = _make_application(db_session, user)

        response = client.patch(
            f"{_interviews_url(application.id)}/{uuid.uuid4()}",
            json={"feedback": "Doesn't matter"},
            headers=auth_headers(user),
        )
        assert response.status_code == 404


class TestDeleteInterview:
    def test_deletes_owned_interview(self, client, db_session, make_user, auth_headers):
        user = make_user()
        application = _make_application(db_session, user)
        interview = _make_interview(db_session, application)

        response = client.delete(
            f"{_interviews_url(application.id)}/{interview.id}",
            headers=auth_headers(user),
        )
        assert response.status_code == 204

        get_response = client.get(
            f"{_interviews_url(application.id)}/{interview.id}",
            headers=auth_headers(user),
        )
        assert get_response.status_code == 404

    def test_deleting_nonexistent_interview_is_404(
        self, client, db_session, make_user, auth_headers
    ):
        import uuid

        user = make_user()
        application = _make_application(db_session, user)

        response = client.delete(
            f"{_interviews_url(application.id)}/{uuid.uuid4()}",
            headers=auth_headers(user),
        )
        assert response.status_code == 404


class TestListInterviewsOrdering:
    def test_returns_interviews_ordered_by_scheduled_at_ascending(
        self, client, db_session, make_user, auth_headers
    ):
        """scheduled_at is client-supplied (not a server timestamp), so
        unlike created_at/updated_at elsewhere in this suite, explicit
        values here are just normal test data - no transaction-timing
        caveat applies."""
        user = make_user()
        application = _make_application(db_session, user)

        later = _make_interview(
            db_session, application, scheduled_at=BASE_SCHEDULED_AT + timedelta(days=5)
        )
        earlier = _make_interview(
            db_session, application, scheduled_at=BASE_SCHEDULED_AT
        )
        middle = _make_interview(
            db_session, application, scheduled_at=BASE_SCHEDULED_AT + timedelta(days=2)
        )

        response = client.get(
            _interviews_url(application.id), headers=auth_headers(user)
        )

        ids_in_order = [item["id"] for item in response.json()["items"]]
        assert ids_in_order == [str(earlier.id), str(middle.id), str(later.id)]

    def test_empty_application_returns_empty_list(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)

        response = client.get(
            _interviews_url(application.id), headers=auth_headers(user)
        )

        assert response.status_code == 200
        body = response.json()
        assert body["items"] == []
        assert body["total"] == 0
        assert body["page"] == 1
        assert body["page_size"] == 20


class TestListInterviewsPagination:
    def test_paginates_results(self, client, db_session, make_user, auth_headers):
        user = make_user()
        application = _make_application(db_session, user)
        for i in range(5):
            _make_interview(
                db_session,
                application,
                scheduled_at=BASE_SCHEDULED_AT + timedelta(days=i),
            )

        page_1 = client.get(
            _interviews_url(application.id),
            params={"page": 1, "page_size": 2},
            headers=auth_headers(user),
        )
        page_2 = client.get(
            _interviews_url(application.id),
            params={"page": 2, "page_size": 2},
            headers=auth_headers(user),
        )

        assert page_1.status_code == 200
        assert page_2.status_code == 200
        assert page_1.json()["total"] == 5
        assert page_2.json()["total"] == 5
        assert len(page_1.json()["items"]) == 2
        assert len(page_2.json()["items"]) == 2

        page_1_ids = {item["id"] for item in page_1.json()["items"]}
        page_2_ids = {item["id"] for item in page_2.json()["items"]}
        assert page_1_ids.isdisjoint(page_2_ids)

    def test_pagination_preserves_scheduled_at_ordering(
        self, client, db_session, make_user, auth_headers
    ):
        """Pagination and ordering are independent concerns - offset/
        limit must apply on top of the ORDER BY, not instead of it."""
        user = make_user()
        application = _make_application(db_session, user)
        interviews = [
            _make_interview(
                db_session,
                application,
                scheduled_at=BASE_SCHEDULED_AT + timedelta(days=i),
            )
            for i in range(4)
        ]

        page_2 = client.get(
            _interviews_url(application.id),
            params={"page": 2, "page_size": 2},
            headers=auth_headers(user),
        )

        ids_in_order = [item["id"] for item in page_2.json()["items"]]
        assert ids_in_order == [str(interviews[2].id), str(interviews[3].id)]

    def test_page_size_is_capped_at_100(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)

        response = client.get(
            _interviews_url(application.id),
            params={"page_size": 500},
            headers=auth_headers(user),
        )
        assert response.status_code == 422

    def test_page_below_one_is_rejected(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)

        response = client.get(
            _interviews_url(application.id),
            params={"page": 0},
            headers=auth_headers(user),
        )
        assert response.status_code == 422


class TestInterviewResultServerDefault:
    """Isolated, clearly-flagged test of the concern in this file's
    module docstring: Interview.result is declared with
    server_default=InterviewResult.PENDING - the raw enum member, not
    .value. This inserts a row via the ORM without setting `result` at
    all, bypassing every code path (including this file's own
    _make_interview helper) that would otherwise supply it explicitly,
    to see what the database itself actually does.

    If this test errors (rather than fails an assertion), that's a
    stronger signal than a normal test failure: it likely means
    server_default couldn't compile into valid DDL at all, which would
    also break Base.metadata.create_all() for the whole suite's
    session-scoped `engine` fixture - not just this test. If that
    happens, changing the model to server_default=InterviewResult.PENDING.value
    is the likely fix, but that's a model change outside this test
    file's scope.
    """

    def test_result_falls_back_to_database_default_when_omitted(
        self, client, db_session, make_user
    ):
        user = make_user()
        application = _make_application(db_session, user)

        interview = Interview(
            application_id=application.id,
            type=InterviewType.TECHNICAL,
            scheduled_at=BASE_SCHEDULED_AT,
            # result deliberately omitted
        )
        db_session.add(interview)
        db_session.commit()
        db_session.refresh(interview)

        assert interview.result == InterviewResult.PENDING
