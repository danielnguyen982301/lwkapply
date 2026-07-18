"""
Integration tests for /applications
(app/api/v1/endpoints/applications.py).

Uses the same fixtures as test_contacts_directory.py (client, db_session,
make_user, auth_headers - see conftest.py) - no new fixture
infrastructure needed here, just endpoint-specific setup helpers.

A note on timestamps: TimestampMixin uses server_default=func.now(),
and Postgres's now() returns the *transaction's* start time, not a
per-statement clock. Because conftest.py's SAVEPOINT-based isolation
runs an entire test inside one real outer transaction, rows created in
the same test can end up with identical created_at/updated_at values -
unlike production, where each request is its own real transaction.
Tests that care about the ORDER BY updated_at DESC behavior therefore
set explicit timestamps rather than relying on wall-clock deltas between
inserts.
"""

from datetime import datetime, timedelta, timezone

from app.models.application import Application, ApplicationStatus

APPLICATIONS_URL = "/api/v1/applications"


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


class TestApplicationsAuth:
    def test_list_requires_authentication(self, client):
        response = client.get(APPLICATIONS_URL)
        assert response.status_code == 401

    def test_create_requires_authentication(self, client):
        response = client.post(
            APPLICATIONS_URL, json={"company": "Initech", "position": "Engineer"}
        )
        assert response.status_code == 401

    def test_rejects_invalid_token(self, client):
        response = client.get(
            APPLICATIONS_URL, headers={"Authorization": "Bearer not-a-real-token"}
        )
        assert response.status_code == 401


class TestCreateApplication:
    def test_creates_application_for_current_user(
        self, client, make_user, auth_headers
    ):
        user = make_user()
        response = client.post(
            APPLICATIONS_URL,
            json={"company": "Initech", "position": "Backend Engineer"},
            headers=auth_headers(user),
        )

        assert response.status_code == 201
        body = response.json()
        assert body["company"] == "Initech"
        assert body["position"] == "Backend Engineer"
        assert body["status"] == "saved"
        assert body["user_id"] == str(user.id)
        assert "id" in body

    def test_missing_company_is_rejected(self, client, make_user, auth_headers):
        user = make_user()
        response = client.post(
            APPLICATIONS_URL,
            json={"position": "Backend Engineer"},
            headers=auth_headers(user),
        )
        assert response.status_code == 422

    def test_invalid_status_is_rejected(self, client, make_user, auth_headers):
        user = make_user()
        response = client.post(
            APPLICATIONS_URL,
            json={
                "company": "Initech",
                "position": "Backend Engineer",
                "status": "not-a-real-status",
            },
            headers=auth_headers(user),
        )
        assert response.status_code == 422

    def test_salary_min_greater_than_max_is_rejected(
        self, client, make_user, auth_headers
    ):
        user = make_user()
        response = client.post(
            APPLICATIONS_URL,
            json={
                "company": "Initech",
                "position": "Backend Engineer",
                "salary_min": 150_000,
                "salary_max": 100_000,
            },
            headers=auth_headers(user),
        )
        assert response.status_code == 422

    def test_spoofed_user_id_in_payload_is_ignored(
        self, client, db_session, make_user, auth_headers
    ):
        """ApplicationCreate has no user_id field, so pydantic's default
        extra='ignore' behavior drops it - ownership is always taken
        from the authenticated user, never from the request body. This
        is the create-side half of the IDOR protections tested more
        directly in TestApplicationOwnership below."""
        user = make_user()
        other_user = make_user()

        response = client.post(
            APPLICATIONS_URL,
            json={
                "company": "Initech",
                "position": "Backend Engineer",
                "user_id": str(other_user.id),
            },
            headers=auth_headers(user),
        )

        assert response.status_code == 201
        assert response.json()["user_id"] == str(user.id)

    def test_created_application_appears_in_owners_list(
        self, client, make_user, auth_headers
    ):
        user = make_user()
        create_response = client.post(
            APPLICATIONS_URL,
            json={"company": "Initech", "position": "Backend Engineer"},
            headers=auth_headers(user),
        )
        application_id = create_response.json()["id"]

        list_response = client.get(APPLICATIONS_URL, headers=auth_headers(user))

        ids = {item["id"] for item in list_response.json()["items"]}
        assert application_id in ids


