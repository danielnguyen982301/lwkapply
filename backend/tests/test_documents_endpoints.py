"""
Integration tests for /applications/{application_id}/documents
(app/api/v1/endpoints/documents.py).

Uses the same fixtures as the other endpoint test files (client,
db_session, make_user, auth_headers - see conftest.py), plus a local,
file-scoped `fake_s3_client` fixture.

Mocking strategy: only app.services.s3._s3_client (the actual boto3
client factory - the real boundary to AWS) is patched, not
upload_document/delete_document/generate_download_url themselves. That
means validate_upload's content-type check, the chunked
MAX_UPLOAD_SIZE_MB enforcement, and _build_object_key's key format all
still run for real in these tests - only the actual network call to S3
is faked. Patching app.services.s3._s3_client (not e.g. a reference in
the documents endpoint module) works because upload_document/
delete_document/generate_download_url all call _s3_client() by name at
call time, resolved through their own module's globals - unaffected by
how those functions were themselves imported into documents.py.

A note on ordering tests: like Applications' created_at/updated_at,
Document.created_at uses server_default=func.now(), which is
transaction-scoped in Postgres - every insert in a single test can get
an identical timestamp under conftest.py's SAVEPOINT isolation. The
ordering test below sets created_at explicitly rather than relying on
wall-clock gaps between inserts, same as test_applications_endpoints.py.
"""

import uuid
from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock

import pytest
from botocore.exceptions import ClientError

import app.services.s3 as s3_service
from app.models.application import Application, ApplicationStatus
from app.models.document import Document, DocumentType

PDF_BYTES = b"%PDF-1.4 fake pdf content for testing"


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


def _make_document(db_session, application, **overrides):
    defaults = {
        "application_id": application.id,
        "file_name": "resume.pdf",
        "file_url": f"users/fake/applications/fake/{uuid.uuid4().hex[:12]}-resume.pdf",
        "file_type": DocumentType.RESUME,
    }
    defaults.update(overrides)
    document = Document(**defaults)
    db_session.add(document)
    db_session.commit()
    db_session.refresh(document)
    return document


@pytest.fixture(autouse=True)
def fake_s3_client(monkeypatch):
    """Applies to every test in this file automatically - real S3 calls
    would fail anyway (no network, no real bucket). Tests that care can
    still accept fake_s3_client as a normal fixture param to inspect
    calls (e.g. .put_object.call_args) or set a .side_effect to simulate
    an S3-side failure - pytest caches fixture results per test, so an
    autouse fixture and one explicitly requested by name resolve to the
    same instance within a single test."""
    fake_client = MagicMock()
    fake_client.put_object.return_value = {}
    fake_client.delete_object.return_value = {}
    fake_client.generate_presigned_url.return_value = (
        "https://fake-bucket.s3.amazonaws.com/presigned-fake-key"
    )
    monkeypatch.setattr(s3_service, "_s3_client", lambda: fake_client)
    return fake_client


class TestDocumentsAuth:
    def test_list_requires_authentication(self, client, db_session, make_user):
        user = make_user()
        application = _make_application(db_session, user)
        response = client.get(_documents_url(application.id))
        assert response.status_code == 401

    def test_upload_requires_authentication(self, client, db_session, make_user):
        user = make_user()
        application = _make_application(db_session, user)
        response = client.post(
            _documents_url(application.id),
            files={"file": ("resume.pdf", PDF_BYTES, "application/pdf")},
        )
        assert response.status_code == 401


