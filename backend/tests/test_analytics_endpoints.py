"""
Integration tests for GET /analytics/summary, /funnel, /activity,
/interviews (app/api/v1/endpoints/analytics.py).

Seeds data directly via the ORM (db_session) rather than through the
API's create endpoints - faster to set up a specific status/result
distribution, and analytics doesn't read application_status_history,
so bypassing the create/update endpoints' write-hook here doesn't skip
anything these tests care about.
"""

from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.models.application import Application, ApplicationStatus
from app.models.interview import Interview, InterviewResult, InterviewType
from app.models.user import User


def _make_application(
    db_session: Session, user: User, status: ApplicationStatus, **overrides
) -> Application:
    application = Application(
        user_id=user.id,
        company=overrides.pop("company", "Acme"),
        position=overrides.pop("position", "Engineer"),
        status=status,
        **overrides,
    )
    db_session.add(application)
    db_session.commit()
    db_session.refresh(application)
    return application


def _make_interview(
    db_session: Session,
    application: Application,
    result: InterviewResult,
    **overrides,
) -> Interview:
    interview = Interview(
        application_id=application.id,
        type=overrides.pop("type", InterviewType.TECHNICAL),
        scheduled_at=overrides.pop(
            "scheduled_at", datetime.now(timezone.utc) + timedelta(days=1)
        ),
        result=result,
        **overrides,
    )
    db_session.add(interview)
    db_session.commit()
    db_session.refresh(interview)
    return interview


class TestSummary:
    def test_counts_and_response_rate(
        self, client: TestClient, db_session: Session, make_user, auth_headers
    ):
        user: User = make_user()
        headers = auth_headers(user)

        _make_application(db_session, user, ApplicationStatus.SAVED)
        _make_application(db_session, user, ApplicationStatus.APPLIED)
        _make_application(db_session, user, ApplicationStatus.INTERVIEWING)
        _make_application(db_session, user, ApplicationStatus.OFFER)
        _make_application(db_session, user, ApplicationStatus.ACCEPTED)
        _make_application(db_session, user, ApplicationStatus.REJECTED)

        resp = client.get("/api/v1/analytics/summary", headers=headers)
        assert resp.status_code == 200, resp.text
        body = resp.json()

        assert body["total_applications"] == 6
        # active = everything except rejected/withdrawn
        assert body["active_applications"] == 5
        # offers_received = OFFER + ACCEPTED
        assert body["offers_received"] == 2
        # submitted (status != saved) = 5; responded (not in {saved, applied}) = 4
        assert body["response_rate"] == 4 / 5

    def test_no_applications_gives_null_response_rate(
        self, client: TestClient, make_user, auth_headers
    ):
        user: User = make_user()
        resp = client.get("/api/v1/analytics/summary", headers=auth_headers(user))
        assert resp.status_code == 200
        body = resp.json()
        assert body["total_applications"] == 0
        assert body["response_rate"] is None

    def test_interviews_scheduled_counts_only_pending(
        self, client: TestClient, db_session: Session, make_user, auth_headers
    ):
        user: User = make_user()
        headers = auth_headers(user)
        application = _make_application(
            db_session, user, ApplicationStatus.INTERVIEWING
        )
        _make_interview(db_session, application, InterviewResult.PENDING)
        _make_interview(db_session, application, InterviewResult.PASSED)
        _make_interview(db_session, application, InterviewResult.PENDING)

        resp = client.get("/api/v1/analytics/summary", headers=headers)
        assert resp.json()["interviews_scheduled"] == 2

    def test_scoped_to_current_user_only(
        self, client: TestClient, db_session: Session, make_user, auth_headers
    ):
        owner: User = make_user()
        other: User = make_user()
        _make_application(db_session, owner, ApplicationStatus.APPLIED)

        resp = client.get("/api/v1/analytics/summary", headers=auth_headers(other))
        assert resp.json()["total_applications"] == 0


