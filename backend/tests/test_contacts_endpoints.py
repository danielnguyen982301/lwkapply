"""
Integration tests for /contacts (app/api/v1/endpoints/contacts.py).

Contacts are a top-level, user-owned resource - not nested under an
application (see app/models/contact.py's module docstring). Creating,
reading, updating, deleting, listing/searching/paginating all live here.
Attaching/detaching a contact to/from a specific application is a
separate concern, covered by test_application_contacts_endpoints.py.

Uses the same fixtures as the other endpoint test files (client,
db_session, make_user, auth_headers - see conftest.py).

A note on ordering: like created_at/updated_at elsewhere in this suite,
Contact.created_at uses server_default=func.now(), which is
transaction-scoped in Postgres - every insert in a single test can get an
identical timestamp under conftest.py's SAVEPOINT isolation. The
ordering test below sets created_at explicitly rather than relying on
wall-clock gaps between inserts, same as test_documents_endpoints.py.

Unlike the old nested route, there's no application-scoping case to test
here any more - a contact isn't reachable through any application's URL
except via the attach/detach link, same as Document.
"""

import uuid
from datetime import datetime, timedelta, timezone

from app.models.contact import Contact

CONTACTS_URL = "/api/v1/contacts"
BASE_CREATED_AT = datetime(2026, 1, 1, tzinfo=timezone.utc)


def _make_contact(db_session, user, **overrides):
    defaults = {
        "user_id": user.id,
        "name": "Jordan Lee",
    }
    defaults.update(overrides)
    contact = Contact(**defaults)
    db_session.add(contact)
    db_session.commit()
    db_session.refresh(contact)
    return contact


class TestContactsAuth:
    def test_list_requires_authentication(self, client):
        response = client.get(CONTACTS_URL)
        assert response.status_code == 401

    def test_create_requires_authentication(self, client):
        response = client.post(CONTACTS_URL, json={"name": "Jordan Lee"})
        assert response.status_code == 401

    def test_rejects_invalid_token(self, client):
        response = client.get(
            CONTACTS_URL, headers={"Authorization": "Bearer not-a-real-token"}
        )
        assert response.status_code == 401


class TestCreateContact:
    def test_creates_contact_for_current_user(self, client, make_user, auth_headers):
        user = make_user()

        response = client.post(
            CONTACTS_URL,
            json={
                "name": "Jordan Lee",
                "title": "Technical Recruiter",
                "email": "jordan@initech.example",
                "linkedin_url": "https://linkedin.com/in/jordanlee",
            },
            headers=auth_headers(user),
        )

        assert response.status_code == 201
        body = response.json()
        assert body["name"] == "Jordan Lee"
        assert body["title"] == "Technical Recruiter"
        assert "application_id" not in body
        assert "id" in body

    def test_optional_fields_can_be_omitted(self, client, make_user, auth_headers):
        user = make_user()

        response = client.post(
            CONTACTS_URL, json={"name": "Jordan Lee"}, headers=auth_headers(user)
        )

        assert response.status_code == 201
        body = response.json()
        assert body["title"] is None
        assert body["email"] is None
        assert body["linkedin_url"] is None

    def test_missing_name_is_rejected(self, client, make_user, auth_headers):
        user = make_user()

        response = client.post(
            CONTACTS_URL,
            json={"title": "Technical Recruiter"},
            headers=auth_headers(user),
        )
        assert response.status_code == 422

    def test_invalid_email_is_rejected(self, client, make_user, auth_headers):
        user = make_user()

        response = client.post(
            CONTACTS_URL,
            json={"name": "Jordan Lee", "email": "not-an-email"},
            headers=auth_headers(user),
        )
        assert response.status_code == 422


class TestGetContact:
    def test_returns_owned_contact(self, client, db_session, make_user, auth_headers):
        user = make_user()
        contact = _make_contact(db_session, user, name="Jordan Lee")

        response = client.get(
            f"{CONTACTS_URL}/{contact.id}", headers=auth_headers(user)
        )

        assert response.status_code == 200
        assert response.json()["name"] == "Jordan Lee"

    def test_nonexistent_contact_is_404(self, client, make_user, auth_headers):
        user = make_user()

        response = client.get(
            f"{CONTACTS_URL}/{uuid.uuid4()}", headers=auth_headers(user)
        )
        assert response.status_code == 404

    def test_malformed_id_is_422(self, client, make_user, auth_headers):
        user = make_user()

        response = client.get(f"{CONTACTS_URL}/not-a-uuid", headers=auth_headers(user))
        assert response.status_code == 422


class TestContactOwnership:
    def test_cannot_get_another_users_contact(
        self, client, db_session, make_user, auth_headers
    ):
        owner = make_user()
        other_user = make_user()
        contact = _make_contact(db_session, owner)

        response = client.get(
            f"{CONTACTS_URL}/{contact.id}", headers=auth_headers(other_user)
        )
        assert response.status_code == 404

    def test_cannot_update_another_users_contact(
        self, client, db_session, make_user, auth_headers
    ):
        owner = make_user()
        other_user = make_user()
        contact = _make_contact(db_session, owner, name="Original Name")

        response = client.patch(
            f"{CONTACTS_URL}/{contact.id}",
            json={"name": "Hijacked Name"},
            headers=auth_headers(other_user),
        )
        assert response.status_code == 404

        db_session.refresh(contact)
        assert contact.name == "Original Name"

    def test_cannot_delete_another_users_contact(
        self, client, db_session, make_user, auth_headers
    ):
        owner = make_user()
        other_user = make_user()
        contact = _make_contact(db_session, owner)

        response = client.delete(
            f"{CONTACTS_URL}/{contact.id}", headers=auth_headers(other_user)
        )
        assert response.status_code == 404

        still_there = db_session.query(Contact).filter(Contact.id == contact.id).first()
        assert still_there is not None

    def test_cannot_list_another_users_contacts(
        self, client, db_session, make_user, auth_headers
    ):
        owner = make_user()
        other_user = make_user()
        _make_contact(db_session, owner, name="Owner's Contact")

        response = client.get(CONTACTS_URL, headers=auth_headers(other_user))

        assert response.status_code == 200
        body = response.json()
        assert body["items"] == []
        assert body["total"] == 0

    def test_search_cannot_be_used_to_find_another_users_contacts(
        self, client, db_session, make_user, auth_headers
    ):
        owner = make_user()
        other_user = make_user()
        _make_contact(db_session, owner, name="Zzz Unique Search Target")

        response = client.get(
            CONTACTS_URL,
            params={"search": "Zzz Unique Search Target"},
            headers=auth_headers(other_user),
        )

        assert response.status_code == 200
        body = response.json()
        assert body["total"] == 0
        assert body["items"] == []