class TestUploadDocument:
    def test_uploads_document_for_owned_application(
        self, client, db_session, make_user, auth_headers, fake_s3_client
    ):
        user = make_user()
        application = _make_application(db_session, user)

        response = client.post(
            _documents_url(application.id),
            files={"file": ("resume.pdf", PDF_BYTES, "application/pdf")},
            headers=auth_headers(user),
        )

        assert response.status_code == 201
        body = response.json()
        assert body["file_name"] == "resume.pdf"
        assert body["application_id"] == str(application.id)
        assert "file_url" not in body
        fake_s3_client.put_object.assert_called_once()

    def test_defaults_to_other_file_type(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)

        response = client.post(
            _documents_url(application.id),
            files={"file": ("resume.pdf", PDF_BYTES, "application/pdf")},
            headers=auth_headers(user),
        )

        assert response.json()["file_type"] == "other"

    def test_explicit_file_type_is_respected(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)

        response = client.post(
            _documents_url(application.id),
            files={"file": ("resume.pdf", PDF_BYTES, "application/pdf")},
            data={"file_type": "resume"},
            headers=auth_headers(user),
        )

        assert response.json()["file_type"] == "resume"

    def test_rejects_unsupported_content_type(
        self, client, db_session, make_user, auth_headers, fake_s3_client
    ):
        user = make_user()
        application = _make_application(db_session, user)

        response = client.post(
            _documents_url(application.id),
            files={"file": ("resume.txt", b"plain text resume", "text/plain")},
            headers=auth_headers(user),
        )

        assert response.status_code == 415
        fake_s3_client.put_object.assert_not_called()
        assert (
            db_session.query(Document)
            .filter(Document.application_id == application.id)
            .count()
            == 0
        )

    def test_rejects_file_over_size_limit(
        self, client, db_session, make_user, auth_headers, fake_s3_client, monkeypatch
    ):
        # Lowering MAX_UPLOAD_SIZE_MB rather than generating a real
        # 10MB+ payload - exercises the same chunked size-check code
        # path in s3.upload_document without the overhead.
        monkeypatch.setattr(s3_service.settings, "MAX_UPLOAD_SIZE_MB", 1)
        user = make_user()
        application = _make_application(db_session, user)
        oversized_bytes = b"x" * (2 * 1024 * 1024)  # 2MB > the 1MB limit above

        response = client.post(
            _documents_url(application.id),
            files={"file": ("resume.pdf", oversized_bytes, "application/pdf")},
            headers=auth_headers(user),
        )

        assert response.status_code == 413
        fake_s3_client.put_object.assert_not_called()
        assert (
            db_session.query(Document)
            .filter(Document.application_id == application.id)
            .count()
            == 0
        )

    def test_s3_failure_during_upload_returns_502(
        self, client, db_session, make_user, auth_headers, fake_s3_client
    ):
        fake_s3_client.put_object.side_effect = ClientError(
            {"Error": {"Code": "500", "Message": "boom"}}, "PutObject"
        )
        user = make_user()
        application = _make_application(db_session, user)

        response = client.post(
            _documents_url(application.id),
            files={"file": ("resume.pdf", PDF_BYTES, "application/pdf")},
            headers=auth_headers(user),
        )

        assert response.status_code == 502
        assert (
            db_session.query(Document)
            .filter(Document.application_id == application.id)
            .count()
            == 0
        )

    def test_cannot_upload_to_nonexistent_application(
        self, client, make_user, auth_headers, fake_s3_client
    ):
        user = make_user()
        response = client.post(
            _documents_url(uuid.uuid4()),
            files={"file": ("resume.pdf", PDF_BYTES, "application/pdf")},
            headers=auth_headers(user),
        )
        assert response.status_code == 404
        fake_s3_client.put_object.assert_not_called()

    def test_cannot_upload_to_another_users_application(
        self, client, db_session, make_user, auth_headers, fake_s3_client
    ):
        owner = make_user()
        other_user = make_user()
        application = _make_application(db_session, owner)

        response = client.post(
            _documents_url(application.id),
            files={"file": ("resume.pdf", PDF_BYTES, "application/pdf")},
            headers=auth_headers(other_user),
        )

        assert response.status_code == 404
        fake_s3_client.put_object.assert_not_called()


