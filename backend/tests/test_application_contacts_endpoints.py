"""
Integration tests for /applications/{application_id}/contacts
(app/api/v1/endpoints/application_contacts.py) - attaching/detaching an
existing, standalone contact to/from an application, and listing which
contacts are currently attached to one.

This used to be the nested CRUD route plus the flat cross-application
contact directory (the old GET /contacts, before Contact became a
top-level resource reusable across many applications - see
app/models/contact.py). That directory concern is now just the ordinary
GET /contacts list, covered by test_contacts_endpoints.py; this file is
entirely about the many-to-many link itself - the direct successor to
test_contacts_directory.py, same relationship
test_application_documents_endpoints.py has to the old
test_documents_directory.py.
"""

import uuid

from app.models.application import Application, ApplicationStatus
from app.models.application_contact import ApplicationContact
from app.models.contact import Contact


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


def _attach(db_session, application, contact):
    link = ApplicationContact(application_id=application.id, contact_id=contact.id)
    db_session.add(link)
    db_session.commit()
    return link


class TestApplicationContactsAuth:
    def test_list_requires_authentication(self, client, db_session, make_user):
        user = make_user()
        application = _make_application(db_session, user)
        response = client.get(_contacts_url(application.id))
        assert response.status_code == 401

    def test_attach_requires_authentication(self, client, db_session, make_user):
        user = make_user()
        application = _make_application(db_session, user)
        contact = _make_contact(db_session, user)
        response = client.post(
            _contacts_url(application.id), json={"contact_id": str(contact.id)}
        )
        assert response.status_code == 401


class TestAttachContact:
    def test_attaches_owned_contact_to_owned_application(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)
        contact = _make_contact(db_session, user)

        response = client.post(
            _contacts_url(application.id),
            json={"contact_id": str(contact.id)},
            headers=auth_headers(user),
        )

        assert response.status_code == 201
        assert response.json()["id"] == str(contact.id)
        assert (
            db_session.query(ApplicationContact)
            .filter(
                ApplicationContact.application_id == application.id,
                ApplicationContact.contact_id == contact.id,
            )
            .count()
            == 1
        )

    def test_same_contact_can_be_attached_to_multiple_applications(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application_a = _make_application(db_session, user, company="Initech")
        application_b = _make_application(db_session, user, company="Globex")
        contact = _make_contact(db_session, user)

        first = client.post(
            _contacts_url(application_a.id),
            json={"contact_id": str(contact.id)},
            headers=auth_headers(user),
        )
        second = client.post(
            _contacts_url(application_b.id),
            json={"contact_id": str(contact.id)},
            headers=auth_headers(user),
        )

        assert first.status_code == 201
        assert second.status_code == 201
        assert (
            db_session.query(ApplicationContact)
            .filter(ApplicationContact.contact_id == contact.id)
            .count()
            == 2
        )

    def test_attaching_the_same_pair_twice_is_409(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)
        contact = _make_contact(db_session, user)
        _attach(db_session, application, contact)

        response = client.post(
            _contacts_url(application.id),
            json={"contact_id": str(contact.id)},
            headers=auth_headers(user),
        )
        assert response.status_code == 409

    def test_cannot_attach_to_another_users_application(
        self, client, db_session, make_user, auth_headers
    ):
        owner = make_user()
        other_user = make_user()
        application = _make_application(db_session, owner)
        contact = _make_contact(db_session, other_user)

        response = client.post(
            _contacts_url(application.id),
            json={"contact_id": str(contact.id)},
            headers=auth_headers(other_user),
        )
        assert response.status_code == 404

    def test_cannot_attach_another_users_contact(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        other_user = make_user()
        application = _make_application(db_session, user)
        other_contact = _make_contact(db_session, other_user)

        response = client.post(
            _contacts_url(application.id),
            json={"contact_id": str(other_contact.id)},
            headers=auth_headers(user),
        )
        assert response.status_code == 404
        assert (
            db_session.query(ApplicationContact)
            .filter(ApplicationContact.application_id == application.id)
            .count()
            == 0
        )

    def test_attaching_to_nonexistent_application_is_404(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        contact = _make_contact(db_session, user)

        response = client.post(
            _contacts_url(uuid.uuid4()),
            json={"contact_id": str(contact.id)},
            headers=auth_headers(user),
        )
        assert response.status_code == 404


class TestDetachContact:
    def test_detaches_contact_without_deleting_it(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)
        contact = _make_contact(db_session, user)
        _attach(db_session, application, contact)

        response = client.delete(
            f"{_contacts_url(application.id)}/{contact.id}",
            headers=auth_headers(user),
        )

        assert response.status_code == 204
        assert (
            db_session.query(ApplicationContact)
            .filter(
                ApplicationContact.application_id == application.id,
                ApplicationContact.contact_id == contact.id,
            )
            .count()
            == 0
        )
        assert db_session.query(Contact).filter(Contact.id == contact.id).count() == 1

    def test_detaching_unattached_contact_is_404(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)
        contact = _make_contact(db_session, user)

        response = client.delete(
            f"{_contacts_url(application.id)}/{contact.id}",
            headers=auth_headers(user),
        )
        assert response.status_code == 404

    def test_cannot_detach_via_another_users_application(
        self, client, db_session, make_user, auth_headers
    ):
        owner = make_user()
        other_user = make_user()
        application = _make_application(db_session, owner)
        contact = _make_contact(db_session, owner)
        _attach(db_session, application, contact)

        response = client.delete(
            f"{_contacts_url(application.id)}/{contact.id}",
            headers=auth_headers(other_user),
        )
        assert response.status_code == 404
        assert (
            db_session.query(ApplicationContact)
            .filter(ApplicationContact.application_id == application.id)
            .count()
            == 1
        )


class TestListAttachedContacts:
    def test_lists_only_contacts_attached_to_this_application(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application_a = _make_application(db_session, user, company="Initech")
        application_b = _make_application(db_session, user, company="Globex")
        contact_a = _make_contact(db_session, user, name="Alice")
        contact_b = _make_contact(db_session, user, name="Bob")
        _attach(db_session, application_a, contact_a)
        _attach(db_session, application_b, contact_b)

        response = client.get(
            _contacts_url(application_a.id), headers=auth_headers(user)
        )

        assert response.status_code == 200
        body = response.json()
        assert body["total"] == 1
        assert body["items"][0]["id"] == str(contact_a.id)

    def test_unattached_application_returns_empty_list(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)

        response = client.get(_contacts_url(application.id), headers=auth_headers(user))

        assert response.status_code == 200
        body = response.json()
        assert body["items"] == []
        assert body["total"] == 0

    def test_cannot_list_another_users_application_contacts(
        self, client, db_session, make_user, auth_headers
    ):
        owner = make_user()
        other_user = make_user()
        application = _make_application(db_session, owner)

        response = client.get(
            _contacts_url(application.id), headers=auth_headers(other_user)
        )
        assert response.status_code == 404
