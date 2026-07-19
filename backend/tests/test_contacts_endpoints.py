"""
Integration tests for /applications/{application_id}/contacts
(app/api/v1/endpoints/contacts.py :: router).

This covers the nested CRUD routes only - the flat, cross-application
GET /contacts directory (:: directory_router) already has its own full
suite in test_contacts_directory.py. Uses the same fixtures as the other
endpoint test files (client, db_session, make_user, auth_headers - see
conftest.py).

A note on ordering: like created_at/updated_at elsewhere in this suite,
Contact.created_at uses server_default=func.now(), which is
transaction-scoped in Postgres - every insert in a single test can get an
identical timestamp under conftest.py's SAVEPOINT isolation. The ordering
test below sets created_at explicitly rather than relying on wall-clock
gaps between inserts, same as test_applications_endpoints.py and
test_documents_endpoints.py.

A note on pagination: unlike the directory route
(ContactWithApplicationListResponse, which has page/page_size), this
nested list_contacts endpoint has no pagination - ContactListResponse is
just items + total. That's deliberate, not a gap: a single application's
contact list is bounded by how many people are realistically involved in
one hiring process, while the directory aggregates across every
application a user has ever tracked. See BACKEND_SUMMARY.md's note on the
contacts directory endpoint for the full reasoning.
"""

import uuid
from datetime import datetime, timedelta, timezone

from app.models.application import Application, ApplicationStatus
from app.models.contact import Contact

BASE_CREATED_AT = datetime(2026, 1, 1, tzinfo=timezone.utc)


def _applications_url(application_id) -> str:
    return f"/api/v1/applications/{application_id}"


def _contacts_url(application_id) -> str:
    return f"{_applications_url(application_id)}/contacts"


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


class TestContactsAuth:
    def test_list_requires_authentication(self, client, db_session, make_user):
        user = make_user()
        application = _make_application(db_session, user)
        response = client.get(_contacts_url(application.id))
        assert response.status_code == 401

    def test_create_requires_authentication(self, client, db_session, make_user):
        user = make_user()
        application = _make_application(db_session, user)
        response = client.post(
            _contacts_url(application.id), json={"name": "Jordan Lee"}
        )
        assert response.status_code == 401

    def test_rejects_invalid_token(self, client, db_session, make_user):
        user = make_user()
        application = _make_application(db_session, user)
        response = client.get(
            _contacts_url(application.id),
            headers={"Authorization": "Bearer not-a-real-token"},
        )
        assert response.status_code == 401