class TestGetDocument:
    def test_returns_owned_document(self, client, db_session, make_user, auth_headers):
        user = make_user()
        application = _make_application(db_session, user)
        document = _make_document(db_session, application, file_name="cover_letter.pdf")

        response = client.get(
            f"{_documents_url(application.id)}/{document.id}",
            headers=auth_headers(user),
        )

        assert response.status_code == 200
        assert response.json()["file_name"] == "cover_letter.pdf"

    def test_response_never_includes_file_url(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)
        document = _make_document(db_session, application)

        response = client.get(
            f"{_documents_url(application.id)}/{document.id}",
            headers=auth_headers(user),
        )

        assert "file_url" not in response.json()

    def test_nonexistent_document_is_404(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)

        response = client.get(
            f"{_documents_url(application.id)}/{uuid.uuid4()}",
            headers=auth_headers(user),
        )
        assert response.status_code == 404


class TestDocumentOwnership:
    def test_cannot_get_another_users_document(
        self, client, db_session, make_user, auth_headers
    ):
        owner = make_user()
        other_user = make_user()
        application = _make_application(db_session, owner)
        document = _make_document(db_session, application)

        response = client.get(
            f"{_documents_url(application.id)}/{document.id}",
            headers=auth_headers(other_user),
        )
        assert response.status_code == 404

    def test_cannot_update_another_users_document(
        self, client, db_session, make_user, auth_headers
    ):
        owner = make_user()
        other_user = make_user()
        application = _make_application(db_session, owner)
        document = _make_document(db_session, application, file_type=DocumentType.OTHER)

        response = client.patch(
            f"{_documents_url(application.id)}/{document.id}",
            json={"file_type": "resume"},
            headers=auth_headers(other_user),
        )
        assert response.status_code == 404

        db_session.refresh(document)
        assert document.file_type == DocumentType.OTHER

    def test_cannot_delete_another_users_document(
        self, client, db_session, make_user, auth_headers, fake_s3_client
    ):
        owner = make_user()
        other_user = make_user()
        application = _make_application(db_session, owner)
        document = _make_document(db_session, application)

        response = client.delete(
            f"{_documents_url(application.id)}/{document.id}",
            headers=auth_headers(other_user),
        )
        assert response.status_code == 404
        fake_s3_client.delete_object.assert_not_called()

        still_there = (
            db_session.query(Document).filter(Document.id == document.id).first()
        )
        assert still_there is not None

    def test_cannot_download_another_users_document(
        self, client, db_session, make_user, auth_headers, fake_s3_client
    ):
        owner = make_user()
        other_user = make_user()
        application = _make_application(db_session, owner)
        document = _make_document(db_session, application)

        response = client.get(
            f"{_documents_url(application.id)}/{document.id}/download",
            headers=auth_headers(other_user),
        )
        assert response.status_code == 404
        fake_s3_client.generate_presigned_url.assert_not_called()

    def test_cannot_list_another_users_documents(
        self, client, db_session, make_user, auth_headers
    ):
        owner = make_user()
        other_user = make_user()
        application = _make_application(db_session, owner)
        _make_document(db_session, application)

        response = client.get(
            _documents_url(application.id), headers=auth_headers(other_user)
        )
        assert response.status_code == 404


