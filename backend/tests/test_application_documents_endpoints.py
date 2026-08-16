"""
Integration tests for /applications/{application_id}/documents
(app/api/v1/endpoints/application_documents.py) - attaching/detaching an
existing, standalone document to/from an application, and listing which
documents are currently attached to one.

This used to be the flat cross-application document directory (the old
GET /documents, before Document became a top-level resource reusable
across many applications - see app/models/document.py). That directory
concern is now just the ordinary GET /documents list, covered by
test_documents_endpoints.py; this file is entirely about the many-to-many
link itself.
"""

import uuid

from app.models.application import Application, ApplicationStatus
from app.models.application_document import ApplicationDocument
from app.models.document import Document, DocumentType


def _applications_url(application_id) -> str:
    return f"/api/v1/applications/{application_id}"


def _documents_url(application_id) -> str:
    return f"{_applications_url(application_id)}/documents"


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


def _make_document(db_session, user, **overrides):
    defaults = {
        "user_id": user.id,
        "file_name": "resume.pdf",
        "file_url": f"users/{user.id}/documents/{uuid.uuid4().hex[:12]}-resume.pdf",
        "file_type": DocumentType.RESUME,
    }
    defaults.update(overrides)
    document = Document(**defaults)
    db_session.add(document)
    db_session.commit()
    db_session.refresh(document)
    return document


def _attach(db_session, application, document):
    link = ApplicationDocument(application_id=application.id, document_id=document.id)
    db_session.add(link)
    db_session.commit()
    return link


class TestApplicationDocumentsAuth:
    def test_list_requires_authentication(self, client, db_session, make_user):
        user = make_user()
        application = _make_application(db_session, user)
        response = client.get(_documents_url(application.id))
        assert response.status_code == 401

    def test_attach_requires_authentication(self, client, db_session, make_user):
        user = make_user()
        application = _make_application(db_session, user)
        document = _make_document(db_session, user)
        response = client.post(
            _documents_url(application.id), json={"document_id": str(document.id)}
        )
        assert response.status_code == 401


class TestAttachDocument:
    def test_attaches_owned_document_to_owned_application(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)
        document = _make_document(db_session, user)

        response = client.post(
            _documents_url(application.id),
            json={"document_id": str(document.id)},
            headers=auth_headers(user),
        )

        assert response.status_code == 201
        assert response.json()["id"] == str(document.id)
        assert (
            db_session.query(ApplicationDocument)
            .filter(
                ApplicationDocument.application_id == application.id,
                ApplicationDocument.document_id == document.id,
            )
            .count()
            == 1
        )

    def test_same_document_can_be_attached_to_multiple_applications(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application_a = _make_application(db_session, user, company="Initech")
        application_b = _make_application(db_session, user, company="Globex")
        document = _make_document(db_session, user)

        first = client.post(
            _documents_url(application_a.id),
            json={"document_id": str(document.id)},
            headers=auth_headers(user),
        )
        second = client.post(
            _documents_url(application_b.id),
            json={"document_id": str(document.id)},
            headers=auth_headers(user),
        )

        assert first.status_code == 201
        assert second.status_code == 201
        assert (
            db_session.query(ApplicationDocument)
            .filter(ApplicationDocument.document_id == document.id)
            .count()
            == 2
        )

    def test_attaching_the_same_pair_twice_is_409(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)
        document = _make_document(db_session, user)
        _attach(db_session, application, document)

        response = client.post(
            _documents_url(application.id),
            json={"document_id": str(document.id)},
            headers=auth_headers(user),
        )
        assert response.status_code == 409

    def test_cannot_attach_to_another_users_application(
        self, client, db_session, make_user, auth_headers
    ):
        owner = make_user()
        other_user = make_user()
        application = _make_application(db_session, owner)
        document = _make_document(db_session, other_user)

        response = client.post(
            _documents_url(application.id),
            json={"document_id": str(document.id)},
            headers=auth_headers(other_user),
        )
        assert response.status_code == 404

    def test_cannot_attach_another_users_document(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        other_user = make_user()
        application = _make_application(db_session, user)
        other_document = _make_document(db_session, other_user)

        response = client.post(
            _documents_url(application.id),
            json={"document_id": str(other_document.id)},
            headers=auth_headers(user),
        )
        assert response.status_code == 404
        assert (
            db_session.query(ApplicationDocument)
            .filter(ApplicationDocument.application_id == application.id)
            .count()
            == 0
        )

    def test_attaching_to_nonexistent_application_is_404(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        document = _make_document(db_session, user)

        response = client.post(
            _documents_url(uuid.uuid4()),
            json={"document_id": str(document.id)},
            headers=auth_headers(user),
        )
        assert response.status_code == 404


class TestDetachDocument:
    def test_detaches_document_without_deleting_it(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)
        document = _make_document(db_session, user)
        _attach(db_session, application, document)

        response = client.delete(
            f"{_documents_url(application.id)}/{document.id}",
            headers=auth_headers(user),
        )

        assert response.status_code == 204
        assert (
            db_session.query(ApplicationDocument)
            .filter(
                ApplicationDocument.application_id == application.id,
                ApplicationDocument.document_id == document.id,
            )
            .count()
            == 0
        )
        assert (
            db_session.query(Document).filter(Document.id == document.id).count() == 1
        )

    def test_detaching_unattached_document_is_404(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)
        document = _make_document(db_session, user)

        response = client.delete(
            f"{_documents_url(application.id)}/{document.id}",
            headers=auth_headers(user),
        )
        assert response.status_code == 404

    def test_cannot_detach_via_another_users_application(
        self, client, db_session, make_user, auth_headers
    ):
        owner = make_user()
        other_user = make_user()
        application = _make_application(db_session, owner)
        document = _make_document(db_session, owner)
        _attach(db_session, application, document)

        response = client.delete(
            f"{_documents_url(application.id)}/{document.id}",
            headers=auth_headers(other_user),
        )
        assert response.status_code == 404
        assert (
            db_session.query(ApplicationDocument)
            .filter(ApplicationDocument.application_id == application.id)
            .count()
            == 1
        )


class TestListAttachedDocuments:
    def test_lists_only_documents_attached_to_this_application(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application_a = _make_application(db_session, user, company="Initech")
        application_b = _make_application(db_session, user, company="Globex")
        document_a = _make_document(db_session, user, file_name="a.pdf")
        document_b = _make_document(db_session, user, file_name="b.pdf")
        _attach(db_session, application_a, document_a)
        _attach(db_session, application_b, document_b)

        response = client.get(
            _documents_url(application_a.id), headers=auth_headers(user)
        )

        assert response.status_code == 200
        body = response.json()
        assert body["total"] == 1
        assert body["items"][0]["id"] == str(document_a.id)

    def test_unattached_application_returns_empty_list(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)

        response = client.get(
            _documents_url(application.id), headers=auth_headers(user)
        )

        assert response.status_code == 200
        body = response.json()
        assert body["items"] == []
        assert body["total"] == 0

    def test_cannot_list_another_users_application_documents(
        self, client, db_session, make_user, auth_headers
    ):
        owner = make_user()
        other_user = make_user()
        application = _make_application(db_session, owner)

        response = client.get(
            _documents_url(application.id), headers=auth_headers(other_user)
        )
        assert response.status_code == 404
