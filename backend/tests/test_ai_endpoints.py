"""
Integration tests for /ai/resume-analyses and /ai/ats-scores
(app/api/v1/endpoints/ai.py).

Uses the same fixtures as the other endpoint test files (client,
db_session, make_user, auth_headers - see conftest.py).

Mocking strategy: these tests verify *dispatch*, not the pipeline (the
pipeline itself is test_ai_tasks.py's job) - parse_resume_task.delay/
score_ats_task.delay are patched so no real Celery broker is needed, and
is_ai_configured is patched to True by default (an autouse fixture) so
tests aren't accidentally exercising the 503 path unless they explicitly
want to.
"""

import uuid

import pytest

import app.api.v1.endpoints.ai as ai_endpoints_module
from app.models.application import Application, ApplicationStatus
from app.models.ats_score import AtsScore
from app.models.document import Document, DocumentType
from app.models.resume_analysis import AIJobStatus, ResumeAnalysis

RESUME_ANALYSES_URL = "/api/v1/ai/resume-analyses"
ATS_SCORES_URL = "/api/v1/ai/ats-scores"


def _make_application(db_session, user, **overrides):
    defaults = {
        "user_id": user.id,
        "company": "Acme",
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


def _make_resume_analysis(db_session, user, document, **overrides):
    defaults = {"user_id": user.id, "document_id": document.id}
    defaults.update(overrides)
    analysis = ResumeAnalysis(**defaults)
    db_session.add(analysis)
    db_session.commit()
    db_session.refresh(analysis)
    return analysis


def _make_ats_score(db_session, user, resume_analysis, **overrides):
    defaults = {"user_id": user.id, "resume_analysis_id": resume_analysis.id}
    defaults.update(overrides)
    ats_score = AtsScore(**defaults)
    db_session.add(ats_score)
    db_session.commit()
    db_session.refresh(ats_score)
    return ats_score


@pytest.fixture(autouse=True)
def ai_configured(monkeypatch):
    monkeypatch.setattr(ai_endpoints_module, "is_ai_configured", lambda: True)


@pytest.fixture(autouse=True)
def no_real_celery_dispatch(monkeypatch):
    """Every test in this file gets task dispatch stubbed out - none of
    them need a real broker, and tests that specifically care about
    dispatch happening can still inspect these via the returned mocks."""
    from unittest.mock import MagicMock

    fake_parse = MagicMock()
    fake_score = MagicMock()
    monkeypatch.setattr(ai_endpoints_module, "parse_resume_task", fake_parse)
    monkeypatch.setattr(ai_endpoints_module, "score_ats_task", fake_score)
    return {"parse_resume_task": fake_parse, "score_ats_task": fake_score}


class TestAiFeaturesRequireConfiguration:
    def test_resume_analysis_503_when_not_configured(
        self, client, db_session, make_user, auth_headers, monkeypatch
    ):
        monkeypatch.setattr(ai_endpoints_module, "is_ai_configured", lambda: False)
        user = make_user()
        application = _make_application(db_session, user)
        document = _make_document(db_session, application)

        response = client.post(
            RESUME_ANALYSES_URL,
            json={"document_id": str(document.id)},
            headers=auth_headers(user),
        )
        assert response.status_code == 503

    def test_ats_score_503_when_not_configured(
        self, client, db_session, make_user, auth_headers, monkeypatch
    ):
        monkeypatch.setattr(ai_endpoints_module, "is_ai_configured", lambda: False)
        user = make_user()
        application = _make_application(db_session, user)
        document = _make_document(db_session, application)
        analysis = _make_resume_analysis(
            db_session, user, document, status=AIJobStatus.COMPLETED
        )

        response = client.post(
            ATS_SCORES_URL,
            json={
                "resume_analysis_id": str(analysis.id),
                "job_description": "x" * 60,
            },
            headers=auth_headers(user),
        )
        assert response.status_code == 503


class TestCreateResumeAnalysis:
    def test_requires_authentication(self, client, db_session, make_user):
        user = make_user()
        application = _make_application(db_session, user)
        document = _make_document(db_session, application)
        response = client.post(
            RESUME_ANALYSES_URL, json={"document_id": str(document.id)}
        )
        assert response.status_code == 401

    def test_creates_pending_analysis_and_dispatches_task(
        self,
        client,
        db_session,
        make_user,
        auth_headers,
        no_real_celery_dispatch,
    ):
        user = make_user()
        application = _make_application(db_session, user)
        document = _make_document(db_session, application)

        response = client.post(
            RESUME_ANALYSES_URL,
            json={"document_id": str(document.id)},
            headers=auth_headers(user),
        )

        assert response.status_code == 202
        body = response.json()
        assert body["status"] == "pending"
        assert body["document_id"] == str(document.id)
        no_real_celery_dispatch["parse_resume_task"].delay.assert_called_once_with(
            body["id"]
        )

    def test_404_for_another_users_document(
        self, client, db_session, make_user, auth_headers
    ):
        owner = make_user()
        other_user = make_user()
        application = _make_application(db_session, owner)
        document = _make_document(db_session, application)

        response = client.post(
            RESUME_ANALYSES_URL,
            json={"document_id": str(document.id)},
            headers=auth_headers(other_user),
        )
        assert response.status_code == 404

    def test_404_for_nonexistent_document(self, client, make_user, auth_headers):
        user = make_user()
        response = client.post(
            RESUME_ANALYSES_URL,
            json={"document_id": str(uuid.uuid4())},
            headers=auth_headers(user),
        )
        assert response.status_code == 404

    def test_rejects_non_resume_document_type(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)
        document = _make_document(
            db_session, application, file_type=DocumentType.COVER_LETTER
        )

        response = client.post(
            RESUME_ANALYSES_URL,
            json={"document_id": str(document.id)},
            headers=auth_headers(user),
        )
        assert response.status_code == 422

    def test_reuses_existing_pending_analysis(
        self,
        client,
        db_session,
        make_user,
        auth_headers,
        no_real_celery_dispatch,
    ):
        user = make_user()
        application = _make_application(db_session, user)
        document = _make_document(db_session, application)
        existing = _make_resume_analysis(db_session, user, document)

        response = client.post(
            RESUME_ANALYSES_URL,
            json={"document_id": str(document.id)},
            headers=auth_headers(user),
        )

        assert response.status_code == 202
        assert response.json()["id"] == str(existing.id)
        no_real_celery_dispatch["parse_resume_task"].delay.assert_not_called()


class TestGetAndListResumeAnalyses:
    def test_get_requires_ownership(self, client, db_session, make_user, auth_headers):
        owner = make_user()
        other_user = make_user()
        application = _make_application(db_session, owner)
        document = _make_document(db_session, application)
        analysis = _make_resume_analysis(db_session, owner, document)

        response = client.get(
            f"{RESUME_ANALYSES_URL}/{analysis.id}", headers=auth_headers(other_user)
        )
        assert response.status_code == 404

    def test_get_returns_owned_analysis(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)
        document = _make_document(db_session, application)
        analysis = _make_resume_analysis(db_session, user, document)

        response = client.get(
            f"{RESUME_ANALYSES_URL}/{analysis.id}", headers=auth_headers(user)
        )
        assert response.status_code == 200
        assert response.json()["id"] == str(analysis.id)

    def test_list_only_returns_own_analyses(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        other_user = make_user()
        application = _make_application(db_session, user)
        document = _make_document(db_session, application)
        other_application = _make_application(db_session, other_user)
        other_document = _make_document(db_session, other_application)
        _make_resume_analysis(db_session, user, document)
        _make_resume_analysis(db_session, other_user, other_document)

        response = client.get(RESUME_ANALYSES_URL, headers=auth_headers(user))
        assert response.status_code == 200
        body = response.json()
        assert body["total"] == 1


class TestCreateAtsScore:
    def test_requires_authentication(self, client, db_session, make_user):
        user = make_user()
        application = _make_application(db_session, user)
        document = _make_document(db_session, application)
        analysis = _make_resume_analysis(
            db_session, user, document, status=AIJobStatus.COMPLETED
        )
        response = client.post(
            ATS_SCORES_URL,
            json={
                "resume_analysis_id": str(analysis.id),
                "job_description": "x" * 60,
            },
        )
        assert response.status_code == 401

    def test_creates_pending_score_with_pasted_description(
        self,
        client,
        db_session,
        make_user,
        auth_headers,
        no_real_celery_dispatch,
    ):
        user = make_user()
        application = _make_application(db_session, user)
        document = _make_document(db_session, application)
        analysis = _make_resume_analysis(
            db_session, user, document, status=AIJobStatus.COMPLETED
        )

        response = client.post(
            ATS_SCORES_URL,
            json={
                "resume_analysis_id": str(analysis.id),
                "job_description": "x" * 60,
            },
            headers=auth_headers(user),
        )

        assert response.status_code == 202
        body = response.json()
        assert body["status"] == "pending"
        assert body["job_description_source"] == "pasted"
        no_real_celery_dispatch["score_ats_task"].delay.assert_called_once_with(
            body["id"]
        )

    def test_creates_pending_score_from_application_job_url(
        self,
        client,
        db_session,
        make_user,
        auth_headers,
        no_real_celery_dispatch,
    ):
        user = make_user()
        application = _make_application(
            db_session, user, job_url="https://jobs.example.com/posting"
        )
        document = _make_document(db_session, application)
        analysis = _make_resume_analysis(
            db_session, user, document, status=AIJobStatus.COMPLETED
        )

        response = client.post(
            ATS_SCORES_URL,
            json={
                "resume_analysis_id": str(analysis.id),
                "application_id": str(application.id),
            },
            headers=auth_headers(user),
        )

        assert response.status_code == 202
        body = response.json()
        assert body["job_description"] is None
        assert body["job_description_source"] is None

    def test_pasted_description_wins_over_job_url(
        self,
        client,
        db_session,
        make_user,
        auth_headers,
        no_real_celery_dispatch,
    ):
        user = make_user()
        application = _make_application(
            db_session, user, job_url="https://jobs.example.com/posting"
        )
        document = _make_document(db_session, application)
        analysis = _make_resume_analysis(
            db_session, user, document, status=AIJobStatus.COMPLETED
        )

        response = client.post(
            ATS_SCORES_URL,
            json={
                "resume_analysis_id": str(analysis.id),
                "application_id": str(application.id),
                "job_description": "y" * 60,
            },
            headers=auth_headers(user),
        )

        assert response.status_code == 202
        body = response.json()
        assert body["job_description"] == "y" * 60
        assert body["job_description_source"] == "pasted"

    def test_422_when_no_job_description_source_available(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user, job_url=None)
        document = _make_document(db_session, application)
        analysis = _make_resume_analysis(
            db_session, user, document, status=AIJobStatus.COMPLETED
        )

        response = client.post(
            ATS_SCORES_URL,
            json={
                "resume_analysis_id": str(analysis.id),
                "application_id": str(application.id),
            },
            headers=auth_headers(user),
        )
        assert response.status_code == 422

    def test_422_with_no_application_and_no_job_description(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)
        document = _make_document(db_session, application)
        analysis = _make_resume_analysis(
            db_session, user, document, status=AIJobStatus.COMPLETED
        )

        response = client.post(
            ATS_SCORES_URL,
            json={"resume_analysis_id": str(analysis.id)},
            headers=auth_headers(user),
        )
        assert response.status_code == 422

    def test_409_when_resume_analysis_not_completed(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)
        document = _make_document(db_session, application)
        analysis = _make_resume_analysis(
            db_session, user, document, status=AIJobStatus.PENDING
        )

        response = client.post(
            ATS_SCORES_URL,
            json={
                "resume_analysis_id": str(analysis.id),
                "job_description": "x" * 60,
            },
            headers=auth_headers(user),
        )
        assert response.status_code == 409

    def test_404_for_another_users_resume_analysis(
        self, client, db_session, make_user, auth_headers
    ):
        owner = make_user()
        other_user = make_user()
        application = _make_application(db_session, owner)
        document = _make_document(db_session, application)
        analysis = _make_resume_analysis(
            db_session, owner, document, status=AIJobStatus.COMPLETED
        )

        response = client.post(
            ATS_SCORES_URL,
            json={
                "resume_analysis_id": str(analysis.id),
                "job_description": "x" * 60,
            },
            headers=auth_headers(other_user),
        )
        assert response.status_code == 404

    def test_404_for_another_users_application(
        self, client, db_session, make_user, auth_headers
    ):
        owner = make_user()
        other_user = make_user()
        application = _make_application(db_session, owner)
        document = _make_document(db_session, application)
        analysis = _make_resume_analysis(
            db_session, owner, document, status=AIJobStatus.COMPLETED
        )
        other_application = _make_application(db_session, other_user)

        response = client.post(
            ATS_SCORES_URL,
            json={
                "resume_analysis_id": str(analysis.id),
                "application_id": str(other_application.id),
                "job_description": "x" * 60,
            },
            headers=auth_headers(other_user),
        )
        # owner's resume analysis isn't visible to other_user regardless
        assert response.status_code == 404

    def test_job_description_too_short_is_rejected(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application = _make_application(db_session, user)
        document = _make_document(db_session, application)
        analysis = _make_resume_analysis(
            db_session, user, document, status=AIJobStatus.COMPLETED
        )

        response = client.post(
            ATS_SCORES_URL,
            json={"resume_analysis_id": str(analysis.id), "job_description": "short"},
            headers=auth_headers(user),
        )
        assert response.status_code == 422


class TestGetAndListAtsScores:
    def test_get_requires_ownership(self, client, db_session, make_user, auth_headers):
        owner = make_user()
        other_user = make_user()
        application = _make_application(db_session, owner)
        document = _make_document(db_session, application)
        analysis = _make_resume_analysis(
            db_session, owner, document, status=AIJobStatus.COMPLETED
        )
        ats_score = _make_ats_score(
            db_session, owner, analysis, job_description="x" * 60
        )

        response = client.get(
            f"{ATS_SCORES_URL}/{ats_score.id}", headers=auth_headers(other_user)
        )
        assert response.status_code == 404

    def test_list_filters_by_application_id(
        self, client, db_session, make_user, auth_headers
    ):
        user = make_user()
        application_a = _make_application(db_session, user, company="A")
        application_b = _make_application(db_session, user, company="B")
        document = _make_document(db_session, application_a)
        analysis = _make_resume_analysis(
            db_session, user, document, status=AIJobStatus.COMPLETED
        )
        _make_ats_score(
            db_session,
            user,
            analysis,
            application_id=application_a.id,
            job_description="x" * 60,
        )
        _make_ats_score(
            db_session,
            user,
            analysis,
            application_id=application_b.id,
            job_description="y" * 60,
        )

        response = client.get(
            ATS_SCORES_URL,
            params={"application_id": str(application_a.id)},
            headers=auth_headers(user),
        )
        assert response.status_code == 200
        body = response.json()
        assert body["total"] == 1
        assert body["items"][0]["application_id"] == str(application_a.id)