class TestDocumentApplicationScoping:
    """Same concern as Interviews: a document under one application must
    not be reachable through a sibling application's URL, even for the
    same user."""

    def test_cannot_get_document_via_sibling_application(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application_a = _make_application(db_session, user, company="Initech")
        application_b = _make_application(db_session, user, company="Globex")
        document = _make_document(db_session, application_a)

        response = client.get(
            f"{_documents_url(application_b.id)}/{document.id}",
            headers=auth_headers(user),
        )
        assert response.status_code == 404

    def test_cannot_delete_document_via_sibling_application(
        self, client, db_session, make_user, auth_headers, fake_s3_client
    ):
        user = make_user()
        application_a = _make_application(db_session, user, company="Initech")
        application_b = _make_application(db_session, user, company="Globex")
        document = _make_document(db_session, application_a)

        response = client.delete(
            f"{_documents_url(application_b.id)}/{document.id}",
            headers=auth_headers(user),
        )
        assert response.status_code == 404
        fake_s3_client.delete_object.assert_not_called()


class TestDownloadDocument:
    def test_returns_presigned_url(
        self, client, db_session, make_user, auth_headers, fake_s3_client
    ):
        user = make_user()
        application = _make_application(db_session, user)
        document = _make_document(db_session, application)

        response = client.get(
            f"{_documents_url(application.id)}/{document.id}/download",
            headers=auth_headers(user),
        )

        assert response.status_code == 200
        body = response.json()
        assert body["download_url"] == (
            "https://fake-bucket.s3.amazonaws.com/presigned-fake-key"
        )
        assert body["expires_in_seconds"] == 300

        _, call_kwargs = fake_s3_client.generate_presigned_url.call_args
        assert call_kwargs["Params"]["Key"] == document.file_url

    def test_s3_failure_returns_502(
        self, client, db_session, make_user, auth_headers, fake_s3_client
    ):
        fake_s3_client.generate_presigned_url.side_effect = ClientError(
            {"Error": {"Code": "500", "Message": "boom"}}, "GeneratePresignedUrl"
        )
        user = make_user()
        application = _make_application(db_session, user)
        document = _make_document(db_session, application)

        response = client.get(
            f"{_documents_url(application.id)}/{document.id}/download",
            headers=auth_headers(user),
        )
        assert response.status_code == 502

    def test_nonexistent_document_is_404(
        self, client, db_session, make_user, auth_headers, fake_s3_client
    ):
        user = make_user()
        application = _make_application(db_session, user)

        response = client.get(
            f"{_documents_url(application.id)}/{uuid.uuid4()}/download",
            headers=auth_headers(user),
        )
        assert response.status_code == 404
        fake_s3_client.generate_presigned_url.assert_not_called()


class TestUpdateDocument:
    def test_updates_file_type(self, client, db_session, make_user, auth_headers):
        user = make_user()
        application = _make_application(db_session, user)
        document = _make_document(db_session, application, file_type=DocumentType.OTHER)

        response = client.patch(
            f"{_documents_url(application.id)}/{document.id}",
            json={"file_type": "resume"},
            headers=auth_headers(user),
        )

        assert response.status_code == 200
        assert response.json()["file_type"] == "resume"

    def test_invalid_file_type_is_rejected(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)
        document = _make_document(db_session, application)

        response = client.patch(
            f"{_documents_url(application.id)}/{document.id}",
            json={"file_type": "not-a-real-type"},
            headers=auth_headers(user),
        )
        assert response.status_code == 422

    def test_spoofed_file_url_in_payload_is_ignored(
        self, client, db_session, make_user, auth_headers
    ):
        """DocumentUpdate only has file_type - file_name/file_url aren't
        fields on it at all, so pydantic's default extra='ignore' drops
        them. A client can't redirect a document's stored S3 key to an
        object it doesn't own by PATCHing file_url."""
        user = make_user()
        application = _make_application(db_session, user)
        document = _make_document(db_session, application, file_url="original/key.pdf")

        response = client.patch(
            f"{_documents_url(application.id)}/{document.id}",
            json={"file_type": "resume", "file_url": "someone/elses/key.pdf"},
            headers=auth_headers(user),
        )

        assert response.status_code == 200
        db_session.refresh(document)
        assert document.file_url == "original/key.pdf"

    def test_empty_update_leaves_document_unchanged(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)
        document = _make_document(
            db_session, application, file_type=DocumentType.RESUME
        )

        response = client.patch(
            f"{_documents_url(application.id)}/{document.id}",
            json={},
            headers=auth_headers(user),
        )

        assert response.status_code == 200
        assert response.json()["file_type"] == "resume"

    def test_updating_nonexistent_document_is_404(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)

        response = client.patch(
            f"{_documents_url(application.id)}/{uuid.uuid4()}",
            json={"file_type": "resume"},
            headers=auth_headers(user),
        )
        assert response.status_code == 404


class TestDeleteDocument:
    def test_deletes_owned_document(
        self, client, db_session, make_user, auth_headers, fake_s3_client
    ):
        user = make_user()
        application = _make_application(db_session, user)
        document = _make_document(
            db_session, application, file_url="users/x/apps/y/key.pdf"
        )

        response = client.delete(
            f"{_documents_url(application.id)}/{document.id}",
            headers=auth_headers(user),
        )

        assert response.status_code == 204
        fake_s3_client.delete_object.assert_called_once()
        _, call_kwargs = fake_s3_client.delete_object.call_args
        assert call_kwargs["Key"] == "users/x/apps/y/key.pdf"

        get_response = client.get(
            f"{_documents_url(application.id)}/{document.id}",
            headers=auth_headers(user),
        )
        assert get_response.status_code == 404

    def test_delete_succeeds_even_if_s3_cleanup_fails(
        self, client, db_session, make_user, auth_headers, fake_s3_client
    ):
        """delete_document() in s3.py deliberately swallows S3 errors -
        the DB row is the source of truth for whether a document exists,
        per its own docstring. Confirms that contract holds end-to-end
        through the actual endpoint, not just in the service function
        in isolation."""
        fake_s3_client.delete_object.side_effect = ClientError(
            {"Error": {"Code": "500", "Message": "boom"}}, "DeleteObject"
        )
        user = make_user()
        application = _make_application(db_session, user)
        document = _make_document(db_session, application)

        response = client.delete(
            f"{_documents_url(application.id)}/{document.id}",
            headers=auth_headers(user),
        )

        assert response.status_code == 204
        still_there = (
            db_session.query(Document).filter(Document.id == document.id).first()
        )
        assert still_there is None

    def test_deleting_nonexistent_document_is_404(
        self, client, db_session, make_user, auth_headers, fake_s3_client
    ):
        user = make_user()
        application = _make_application(db_session, user)

        response = client.delete(
            f"{_documents_url(application.id)}/{uuid.uuid4()}",
            headers=auth_headers(user),
        )
        assert response.status_code == 404
        fake_s3_client.delete_object.assert_not_called()


class TestListDocumentsOrdering:
    def test_returns_documents_ordered_by_created_at_descending(
        self, client, db_session, make_user, auth_headers
    ):
        """Explicit created_at values, not wall-clock gaps - see module
        docstring."""
        user = make_user()
        application = _make_application(db_session, user)
        now = datetime.now(timezone.utc)

        oldest = _make_document(
            db_session,
            application,
            file_name="a.pdf",
            created_at=now - timedelta(days=3),
        )
        newest = _make_document(
            db_session,
            application,
            file_name="c.pdf",
            created_at=now - timedelta(days=1),
        )
        middle = _make_document(
            db_session,
            application,
            file_name="b.pdf",
            created_at=now - timedelta(days=2),
        )

        response = client.get(
            _documents_url(application.id), headers=auth_headers(user)
        )

        ids_in_order = [item["id"] for item in response.json()["items"]]
        assert ids_in_order == [str(newest.id), str(middle.id), str(oldest.id)]

    def test_empty_application_returns_empty_list(
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
        assert body["page"] == 1
        assert body["page_size"] == 20


class TestListDocumentsPagination:
    def test_paginates_results(self, client, db_session, make_user, auth_headers):
        user = make_user()
        application = _make_application(db_session, user)
        now = datetime.now(timezone.utc)
        for i in range(5):
            _make_document(
                db_session,
                application,
                file_name=f"doc_{i}.pdf",
                created_at=now - timedelta(days=i),
            )

        page_1 = client.get(
            _documents_url(application.id),
            params={"page": 1, "page_size": 2},
            headers=auth_headers(user),
        )
        page_2 = client.get(
            _documents_url(application.id),
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

    def test_page_size_is_capped_at_100(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)

        response = client.get(
            _documents_url(application.id),
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
            _documents_url(application.id),
            params={"page": 0},
            headers=auth_headers(user),
        )
        assert response.status_code == 422
