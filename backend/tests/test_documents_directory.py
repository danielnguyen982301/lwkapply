"""
Integration tests for GET /documents
(app/api/v1/endpoints/documents.py :: directory_router).

Mirrors test_interviews_directory.py / test_contacts_directory.py's shape
and reasoning: this route is deliberately not nested under
/applications/{id} - it's a flat, cross-application listing scoped only by
Application.user_id via a join. That means there's no application_id in
the URL to accidentally scope by, which makes the ownership/IDOR check the
single most important thing this file verifies.

Where this diverges from the other two directories: Document has both a
name-like field (file_name, like Contacts' `search`) and an enum field
(file_type, like Interviews' `result`), so this suite covers both filters
and their own IDOR variants. Ordering is `created_at` descending, matching
the nested GET /applications/{id}/documents route (and Contacts'
directory, not Interviews').

Rows are inserted directly via the ORM rather than through the real
multipart upload endpoint - these tests are about the directory read path,
not the R2 upload flow, which is already covered by
test_documents_endpoints.py.
"""

from datetime import datetime, timedelta, timezone

from app.models.application import Application, ApplicationStatus
from app.models.document import Document, DocumentType

DOCUMENTS_URL = "/api/v1/documents"


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
        "file_url": "documents/some-object-key.pdf",
        "file_type": DocumentType.RESUME,
    }
    defaults.update(overrides)
    document = Document(**defaults)
    db_session.add(document)
    db_session.commit()
    db_session.refresh(document)
    return document


class TestDocumentsDirectoryAuth:
    def test_requires_authentication(self, client):
        response = client.get(DOCUMENTS_URL)
        assert response.status_code == 401

    def test_rejects_invalid_token(self, client):
        response = client.get(
            DOCUMENTS_URL, headers={"Authorization": "Bearer not-a-real-token"}
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
            DOCUMENTS_URL, headers={"Authorization": f"Bearer {token}"}
        )
        assert response.status_code == 401


