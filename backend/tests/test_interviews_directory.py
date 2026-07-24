"""
Integration tests for GET /interviews
(app/api/v1/endpoints/interviews.py :: directory_router).

Mirrors test_contacts_directory.py's shape and reasoning: this route is
deliberately not nested under /applications/{id} - it's a flat,
cross-application listing scoped only by Application.user_id via a join.
That means there's no application_id in the URL to accidentally scope
by, which makes the ownership/IDOR check the single most important thing
this file verifies.

Where this diverges from the Contacts directory tests: Interview has no
name-like text field, so there's no `search` param here - the equivalent
filter is `result` (pending/passed/failed/cancelled), and ordering is
`scheduled_at` ascending (matching the nested GET /applications/{id}/interviews
route) rather than `created_at` descending.
"""

from datetime import datetime, timedelta, timezone

from app.models.application import Application, ApplicationStatus
from app.models.interview import Interview, InterviewResult, InterviewType

INTERVIEWS_URL = "/api/v1/interviews"


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
    defaults = {
        "application_id": application.id,
        "type": InterviewType.PHONE_SCREEN,
        "scheduled_at": datetime.now(timezone.utc) + timedelta(days=1),
    }
    defaults.update(overrides)
    interview = Interview(**defaults)
    db_session.add(interview)
    db_session.commit()
    db_session.refresh(interview)
    return interview


class TestInterviewsDirectoryAuth:
    def test_requires_authentication(self, client):
        response = client.get(INTERVIEWS_URL)
        assert response.status_code == 401

    def test_rejects_invalid_token(self, client):
        response = client.get(
            INTERVIEWS_URL, headers={"Authorization": "Bearer not-a-real-token"}
        )
        assert response.status_code == 401

    def test_rejects_refresh_token_used_as_access_token(self, client, make_user):
        """get_current_user checks payload["type"] == "access" - a
        refresh token (same signing key, different `type` claim) must
        not work here, or a leaked refresh token would grant API access
        directly instead of only /auth/refresh."""
        from app.core.security import create_refresh_token

        user = make_user()
        token = create_refresh_token(subject=str(user.id))
        response = client.get(
            INTERVIEWS_URL, headers={"Authorization": f"Bearer {token}"}
        )
        assert response.status_code == 401