class TestGetApplication:
    def test_returns_owned_application(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user, company="Initech")

        response = client.get(
            f"{APPLICATIONS_URL}/{application.id}", headers=auth_headers(user)
        )

        assert response.status_code == 200
        assert response.json()["company"] == "Initech"

    def test_nonexistent_application_is_404(self, client, make_user, auth_headers):
        import uuid

        user = make_user()
        response = client.get(
            f"{APPLICATIONS_URL}/{uuid.uuid4()}", headers=auth_headers(user)
        )
        assert response.status_code == 404

    def test_malformed_id_is_422(self, client, make_user, auth_headers):
        user = make_user()
        response = client.get(
            f"{APPLICATIONS_URL}/not-a-uuid", headers=auth_headers(user)
        )
        assert response.status_code == 422


class TestApplicationOwnership:
    """The core IDOR surface for this endpoint: get/update/delete all
    resolve through _get_owned_application, which filters by
    Application.user_id == current_user.id. Every mutating and
    read path needs its own check here - passing on GET doesn't
    guarantee PATCH/DELETE are scoped the same way."""

    def test_cannot_get_another_users_application(
        self, client, db_session, make_user, auth_headers
    ):
        owner = make_user()
        other_user = make_user()
        application = _make_application(db_session, owner, company="Initech")

        response = client.get(
            f"{APPLICATIONS_URL}/{application.id}", headers=auth_headers(other_user)
        )
        assert response.status_code == 404

    def test_cannot_update_another_users_application(
        self, client, db_session, make_user, auth_headers
    ):
        owner = make_user()
        other_user = make_user()
        application = _make_application(db_session, owner, company="Initech")

        response = client.patch(
            f"{APPLICATIONS_URL}/{application.id}",
            json={"company": "Hijacked Corp"},
            headers=auth_headers(other_user),
        )
        assert response.status_code == 404

        db_session.refresh(application)
        assert application.company == "Initech"

    def test_cannot_delete_another_users_application(
        self, client, db_session, make_user, auth_headers
    ):
        owner = make_user()
        other_user = make_user()
        application = _make_application(db_session, owner, company="Initech")

        response = client.delete(
            f"{APPLICATIONS_URL}/{application.id}", headers=auth_headers(other_user)
        )
        assert response.status_code == 404

        still_there = (
            db_session.query(Application)
            .filter(Application.id == application.id)
            .first()
        )
        assert still_there is not None

    def test_list_only_returns_current_users_applications(
        self, client, db_session, make_user, auth_headers
    ):
        owner = make_user()
        other_user = make_user()
        _make_application(db_session, owner, company="Initech")
        _make_application(db_session, other_user, company="Globex")

        response = client.get(APPLICATIONS_URL, headers=auth_headers(owner))

        companies = {item["company"] for item in response.json()["items"]}
        assert companies == {"Initech"}

    def test_search_cannot_surface_another_users_applications(
        self, client, db_session, make_user, auth_headers
    ):
        owner = make_user()
        other_user = make_user()
        _make_application(db_session, other_user, company="Zzz Unique Target Corp")

        response = client.get(
            APPLICATIONS_URL,
            params={"search": "Zzz Unique Target Corp"},
            headers=auth_headers(owner),
        )

        assert response.json()["total"] == 0