class TestDocumentsDirectoryAggregation:
    def test_aggregates_documents_across_applications(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        app_a = _make_application(db_session, user, company="Initech")
        app_b = _make_application(db_session, user, company="Globex")
        _make_document(db_session, app_a, file_name="initech_resume.pdf")
        _make_document(db_session, app_b, file_name="globex_resume.pdf")

        response = client.get(DOCUMENTS_URL, headers=auth_headers(user))

        assert response.status_code == 200
        body = response.json()
        assert body["total"] == 2
        names = {item["file_name"] for item in body["items"]}
        assert names == {"initech_resume.pdf", "globex_resume.pdf"}
        companies = {item["application"]["company"] for item in body["items"]}
        assert companies == {"Initech", "Globex"}

    def test_embeds_correct_parent_application_per_document(
        self, client, db_session, make_user, auth_headers
    ):
        """Guards the contains_eager() join specifically: each document
        must be paired with its own application, not e.g. the last
        application row seen during the join."""
        user = make_user()
        app_a = _make_application(db_session, user, company="Initech")
        app_b = _make_application(db_session, user, company="Globex")
        document_a = _make_document(db_session, app_a)
        document_b = _make_document(db_session, app_b)

        response = client.get(DOCUMENTS_URL, headers=auth_headers(user))

        by_id = {item["id"]: item for item in response.json()["items"]}
        assert by_id[str(document_a.id)]["application"]["company"] == "Initech"
        assert by_id[str(document_b.id)]["application"]["company"] == "Globex"

    def test_never_returns_raw_file_url(
        self, client, db_session, make_user, auth_headers
    ):
        """Same contract as DocumentRead on the nested routes: the
        permanent R2 object key must never leak through this response
        either, even though this is a different schema
        (DocumentWithApplicationRead)."""
        user = make_user()
        application = _make_application(db_session, user)
        _make_document(db_session, application)

        response = client.get(DOCUMENTS_URL, headers=auth_headers(user))

        body = response.json()["items"][0]
        assert "file_url" not in body

    def test_empty_when_user_has_no_documents(self, client, make_user, auth_headers):
        user = make_user()
        response = client.get(DOCUMENTS_URL, headers=auth_headers(user))
        assert response.status_code == 200
        body = response.json()
        assert body["items"] == []
        assert body["total"] == 0

    def test_ordered_by_created_at_descending(
        self, client, db_session, make_user, auth_headers
    ):
        """created_at comes from TimestampMixin's server_default=func.now(),
        and every insert in this test shares one real outer transaction
        under the SAVEPOINT isolation strategy (see conftest.py) - Postgres's
        now() is transaction-scoped, so two inserts separated only by
        wall-clock time can still land on the exact same created_at value.
        Set it explicitly instead, the same fix already applied to
        test_applications_endpoints.py's ordering test."""
        user = make_user()
        application = _make_application(db_session, user)
        now = datetime.now(timezone.utc)
        older = _make_document(
            db_session,
            application,
            file_name="older.pdf",
            created_at=now - timedelta(days=1),
        )
        newer = _make_document(
            db_session, application, file_name="newer.pdf", created_at=now
        )

        response = client.get(DOCUMENTS_URL, headers=auth_headers(user))

        ids_in_order = [item["id"] for item in response.json()["items"]]
        assert ids_in_order == [str(newer.id), str(older.id)]


class TestDocumentsDirectoryOwnership:
    def test_user_cannot_see_another_users_documents(
        self, client, db_session, make_user, auth_headers
    ):
        """The critical IDOR check flagged for the Contacts/Interviews
        directories applies identically here: this route has no
        application_id path param, so the Application.user_id join/filter
        is the *only* thing standing between one user and every other
        user's documents."""
        owner = make_user()
        other_user = make_user()

        owner_app = _make_application(db_session, owner, company="Initech")
        _make_document(db_session, owner_app)

        other_app = _make_application(db_session, other_user, company="Umbrella Corp")
        other_document = _make_document(db_session, other_app)

        response = client.get(DOCUMENTS_URL, headers=auth_headers(other_user))

        assert response.status_code == 200
        body = response.json()
        assert body["total"] == 1
        assert body["items"][0]["id"] == str(other_document.id)

    def test_search_cannot_be_used_to_find_another_users_documents(
        self, client, db_session, make_user, auth_headers
    ):
        owner = make_user()
        other_user = make_user()

        owner_app = _make_application(db_session, owner, company="Initech")
        _make_document(db_session, owner_app, file_name="shared_name.pdf")

        other_app = _make_application(db_session, other_user, company="Globex")
        _make_document(db_session, other_app, file_name="unrelated.pdf")

        response = client.get(
            DOCUMENTS_URL,
            params={"search": "shared_name"},
            headers=auth_headers(other_user),
        )

        assert response.status_code == 200
        body = response.json()
        assert body["total"] == 0
        assert body["items"] == []

    def test_file_type_filter_cannot_be_used_to_find_another_users_documents(
        self, client, db_session, make_user, auth_headers
    ):
        owner = make_user()
        other_user = make_user()

        owner_app = _make_application(db_session, owner, company="Initech")
        _make_document(db_session, owner_app, file_type=DocumentType.RESUME)

        other_app = _make_application(db_session, other_user, company="Globex")
        _make_document(db_session, other_app, file_type=DocumentType.COVER_LETTER)

        response = client.get(
            DOCUMENTS_URL,
            params={"file_type": "resume"},
            headers=auth_headers(other_user),
        )

        assert response.status_code == 200
        body = response.json()
        assert body["total"] == 0
        assert body["items"] == []


class TestDocumentsDirectorySearch:
    def test_filters_by_file_name(self, client, db_session, make_user, auth_headers):
        user = make_user()
        application = _make_application(db_session, user)
        _make_document(db_session, application, file_name="cover_letter_v2.pdf")
        _make_document(db_session, application, file_name="resume_final.pdf")

        response = client.get(
            DOCUMENTS_URL,
            params={"search": "cover_letter"},
            headers=auth_headers(user),
        )

        assert response.status_code == 200
        body = response.json()
        assert body["total"] == 1
        assert body["items"][0]["file_name"] == "cover_letter_v2.pdf"

    def test_filters_by_application_company(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        app_a = _make_application(db_session, user, company="Initech")
        app_b = _make_application(db_session, user, company="Globex")
        _make_document(db_session, app_a, file_name="resume.pdf")
        _make_document(db_session, app_b, file_name="resume.pdf")

        response = client.get(
            DOCUMENTS_URL, params={"search": "Initech"}, headers=auth_headers(user)
        )

        assert response.status_code == 200
        body = response.json()
        assert body["total"] == 1
        assert body["items"][0]["application"]["company"] == "Initech"

    def test_no_search_returns_all_documents(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)
        _make_document(db_session, application, file_name="a.pdf")
        _make_document(db_session, application, file_name="b.pdf")

        response = client.get(DOCUMENTS_URL, headers=auth_headers(user))

        assert response.status_code == 200
        assert response.json()["total"] == 2


class TestDocumentsDirectoryFileTypeFilter:
    def test_filters_by_file_type(self, client, db_session, make_user, auth_headers):
        user = make_user()
        application = _make_application(db_session, user)
        _make_document(db_session, application, file_type=DocumentType.RESUME)
        _make_document(db_session, application, file_type=DocumentType.COVER_LETTER)

        response = client.get(
            DOCUMENTS_URL, params={"file_type": "resume"}, headers=auth_headers(user)
        )

        assert response.status_code == 200
        body = response.json()
        assert body["total"] == 1
        assert body["items"][0]["file_type"] == "resume"

    def test_invalid_file_type_value_is_rejected(self, client, make_user, auth_headers):
        user = make_user()
        response = client.get(
            DOCUMENTS_URL,
            params={"file_type": "not-a-real-type"},
            headers=auth_headers(user),
        )
        assert response.status_code == 422

    def test_no_filter_returns_all_file_types(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)
        _make_document(db_session, application, file_type=DocumentType.RESUME)
        _make_document(db_session, application, file_type=DocumentType.COVER_LETTER)

        response = client.get(DOCUMENTS_URL, headers=auth_headers(user))

        assert response.status_code == 200
        assert response.json()["total"] == 2

    def test_search_and_file_type_combine(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)
        _make_document(
            db_session,
            application,
            file_name="cover_letter_v1.pdf",
            file_type=DocumentType.COVER_LETTER,
        )
        _make_document(
            db_session,
            application,
            file_name="cover_letter_old.pdf",
            file_type=DocumentType.OTHER,
        )

        response = client.get(
            DOCUMENTS_URL,
            params={"search": "cover_letter", "file_type": "cover_letter"},
            headers=auth_headers(user),
        )

        assert response.status_code == 200
        body = response.json()
        assert body["total"] == 1
        assert body["items"][0]["file_name"] == "cover_letter_v1.pdf"


class TestDocumentsDirectoryPagination:
    def test_paginates_results(self, client, db_session, make_user, auth_headers):
        user = make_user()
        application = _make_application(db_session, user)
        for i in range(5):
            _make_document(db_session, application, file_name=f"doc_{i}.pdf")

        page_1 = client.get(
            DOCUMENTS_URL,
            params={"page": 1, "page_size": 2},
            headers=auth_headers(user),
        )
        page_2 = client.get(
            DOCUMENTS_URL,
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
            DOCUMENTS_URL, params={"page_size": 500}, headers=auth_headers(user)
        )
        assert response.status_code == 422

    def test_page_below_one_is_rejected(self, client, make_user, auth_headers):
        user = make_user()
        response = client.get(
            DOCUMENTS_URL, params={"page": 0}, headers=auth_headers(user)
        )
        assert response.status_code == 422