class TestInterviewsDirectoryAggregation:
    def test_aggregates_interviews_across_applications(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        app_a = _make_application(db_session, user, company="Initech")
        app_b = _make_application(db_session, user, company="Globex")
        _make_interview(db_session, app_a, type=InterviewType.PHONE_SCREEN)
        _make_interview(db_session, app_b, type=InterviewType.ONSITE)

        response = client.get(INTERVIEWS_URL, headers=auth_headers(user))

        assert response.status_code == 200
        body = response.json()
        assert body["total"] == 2
        types = {item["type"] for item in body["items"]}
        assert types == {"phone_screen", "onsite"}
        companies = {item["application"]["company"] for item in body["items"]}
        assert companies == {"Initech", "Globex"}

    def test_embeds_correct_parent_application_per_interview(
        self, client, db_session, make_user, auth_headers
    ):
        """Guards the contains_eager() join specifically: each interview
        must be paired with its own application, not e.g. the last
        application row seen during the join."""
        user = make_user()
        app_a = _make_application(db_session, user, company="Initech")
        app_b = _make_application(db_session, user, company="Globex")
        interview_a = _make_interview(db_session, app_a)
        interview_b = _make_interview(db_session, app_b)

        response = client.get(INTERVIEWS_URL, headers=auth_headers(user))

        by_id = {item["id"]: item for item in response.json()["items"]}
        assert by_id[str(interview_a.id)]["application"]["company"] == "Initech"
        assert by_id[str(interview_b.id)]["application"]["company"] == "Globex"

    def test_empty_when_user_has_no_interviews(self, client, make_user, auth_headers):
        user = make_user()
        response = client.get(INTERVIEWS_URL, headers=auth_headers(user))
        assert response.status_code == 200
        body = response.json()
        assert body["items"] == []
        assert body["total"] == 0

    def test_ordered_by_scheduled_at_ascending(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)
        now = datetime.now(timezone.utc)
        later = _make_interview(
            db_session, application, scheduled_at=now + timedelta(days=5)
        )
        sooner = _make_interview(
            db_session, application, scheduled_at=now + timedelta(days=1)
        )

        response = client.get(INTERVIEWS_URL, headers=auth_headers(user))

        ids_in_order = [item["id"] for item in response.json()["items"]]
        assert ids_in_order == [str(sooner.id), str(later.id)]


class TestInterviewsDirectoryOwnership:
    def test_user_cannot_see_another_users_interviews(
        self, client, db_session, make_user, auth_headers
    ):
        """The critical IDOR check flagged for the Contacts directory
        applies identically here: this route has no application_id path
        param, so the Application.user_id join/filter is the *only*
        thing standing between one user and every other user's
        interviews."""
        owner = make_user()
        other_user = make_user()

        owner_app = _make_application(db_session, owner, company="Initech")
        _make_interview(db_session, owner_app)

        other_app = _make_application(db_session, other_user, company="Umbrella Corp")
        other_interview = _make_interview(db_session, other_app)

        response = client.get(INTERVIEWS_URL, headers=auth_headers(other_user))

        assert response.status_code == 200
        body = response.json()
        assert body["total"] == 1
        assert body["items"][0]["id"] == str(other_interview.id)

    def test_result_filter_cannot_be_used_to_find_another_users_interviews(
        self, client, db_session, make_user, auth_headers
    ):
        owner = make_user()
        other_user = make_user()

        owner_app = _make_application(db_session, owner, company="Initech")
        _make_interview(db_session, owner_app, result=InterviewResult.PASSED)

        other_app = _make_application(db_session, other_user, company="Globex")
        _make_interview(db_session, other_app, result=InterviewResult.PENDING)

        response = client.get(
            INTERVIEWS_URL,
            params={"result": "passed"},
            headers=auth_headers(other_user),
        )

        assert response.status_code == 200
        body = response.json()
        assert body["total"] == 0
        assert body["items"] == []


class TestInterviewsDirectoryResultFilter:
    def test_filters_by_result(self, client, db_session, make_user, auth_headers):
        user = make_user()
        application = _make_application(db_session, user)
        _make_interview(db_session, application, result=InterviewResult.PASSED)
        _make_interview(db_session, application, result=InterviewResult.PENDING)

        response = client.get(
            INTERVIEWS_URL, params={"result": "passed"}, headers=auth_headers(user)
        )

        assert response.status_code == 200
        body = response.json()
        assert body["total"] == 1
        assert body["items"][0]["result"] == "passed"

    def test_invalid_result_value_is_rejected(self, client, make_user, auth_headers):
        user = make_user()
        response = client.get(
            INTERVIEWS_URL,
            params={"result": "not-a-real-result"},
            headers=auth_headers(user),
        )
        assert response.status_code == 422

    def test_no_filter_returns_all_results(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)
        _make_interview(db_session, application, result=InterviewResult.PASSED)
        _make_interview(db_session, application, result=InterviewResult.PENDING)

        response = client.get(INTERVIEWS_URL, headers=auth_headers(user))

        assert response.status_code == 200
        assert response.json()["total"] == 2


class TestInterviewsDirectoryPagination:
    def test_paginates_results(self, client, db_session, make_user, auth_headers):
        user = make_user()
        application = _make_application(db_session, user)
        now = datetime.now(timezone.utc)
        for i in range(5):
            _make_interview(
                db_session, application, scheduled_at=now + timedelta(days=i)
            )

        page_1 = client.get(
            INTERVIEWS_URL,
            params={"page": 1, "page_size": 2},
            headers=auth_headers(user),
        )
        page_2 = client.get(
            INTERVIEWS_URL,
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

    def test_page_size_is_capped_at_100(self, client, make_user, auth_headers):
        user = make_user()
        response = client.get(
            INTERVIEWS_URL, params={"page_size": 500}, headers=auth_headers(user)
        )
        assert response.status_code == 422

    def test_page_below_one_is_rejected(self, client, make_user, auth_headers):
        user = make_user()
        response = client.get(
            INTERVIEWS_URL, params={"page": 0}, headers=auth_headers(user)
        )
        assert response.status_code == 422