class TestUpdateApplication:
    def test_updates_only_provided_fields(
        self, client, db_session, make_user, auth_headers
    ):
        """ApplicationUpdate is applied via model_dump(exclude_unset=True)
        - fields not included in the request body must be left alone,
        not reset to their schema defaults."""
        user = make_user()
        application = _make_application(
            db_session,
            user,
            company="Initech",
            position="Backend Engineer",
            status=ApplicationStatus.SAVED,
        )

        response = client.patch(
            f"{APPLICATIONS_URL}/{application.id}",
            json={"status": "applied"},
            headers=auth_headers(user),
        )

        assert response.status_code == 200
        body = response.json()
        assert body["status"] == "applied"
        assert body["company"] == "Initech"
        assert body["position"] == "Backend Engineer"

    def test_invalid_status_is_rejected(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)

        response = client.patch(
            f"{APPLICATIONS_URL}/{application.id}",
            json={"status": "not-a-real-status"},
            headers=auth_headers(user),
        )
        assert response.status_code == 422

    def test_salary_min_greater_than_max_is_rejected(
        self, client, db_session, make_user, auth_headers
    ):
        """Both fields inverted in a single PATCH - caught by
        ApplicationUpdate's own schema validator before the endpoint
        code runs at all (a 422 from request parsing, not from the
        endpoint-level check below)."""
        user = make_user()
        application = _make_application(db_session, user)

        response = client.patch(
            f"{APPLICATIONS_URL}/{application.id}",
            json={"salary_min": 150_000, "salary_max": 100_000},
            headers=auth_headers(user),
        )

        assert response.status_code == 422
        db_session.refresh(application)
        assert application.salary_min is None
        assert application.salary_max is None

    def test_salary_min_conflicting_with_existing_max_is_rejected(
        self, client, db_session, make_user, auth_headers
    ):
        """A PATCH that only sets salary_min - the schema validator alone
        can't see this is invalid, since salary_max never appears in the
        request body. This is what the endpoint-level check (comparing
        against the stored row) exists for."""
        user = make_user()
        application = _make_application(db_session, user, salary_max=100_000)

        response = client.patch(
            f"{APPLICATIONS_URL}/{application.id}",
            json={"salary_min": 150_000},
            headers=auth_headers(user),
        )

        assert response.status_code == 422
        assert (
            "salary_min cannot be greater than salary_max" in response.json()["detail"]
        )

        db_session.refresh(application)
        assert application.salary_min is None
        assert application.salary_max == 100_000

    def test_salary_max_conflicting_with_existing_min_is_rejected(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user, salary_min=100_000)

        response = client.patch(
            f"{APPLICATIONS_URL}/{application.id}",
            json={"salary_max": 50_000},
            headers=auth_headers(user),
        )

        assert response.status_code == 422

        db_session.refresh(application)
        assert application.salary_min == 100_000
        assert application.salary_max is None

    def test_partial_salary_update_consistent_with_existing_is_accepted(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user, salary_min=80_000)

        response = client.patch(
            f"{APPLICATIONS_URL}/{application.id}",
            json={"salary_max": 120_000},
            headers=auth_headers(user),
        )

        assert response.status_code == 200
        body = response.json()
        assert body["salary_min"] == 80_000
        assert body["salary_max"] == 120_000

    def test_unrelated_field_update_is_unaffected_by_salary_check(
        self, client, db_session, make_user, auth_headers
    ):
        """A PATCH that never touches salary fields must not trip the
        merged-values check just because the stored row happens to have
        a valid (or even absent) salary range."""
        user = make_user()
        application = _make_application(
            db_session, user, salary_min=80_000, salary_max=120_000
        )

        response = client.patch(
            f"{APPLICATIONS_URL}/{application.id}",
            json={"notes": "Following up next week"},
            headers=auth_headers(user),
        )

        assert response.status_code == 200
        assert response.json()["notes"] == "Following up next week"

    def test_valid_salary_range_update_is_accepted(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)

        response = client.patch(
            f"{APPLICATIONS_URL}/{application.id}",
            json={"salary_min": 80_000, "salary_max": 120_000},
            headers=auth_headers(user),
        )

        assert response.status_code == 200
        body = response.json()
        assert body["salary_min"] == 80_000
        assert body["salary_max"] == 120_000

    def test_updating_nonexistent_application_is_404(
        self, client, make_user, auth_headers
    ):
        import uuid

        user = make_user()
        response = client.patch(
            f"{APPLICATIONS_URL}/{uuid.uuid4()}",
            json={"status": "applied"},
            headers=auth_headers(user),
        )
        assert response.status_code == 404