class TestFunnel:
    def test_stages_and_off_ramps(
        self, client: TestClient, db_session: Session, make_user, auth_headers
    ):
        user: User = make_user()
        headers = auth_headers(user)
        _make_application(db_session, user, ApplicationStatus.SAVED)
        _make_application(db_session, user, ApplicationStatus.SAVED)
        _make_application(db_session, user, ApplicationStatus.APPLIED)
        _make_application(db_session, user, ApplicationStatus.REJECTED)
        _make_application(db_session, user, ApplicationStatus.WITHDRAWN)

        resp = client.get("/api/v1/analytics/funnel", headers=headers)
        assert resp.status_code == 200, resp.text
        body = resp.json()

        assert body["total_applications"] == 5
        stage_counts = {s["status"]: s["count"] for s in body["stages"]}
        assert stage_counts["saved"] == 2
        assert stage_counts["applied"] == 1
        assert stage_counts["phone_screen"] == 0
        off_ramp_counts = {s["status"]: s["count"] for s in body["off_ramps"]}
        assert off_ramp_counts["rejected"] == 1
        assert off_ramp_counts["withdrawn"] == 1

    def test_stage_order_is_stable_regardless_of_insertion_order(
        self, client: TestClient, db_session: Session, make_user, auth_headers
    ):
        user: User = make_user()
        headers = auth_headers(user)
        _make_application(db_session, user, ApplicationStatus.OFFER)
        _make_application(db_session, user, ApplicationStatus.SAVED)

        resp = client.get("/api/v1/analytics/funnel", headers=headers)
        statuses_in_order = [s["status"] for s in resp.json()["stages"]]
        assert statuses_in_order == [
            "saved",
            "applied",
            "phone_screen",
            "interviewing",
            "offer",
            "accepted",
        ]


class TestActivity:
    def test_buckets_by_month_with_zero_fill(
        self, client: TestClient, db_session: Session, make_user, auth_headers
    ):
        user: User = make_user()
        headers = auth_headers(user)

        now = datetime.now(timezone.utc)
        this_month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        two_months_ago = this_month_start - timedelta(days=45)  # earlier month

        app_this_month = _make_application(db_session, user, ApplicationStatus.SAVED)
        app_this_month.created_at = this_month_start + timedelta(days=1)
        app_earlier = _make_application(db_session, user, ApplicationStatus.SAVED)
        app_earlier.created_at = two_months_ago
        db_session.add_all([app_this_month, app_earlier])
        db_session.commit()

        resp = client.get(
            "/api/v1/analytics/activity", params={"months": 3}, headers=headers
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert len(body["buckets"]) == 3
        periods = [b["period"] for b in body["buckets"]]
        assert periods == sorted(periods)  # chronological, oldest first
        counts_by_period = {
            b["period"]: b["applications_created"] for b in body["buckets"]
        }
        assert counts_by_period[this_month_start.strftime("%Y-%m")] == 1

    def test_months_param_is_bounded(self, client: TestClient, make_user, auth_headers):
        user: User = make_user()
        resp = client.get(
            "/api/v1/analytics/activity",
            params={"months": 0},
            headers=auth_headers(user),
        )
        assert resp.status_code == 422

        resp = client.get(
            "/api/v1/analytics/activity",
            params={"months": 25},
            headers=auth_headers(user),
        )
        assert resp.status_code == 422


class TestInterviewAnalytics:
    def test_counts_and_pass_rate(
        self, client: TestClient, db_session: Session, make_user, auth_headers
    ):
        user: User = make_user()
        headers = auth_headers(user)
        application = _make_application(
            db_session, user, ApplicationStatus.INTERVIEWING
        )
        _make_interview(db_session, application, InterviewResult.PASSED)
        _make_interview(db_session, application, InterviewResult.PASSED)
        _make_interview(db_session, application, InterviewResult.FAILED)
        _make_interview(db_session, application, InterviewResult.PENDING)
        _make_interview(db_session, application, InterviewResult.CANCELLED)

        resp = client.get("/api/v1/analytics/interviews", headers=headers)
        assert resp.status_code == 200, resp.text
        body = resp.json()

        assert body["total_interviews"] == 5
        assert body["by_result"] == {
            "pending": 1,
            "passed": 2,
            "failed": 1,
            "cancelled": 1,
        }
        assert body["pass_rate"] == 2 / 3

    def test_no_decided_interviews_gives_null_pass_rate(
        self, client: TestClient, db_session: Session, make_user, auth_headers
    ):
        user: User = make_user()
        headers = auth_headers(user)
        application = _make_application(
            db_session, user, ApplicationStatus.INTERVIEWING
        )
        _make_interview(db_session, application, InterviewResult.PENDING)

        resp = client.get("/api/v1/analytics/interviews", headers=headers)
        assert resp.json()["pass_rate"] is None

    def test_scoped_through_application_ownership(
        self, client: TestClient, db_session: Session, make_user, auth_headers
    ):
        owner: User = make_user()
        other: User = make_user()
        application = _make_application(
            db_session, owner, ApplicationStatus.INTERVIEWING
        )
        _make_interview(db_session, application, InterviewResult.PASSED)

        resp = client.get("/api/v1/analytics/interviews", headers=auth_headers(other))
        assert resp.json()["total_interviews"] == 0
