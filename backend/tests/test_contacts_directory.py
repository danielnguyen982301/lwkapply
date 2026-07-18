"""
Integration tests for GET /contacts
(app/api/v1/endpoints/contacts.py :: directory_router).

This is the first endpoint-level test in the suite (see
BACKEND_SUMMARY.md), running against a real Postgres instance via
TestClient + the transactional fixtures in conftest.py, rather than pure
schema validation like test_contact_schema.py.

The route is deliberately not nested under /applications/{id} - it's a
flat, cross-application listing scoped only by Application.user_id via a
join. That means there's no application_id in the URL to accidentally
scope by, which makes the ownership/IDOR check the single most important
thing this file verifies.
"""

from app.models.application import Application, ApplicationStatus
from app.models.contact import Contact

CONTACTS_URL = "/api/v1/contacts"


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


def _make_contact(db_session, application, **overrides):
    defaults = {
        "application_id": application.id,
        "name": "Jordan Lee",
    }
    defaults.update(overrides)
    contact = Contact(**defaults)
    db_session.add(contact)
    db_session.commit()
    db_session.refresh(contact)
    return contact


class TestContactsDirectoryAuth:
    def test_requires_authentication(self, client):
        response = client.get(CONTACTS_URL)
        assert response.status_code == 401

    def test_rejects_invalid_token(self, client):
        response = client.get(
            CONTACTS_URL, headers={"Authorization": "Bearer not-a-real-token"}
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
            CONTACTS_URL, headers={"Authorization": f"Bearer {token}"}
        )
        assert response.status_code == 401


class TestContactsDirectoryAggregation:
    def test_aggregates_contacts_across_applications(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        app_a = _make_application(db_session, user, company="Initech")
        app_b = _make_application(db_session, user, company="Globex")
        _make_contact(db_session, app_a, name="Alice Recruiter")
        _make_contact(db_session, app_b, name="Bob Hiring Manager")

        response = client.get(CONTACTS_URL, headers=auth_headers(user))

        assert response.status_code == 200
        body = response.json()
        assert body["total"] == 2
        names = {item["name"] for item in body["items"]}
        assert names == {"Alice Recruiter", "Bob Hiring Manager"}
        companies = {item["application"]["company"] for item in body["items"]}
        assert companies == {"Initech", "Globex"}

    def test_embeds_correct_parent_application_per_contact(
        self, client, db_session, make_user, auth_headers
    ):
        """Guards the contains_eager() join specifically: each contact
        must be paired with its own application, not e.g. the last
        application row seen during the join."""
        user = make_user()
        app_a = _make_application(db_session, user, company="Initech")
        app_b = _make_application(db_session, user, company="Globex")
        _make_contact(db_session, app_a, name="Alice Recruiter")
        _make_contact(db_session, app_b, name="Bob Hiring Manager")

        response = client.get(CONTACTS_URL, headers=auth_headers(user))

        by_name = {item["name"]: item for item in response.json()["items"]}
        assert by_name["Alice Recruiter"]["application"]["company"] == "Initech"
        assert by_name["Bob Hiring Manager"]["application"]["company"] == "Globex"

    def test_empty_when_user_has_no_contacts(self, client, make_user, auth_headers):
        user = make_user()
        response = client.get(CONTACTS_URL, headers=auth_headers(user))
        assert response.status_code == 200
        body = response.json()
        assert body["items"] == []
        assert body["total"] == 0


class TestContactsDirectoryOwnership:
    def test_user_cannot_see_another_users_contacts(
        self, client, db_session, make_user, auth_headers
    ):
        """The critical IDOR check flagged in BACKEND_SUMMARY.md: this
        route has no application_id path param, so the
        Application.user_id join/filter is the *only* thing standing
        between one user and every other user's contacts."""
        owner = make_user()
        other_user = make_user()

        owner_app = _make_application(db_session, owner, company="Initech")
        _make_contact(db_session, owner_app, name="Owner's Contact")

        other_app = _make_application(db_session, other_user, company="Umbrella Corp")
        _make_contact(db_session, other_app, name="Other User's Contact")

        response = client.get(CONTACTS_URL, headers=auth_headers(other_user))

        assert response.status_code == 200
        body = response.json()
        assert body["total"] == 1
        assert body["items"][0]["name"] == "Other User's Contact"

    def test_search_cannot_be_used_to_find_another_users_contacts(
        self, client, db_session, make_user, auth_headers
    ):
        """Same IDOR concern, but via the search filter: a broad search
        term must still be scoped by ownership, not just by the
        search-term match."""
        owner = make_user()
        other_user = make_user()

        owner_app = _make_application(db_session, owner, company="Initech")
        _make_contact(db_session, owner_app, name="Zzz Unique Search Target")

        other_app = _make_application(db_session, other_user, company="Globex")
        _make_contact(db_session, other_app, name="Someone Else")

        response = client.get(
            CONTACTS_URL,
            params={"search": "Zzz Unique Search Target"},
            headers=auth_headers(other_user),
        )

        assert response.status_code == 200
        body = response.json()
        assert body["total"] == 0
        assert body["items"] == []


class TestContactsDirectorySearch:
    def test_search_matches_contact_name(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)
        _make_contact(db_session, application, name="Alice Recruiter")
        _make_contact(db_session, application, name="Bob Hiring Manager")

        response = client.get(
            CONTACTS_URL, params={"search": "alice"}, headers=auth_headers(user)
        )

        assert response.status_code == 200
        body = response.json()
        assert body["total"] == 1
        assert body["items"][0]["name"] == "Alice Recruiter"

    def test_search_matches_application_company(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        app_a = _make_application(db_session, user, company="Initech")
        app_b = _make_application(db_session, user, company="Globex")
        _make_contact(db_session, app_a, name="Alice Recruiter")
        _make_contact(db_session, app_b, name="Bob Hiring Manager")

        response = client.get(
            CONTACTS_URL, params={"search": "globex"}, headers=auth_headers(user)
        )

        assert response.status_code == 200
        body = response.json()
        assert body["total"] == 1
        assert body["items"][0]["name"] == "Bob Hiring Manager"

    def test_search_with_no_matches_returns_empty(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)
        _make_contact(db_session, application, name="Alice Recruiter")

        response = client.get(
            CONTACTS_URL,
            params={"search": "no-such-contact-or-company"},
            headers=auth_headers(user),
        )

        assert response.status_code == 200
        assert response.json()["total"] == 0


class TestContactsDirectoryPagination:
    def test_paginates_results(self, client, db_session, make_user, auth_headers):
        user = make_user()
        application = _make_application(db_session, user)
        for i in range(5):
            _make_contact(db_session, application, name=f"Contact {i}")

        page_1 = client.get(
            CONTACTS_URL,
            params={"page": 1, "page_size": 2},
            headers=auth_headers(user),
        )
        page_2 = client.get(
            CONTACTS_URL,
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
            CONTACTS_URL, params={"page_size": 500}, headers=auth_headers(user)
        )
        assert response.status_code == 422

    def test_page_below_one_is_rejected(self, client, make_user, auth_headers):
        user = make_user()
        response = client.get(
            CONTACTS_URL, params={"page": 0}, headers=auth_headers(user)
        )
        assert response.status_code == 422