class TestDeleteApplication:
    def test_deletes_owned_application(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)

        response = client.delete(
            f"{APPLICATIONS_URL}/{application.id}", headers=auth_headers(user)
        )
        assert response.status_code == 204

        get_response = client.get(
            f"{APPLICATIONS_URL}/{application.id}", headers=auth_headers(user)
        )
        assert get_response.status_code == 404

    def test_deleting_nonexistent_application_is_404(
        self, client, make_user, auth_headers
    ):
        import uuid

        user = make_user()
        response = client.delete(
            f"{APPLICATIONS_URL}/{uuid.uuid4()}", headers=auth_headers(user)
        )
        assert response.status_code == 404


class TestListApplicationsFilter:
    def test_filters_by_status(self, client, db_session, make_user, auth_headers):
        user = make_user()
        _make_application(
            db_session, user, company="Initech", status=ApplicationStatus.SAVED
        )
        _make_application(
            db_session, user, company="Globex", status=ApplicationStatus.APPLIED
        )

        response = client.get(
            APPLICATIONS_URL, params={"status": "applied"}, headers=auth_headers(user)
        )

        body = response.json()
        assert body["total"] == 1
        assert body["items"][0]["company"] == "Globex"

    def test_invalid_status_filter_is_rejected(self, client, make_user, auth_headers):
        user = make_user()
        response = client.get(
            APPLICATIONS_URL,
            params={"status": "not-a-real-status"},
            headers=auth_headers(user),
        )
        assert response.status_code == 422


class TestListApplicationsSearch:
    def test_search_matches_company(self, client, db_session, make_user, auth_headers):
        user = make_user()
        _make_application(db_session, user, company="Initech", position="Engineer")
        _make_application(db_session, user, company="Globex", position="Manager")

        response = client.get(
            APPLICATIONS_URL, params={"search": "initech"}, headers=auth_headers(user)
        )

        body = response.json()
        assert body["total"] == 1
        assert body["items"][0]["company"] == "Initech"

    def test_search_matches_position(self, client, db_session, make_user, auth_headers):
        user = make_user()
        _make_application(
            db_session, user, company="Initech", position="Backend Engineer"
        )
        _make_application(
            db_session, user, company="Globex", position="Product Manager"
        )

        response = client.get(
            APPLICATIONS_URL, params={"search": "manager"}, headers=auth_headers(user)
        )

        body = response.json()
        assert body["total"] == 1
        assert body["items"][0]["company"] == "Globex"

    def test_search_with_no_matches_returns_empty(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        _make_application(db_session, user, company="Initech")

        response = client.get(
            APPLICATIONS_URL,
            params={"search": "no-such-company-or-role"},
            headers=auth_headers(user),
        )

        assert response.json()["total"] == 0


class TestListApplicationsPagination:
    def test_paginates_results(self, client, db_session, make_user, auth_headers):
        user = make_user()
        for i in range(5):
            _make_application(db_session, user, company=f"Company {i}")

        page_1 = client.get(
            APPLICATIONS_URL,
            params={"page": 1, "page_size": 2},
            headers=auth_headers(user),
        )
        page_2 = client.get(
            APPLICATIONS_URL,
            params={"page": 2, "page_size": 2},
            headers=auth_headers(user),
        )

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
            APPLICATIONS_URL, params={"page_size": 500}, headers=auth_headers(user)
        )
        assert response.status_code == 422

    def test_page_below_one_is_rejected(self, client, make_user, auth_headers):
        user = make_user()
        response = client.get(
            APPLICATIONS_URL, params={"page": 0}, headers=auth_headers(user)
        )
        assert response.status_code == 422


class TestListApplicationsOrdering:
    def test_most_recently_updated_appears_first(
        self, client, db_session, make_user, auth_headers
    ):
        """Sets explicit updated_at values rather than relying on
        wall-clock gaps between inserts - see module docstring on why
        that's unreliable inside this fixture's single-transaction
        isolation."""
        user = make_user()
        now = datetime.now(timezone.utc)

        older = _make_application(
            db_session, user, company="Older Update", updated_at=now - timedelta(days=2)
        )
        newer = _make_application(
            db_session, user, company="Newer Update", updated_at=now - timedelta(days=1)
        )

        response = client.get(APPLICATIONS_URL, headers=auth_headers(user))

        ids_in_order = [item["id"] for item in response.json()["items"]]
        assert ids_in_order.index(str(newer.id)) < ids_in_order.index(str(older.id))