class TestCreateContact:
    def test_creates_contact_for_owned_application(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)

        response = client.post(
            _contacts_url(application.id),
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
        assert body["application_id"] == str(application.id)
        assert "id" in body

    def test_optional_fields_can_be_omitted(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)

        response = client.post(
            _contacts_url(application.id),
            json={"name": "Jordan Lee"},
            headers=auth_headers(user),
        )

        assert response.status_code == 201
        body = response.json()
        assert body["title"] is None
        assert body["email"] is None
        assert body["linkedin_url"] is None

    def test_missing_name_is_rejected(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)

        response = client.post(
            _contacts_url(application.id),
            json={"title": "Technical Recruiter"},
            headers=auth_headers(user),
        )
        assert response.status_code == 422

    def test_invalid_email_is_rejected(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)

        response = client.post(
            _contacts_url(application.id),
            json={"name": "Jordan Lee", "email": "not-an-email"},
            headers=auth_headers(user),
        )
        assert response.status_code == 422

    def test_cannot_create_under_nonexistent_application(
        self, client, make_user, auth_headers
    ):
        user = make_user()
        response = client.post(
            _contacts_url(uuid.uuid4()),
            json={"name": "Jordan Lee"},
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
            _contacts_url(application.id),
            json={"name": "Jordan Lee"},
            headers=auth_headers(other_user),
        )
        assert response.status_code == 404

        remaining = (
            db_session.query(Contact)
            .filter(Contact.application_id == application.id)
            .count()
        )
        assert remaining == 0


class TestGetContact:
    def test_returns_owned_contact(self, client, db_session, make_user, auth_headers):
        user = make_user()
        application = _make_application(db_session, user)
        contact = _make_contact(db_session, application, name="Jordan Lee")

        response = client.get(
            f"{_contacts_url(application.id)}/{contact.id}", headers=auth_headers(user)
        )

        assert response.status_code == 200
        assert response.json()["name"] == "Jordan Lee"

    def test_nonexistent_contact_is_404(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)

        response = client.get(
            f"{_contacts_url(application.id)}/{uuid.uuid4()}",
            headers=auth_headers(user),
        )
        assert response.status_code == 404

    def test_malformed_id_is_422(self, client, db_session, make_user, auth_headers):
        user = make_user()
        application = _make_application(db_session, user)

        response = client.get(
            f"{_contacts_url(application.id)}/not-a-uuid", headers=auth_headers(user)
        )
        assert response.status_code == 422


class TestContactOwnership:
    """Cross-user IDOR checks - see TestContactApplicationScoping below
    for the same-user, wrong-application variant."""

    def test_cannot_get_another_users_contact(
        self, client, db_session, make_user, auth_headers
    ):
        owner = make_user()
        other_user = make_user()
        application = _make_application(db_session, owner)
        contact = _make_contact(db_session, application)

        response = client.get(
            f"{_contacts_url(application.id)}/{contact.id}",
            headers=auth_headers(other_user),
        )
        assert response.status_code == 404

    def test_cannot_update_another_users_contact(
        self, client, db_session, make_user, auth_headers
    ):
        owner = make_user()
        other_user = make_user()
        application = _make_application(db_session, owner)
        contact = _make_contact(db_session, application, name="Original Name")

        response = client.patch(
            f"{_contacts_url(application.id)}/{contact.id}",
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
        application = _make_application(db_session, owner)
        contact = _make_contact(db_session, application)

        response = client.delete(
            f"{_contacts_url(application.id)}/{contact.id}",
            headers=auth_headers(other_user),
        )
        assert response.status_code == 404

        still_there = db_session.query(Contact).filter(Contact.id == contact.id).first()
        assert still_there is not None

    def test_cannot_list_another_users_contacts(
        self, client, db_session, make_user, auth_headers
    ):
        owner = make_user()
        other_user = make_user()
        application = _make_application(db_session, owner)
        _make_contact(db_session, application)

        response = client.get(
            _contacts_url(application.id), headers=auth_headers(other_user)
        )
        assert response.status_code == 404


class TestContactApplicationScoping:
    """A same user owning two applications must not be able to reach one
    application's contact through the *other* application's URL - same
    concern as the Interviews and Documents scoping tests."""

    def test_cannot_get_contact_via_sibling_application(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application_a = _make_application(db_session, user, company="Initech")
        application_b = _make_application(db_session, user, company="Globex")
        contact = _make_contact(db_session, application_a)

        response = client.get(
            f"{_contacts_url(application_b.id)}/{contact.id}",
            headers=auth_headers(user),
        )
        assert response.status_code == 404

    def test_cannot_update_contact_via_sibling_application(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application_a = _make_application(db_session, user, company="Initech")
        application_b = _make_application(db_session, user, company="Globex")
        contact = _make_contact(db_session, application_a, name="Original")

        response = client.patch(
            f"{_contacts_url(application_b.id)}/{contact.id}",
            json={"name": "Wrong parent"},
            headers=auth_headers(user),
        )
        assert response.status_code == 404

        db_session.refresh(contact)
        assert contact.name == "Original"

    def test_cannot_delete_contact_via_sibling_application(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application_a = _make_application(db_session, user, company="Initech")
        application_b = _make_application(db_session, user, company="Globex")
        contact = _make_contact(db_session, application_a)

        response = client.delete(
            f"{_contacts_url(application_b.id)}/{contact.id}",
            headers=auth_headers(user),
        )
        assert response.status_code == 404

        still_there = db_session.query(Contact).filter(Contact.id == contact.id).first()
        assert still_there is not None

    def test_listing_one_application_does_not_include_siblings_contacts(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application_a = _make_application(db_session, user, company="Initech")
        application_b = _make_application(db_session, user, company="Globex")
        contact_a = _make_contact(db_session, application_a)
        _make_contact(db_session, application_b)

        response = client.get(
            _contacts_url(application_a.id), headers=auth_headers(user)
        )

        body = response.json()
        assert body["total"] == 1
        assert body["items"][0]["id"] == str(contact_a.id)


class TestUpdateContact:
    def test_updates_only_provided_fields(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)
        contact = _make_contact(
            db_session, application, name="Jordan Lee", title="Recruiter"
        )

        response = client.patch(
            f"{_contacts_url(application.id)}/{contact.id}",
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
        application = _make_application(db_session, user)
        contact = _make_contact(db_session, application)

        response = client.patch(
            f"{_contacts_url(application.id)}/{contact.id}",
            json={"email": "not-an-email"},
            headers=auth_headers(user),
        )
        assert response.status_code == 422

    def test_empty_update_leaves_contact_unchanged(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)
        contact = _make_contact(db_session, application, name="Jordan Lee")

        response = client.patch(
            f"{_contacts_url(application.id)}/{contact.id}",
            json={},
            headers=auth_headers(user),
        )

        assert response.status_code == 200
        assert response.json()["name"] == "Jordan Lee"

    def test_updating_nonexistent_contact_is_404(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)

        response = client.patch(
            f"{_contacts_url(application.id)}/{uuid.uuid4()}",
            json={"name": "Doesn't matter"},
            headers=auth_headers(user),
        )
        assert response.status_code == 404


class TestDeleteContact:
    def test_deletes_owned_contact(self, client, db_session, make_user, auth_headers):
        user = make_user()
        application = _make_application(db_session, user)
        contact = _make_contact(db_session, application)

        response = client.delete(
            f"{_contacts_url(application.id)}/{contact.id}", headers=auth_headers(user)
        )
        assert response.status_code == 204

        get_response = client.get(
            f"{_contacts_url(application.id)}/{contact.id}", headers=auth_headers(user)
        )
        assert get_response.status_code == 404

    def test_deleting_nonexistent_contact_is_404(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)

        response = client.delete(
            f"{_contacts_url(application.id)}/{uuid.uuid4()}",
            headers=auth_headers(user),
        )
        assert response.status_code == 404


class TestListContactsOrdering:
    def test_returns_contacts_ordered_by_created_at_descending(
        self, client, db_session, make_user, auth_headers
    ):
        """Explicit created_at values, not wall-clock gaps - see module
        docstring."""
        user = make_user()
        application = _make_application(db_session, user)

        oldest = _make_contact(
            db_session, application, name="Oldest", created_at=BASE_CREATED_AT
        )
        newest = _make_contact(
            db_session,
            application,
            name="Newest",
            created_at=BASE_CREATED_AT + timedelta(days=2),
        )
        middle = _make_contact(
            db_session,
            application,
            name="Middle",
            created_at=BASE_CREATED_AT + timedelta(days=1),
        )

        response = client.get(_contacts_url(application.id), headers=auth_headers(user))

        ids_in_order = [item["id"] for item in response.json()["items"]]
        assert ids_in_order == [str(newest.id), str(middle.id), str(oldest.id)]

    def test_empty_application_returns_empty_list(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)

        response = client.get(_contacts_url(application.id), headers=auth_headers(user))

        assert response.status_code == 200
        body = response.json()
        assert body["items"] == []
        assert body["total"] == 0