class TestUpdateContact:
    def test_updates_only_provided_fields(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        contact = _make_contact(db_session, user, name="Jordan Lee", title="Recruiter")

        response = client.patch(
            f"{CONTACTS_URL}/{contact.id}",
            json={"title": "Senior Recruiter"},
            headers=auth_headers(user),
        )

        assert response.status_code == 200
        body = response.json()
        assert body["title"] == "Senior Recruiter"
        assert body["name"] == "Jordan Lee"

    def test_invalid_email_is_rejected(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        contact = _make_contact(db_session, user)

        response = client.patch(
            f"{CONTACTS_URL}/{contact.id}",
            json={"email": "not-an-email"},
            headers=auth_headers(user),
        )
        assert response.status_code == 422

    def test_empty_update_leaves_contact_unchanged(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        contact = _make_contact(db_session, user, name="Jordan Lee")

        response = client.patch(
            f"{CONTACTS_URL}/{contact.id}", json={}, headers=auth_headers(user)
        )

        assert response.status_code == 200
        assert response.json()["name"] == "Jordan Lee"

    def test_updating_nonexistent_contact_is_404(self, client, make_user, auth_headers):
        user = make_user()

        response = client.patch(
            f"{CONTACTS_URL}/{uuid.uuid4()}",
            json={"name": "Doesn't matter"},
            headers=auth_headers(user),
        )
        assert response.status_code == 404


class TestDeleteContact:
    def test_deletes_owned_contact(self, client, db_session, make_user, auth_headers):
        user = make_user()
        contact = _make_contact(db_session, user)

        response = client.delete(
            f"{CONTACTS_URL}/{contact.id}", headers=auth_headers(user)
        )
        assert response.status_code == 204

        get_response = client.get(
            f"{CONTACTS_URL}/{contact.id}", headers=auth_headers(user)
        )
        assert get_response.status_code == 404

    def test_deleting_nonexistent_contact_is_404(self, client, make_user, auth_headers):
        user = make_user()

        response = client.delete(
            f"{CONTACTS_URL}/{uuid.uuid4()}", headers=auth_headers(user)
        )
        assert response.status_code == 404


class TestListContactsOrdering:
    def test_returns_contacts_ordered_by_created_at_descending(
        self, client, db_session, make_user, auth_headers
    ):
        """Explicit created_at values, not wall-clock gaps - see module
        docstring."""
        user = make_user()

        oldest = _make_contact(
            db_session, user, name="Oldest", created_at=BASE_CREATED_AT
        )
        newest = _make_contact(
            db_session,
            user,
            name="Newest",
            created_at=BASE_CREATED_AT + timedelta(days=2),
        )
        middle = _make_contact(
            db_session,
            user,
            name="Middle",
            created_at=BASE_CREATED_AT + timedelta(days=1),
        )

        response = client.get(CONTACTS_URL, headers=auth_headers(user))

        ids_in_order = [item["id"] for item in response.json()["items"]]
        assert ids_in_order == [str(newest.id), str(middle.id), str(oldest.id)]

    def test_empty_list_when_user_has_no_contacts(
        self, client, make_user, auth_headers
    ):
        user = make_user()

        response = client.get(CONTACTS_URL, headers=auth_headers(user))

        assert response.status_code == 200
        body = response.json()
        assert body["items"] == []
        assert body["total"] == 0


class TestSearchContacts:
    def test_search_matches_contact_name(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        _make_contact(db_session, user, name="Alice Recruiter")
        _make_contact(db_session, user, name="Bob Hiring Manager")

        response = client.get(
            CONTACTS_URL, params={"search": "alice"}, headers=auth_headers(user)
        )

        assert response.status_code == 200
        body = response.json()
        assert body["total"] == 1
        assert body["items"][0]["name"] == "Alice Recruiter"

    def test_search_with_no_matches_returns_empty(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        _make_contact(db_session, user, name="Alice Recruiter")

        response = client.get(
            CONTACTS_URL,
            params={"search": "no-such-contact"},
            headers=auth_headers(user),
        )

        assert response.status_code == 200
        assert response.json()["total"] == 0


class TestContactsPagination:
    def test_paginates_results(self, client, db_session, make_user, auth_headers):
        user = make_user()
        for i in range(5):
            _make_contact(db_session, user, name=f"Contact {i}")

        page_1 = client.get(
            CONTACTS_URL, params={"page": 1, "page_size": 2}, headers=auth_headers(user)
        )
        page_2 = client.get(
            CONTACTS_URL, params={"page": 2, "page_size": 2}, headers=auth_headers(user)
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
