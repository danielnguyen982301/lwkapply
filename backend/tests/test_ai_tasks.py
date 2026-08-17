"""
Integration tests for app.tasks.ai (parse_resume_task, score_ats_task).

Celery tasks are plain callables - these call them directly rather than
through the broker, same approach the plan called for since there's no
existing precedent in this codebase for testing a task that opens its
own SessionLocal() (app/tasks/reminders.py's send_due_reminders has no
test coverage yet either - see TODO.md).

The tricky part: SessionLocal() normally opens a brand-new connection to
settings.DATABASE_URL, which would (a) miss whatever this test's
db_session fixture already inserted (different connection, different
transaction) and (b) not roll back at teardown. patch_ai_tasks_session
below fixes this by monkeypatching app.tasks.ai.SessionLocal to a
sessionmaker bound to the *same* connection db_session uses, with
join_transaction_mode="create_savepoint" (SQLAlchemy 2.0) so the task's
own db.commit() calls become SAVEPOINT release/restart rather than
committing (or breaking) db_session's outer transaction - the same
end result conftest.py's after_transaction_end listener achieves for
db_session itself, just via SQLAlchemy's built-in mechanism for a
second, independent Session on the same connection.

Mocking strategy: download_document/extract_text/parse_resume/
score_resume_against_job/fetch_job_description are all imported by name
into app.tasks.ai's own namespace, so they're patched there (not in
their defining modules) - same "resolved through the calling module's
own globals" reasoning documented in test_documents_endpoints.py.
"""

import uuid
from datetime import datetime, timezone

import pytest
from sqlalchemy.orm import sessionmaker

import app.tasks.ai as ai_tasks_module
from app.models.ats_score import AtsScore
from app.models.document import Document, DocumentType
from app.models.resume_analysis import AIJobStatus, ResumeAnalysis
from app.schemas.ai import AtsScoreResult, ParsedResume
from app.services.ai.resume_parser import UnsupportedResumeFormatError
from app.tasks.ai import _generate_analysis_name, parse_resume_task, score_ats_task


@pytest.fixture()
def patch_ai_tasks_session(monkeypatch, db_session):
    connection = db_session.connection()
    task_session_factory = sessionmaker(
        bind=connection, join_transaction_mode="create_savepoint"
    )
    monkeypatch.setattr(ai_tasks_module, "SessionLocal", task_session_factory)
    return task_session_factory


def _make_user(db_session):
    from app.core.security import hash_password
    from app.models.user import User

    user = User(
        email=f"{uuid.uuid4()}@example.com",
        password_hash=hash_password("correct-horse-battery-staple"),
        first_name="Test",
        last_name="User",
    )
    db_session.add(user)
    db_session.commit()
    db_session.refresh(user)
    return user


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


class TestGenerateAnalysisName:
    def test_combines_slugified_filename_and_timestamp(self):
        completed_at = datetime(2026, 8, 17, 14, 32, 5, tzinfo=timezone.utc)
        name = _generate_analysis_name("My Resume (v2).pdf", completed_at)
        assert name.startswith("my_resume_v2_20260817_143205_")

    def test_falls_back_to_resume_for_unnamed_or_unslugifiable_file(self):
        completed_at = datetime(2026, 8, 17, 14, 32, 5, tzinfo=timezone.utc)
        assert _generate_analysis_name("", completed_at).startswith(
            "resume_20260817_143205_"
        )
        assert _generate_analysis_name("***.pdf", completed_at).startswith(
            "resume_20260817_143205_"
        )

    def test_is_unique_across_calls_with_the_same_inputs(self):
        completed_at = datetime(2026, 8, 17, 14, 32, 5, tzinfo=timezone.utc)
        names = {_generate_analysis_name("resume.pdf", completed_at) for _ in range(20)}
        assert len(names) == 20


class TestParseResumeTask:
    def test_success_path_populates_parsed_data(
        self, db_session, patch_ai_tasks_session, monkeypatch
    ):
        user = _make_user(db_session)
        document = _make_document(db_session, user)
        analysis = _make_resume_analysis(db_session, user, document)

        parsed = ParsedResume(
            full_name="Jane Doe",
            email="jane@example.com",
            phone=None,
            summary=None,
            skills=["Python"],
            work_experience=[],
            education=[],
            total_years_experience=None,
        )
        monkeypatch.setattr(
            ai_tasks_module, "download_document", lambda key: b"fake bytes"
        )
        monkeypatch.setattr(
            ai_tasks_module, "extract_text", lambda file_bytes, name: "resume text"
        )
        monkeypatch.setattr(ai_tasks_module, "parse_resume", lambda text: parsed)

        parse_resume_task(str(analysis.id))

        db_session.refresh(analysis)
        assert analysis.status == AIJobStatus.COMPLETED
        assert analysis.raw_text == "resume text"
        assert analysis.parsed_data is not None
        assert analysis.parsed_data["full_name"] == "Jane Doe"
        assert analysis.error_message is None
        assert analysis.completed_at is not None
        assert analysis.analysis_name is not None
        assert analysis.analysis_name.startswith("resume_")

    def test_unsupported_format_marks_failed_with_clear_message(
        self, db_session, patch_ai_tasks_session, monkeypatch
    ):
        user = _make_user(db_session)
        document = _make_document(db_session, user, file_name="resume.doc")
        analysis = _make_resume_analysis(db_session, user, document)

        monkeypatch.setattr(
            ai_tasks_module, "download_document", lambda key: b"fake bytes"
        )

        def _raise_unsupported(file_bytes, name):
            raise UnsupportedResumeFormatError("please re-upload as PDF or DOCX")

        monkeypatch.setattr(ai_tasks_module, "extract_text", _raise_unsupported)

        parse_resume_task(str(analysis.id))

        db_session.refresh(analysis)
        assert analysis.status == AIJobStatus.FAILED
        assert analysis.error_message is not None
        assert "PDF or DOCX" in analysis.error_message
        assert analysis.completed_at is None
        assert analysis.analysis_name is None

    def test_unexpected_error_marks_failed_generically(
        self, db_session, patch_ai_tasks_session, monkeypatch
    ):
        user = _make_user(db_session)
        document = _make_document(db_session, user)
        analysis = _make_resume_analysis(db_session, user, document)

        def _raise(key):
            raise RuntimeError("R2 is down")

        monkeypatch.setattr(ai_tasks_module, "download_document", _raise)

        parse_resume_task(str(analysis.id))

        db_session.refresh(analysis)
        assert analysis.status == AIJobStatus.FAILED
        assert analysis.error_message == "Resume parsing failed. Please try again."
        assert analysis.analysis_name is None


class TestScoreAtsTask:
    def test_pasted_job_description_skips_fetcher(
        self, db_session, patch_ai_tasks_session, monkeypatch
    ):
        user = _make_user(db_session)
        document = _make_document(db_session, user)
        analysis = _make_resume_analysis(
            db_session,
            user,
            document,
            status=AIJobStatus.COMPLETED,
            raw_text="resume text",
        )
        ats_score = _make_ats_score(
            db_session,
            user,
            analysis,
            job_description="x" * 60,
            job_description_source="pasted",
        )

        fetcher_called = {"called": False}

        def _fetcher_should_not_run(url):
            fetcher_called["called"] = True
            return "should not be used"

        result = AtsScoreResult(
            score=80,
            summary="Good match",
            matched_keywords=["Python"],
            missing_keywords=[],
            suggestions=[],
        )
        monkeypatch.setattr(
            ai_tasks_module, "fetch_job_description", _fetcher_should_not_run
        )
        monkeypatch.setattr(
            ai_tasks_module, "score_resume_against_job", lambda text, jd: result
        )

        score_ats_task(str(ats_score.id))

        db_session.refresh(ats_score)
        assert fetcher_called["called"] is False
        assert ats_score.status == AIJobStatus.COMPLETED
        assert ats_score.score == 80
        assert ats_score.job_description_source == "pasted"
        assert ats_score.scored_at is not None

    def test_job_url_fetch_success_backfills_job_description(
        self, db_session, patch_ai_tasks_session, monkeypatch
    ):
        user = _make_user(db_session)
        document = _make_document(db_session, user)
        analysis = _make_resume_analysis(
            db_session,
            user,
            document,
            status=AIJobStatus.COMPLETED,
            raw_text="resume text",
        )
        ats_score = _make_ats_score(
            db_session,
            user,
            analysis,
            job_description_source="url",
            job_url="https://jobs.example.com/posting/123",
        )

        result = AtsScoreResult(
            score=55,
            summary="Partial match",
            matched_keywords=[],
            missing_keywords=["Kubernetes"],
            suggestions=["Add Kubernetes experience"],
        )
        monkeypatch.setattr(
            ai_tasks_module,
            "fetch_job_description",
            lambda url: "fetched job description text",
        )
        monkeypatch.setattr(
            ai_tasks_module, "score_resume_against_job", lambda text, jd: result
        )

        score_ats_task(str(ats_score.id))

        db_session.refresh(ats_score)
        assert ats_score.status == AIJobStatus.COMPLETED
        assert ats_score.job_description == "fetched job description text"
        assert ats_score.job_description_source == "url"
        assert ats_score.score == 55

    def test_job_url_fetch_failure_marks_failed_with_resubmit_message(
        self, db_session, patch_ai_tasks_session, monkeypatch
    ):
        user = _make_user(db_session)
        document = _make_document(db_session, user)
        analysis = _make_resume_analysis(
            db_session,
            user,
            document,
            status=AIJobStatus.COMPLETED,
            raw_text="resume text",
        )
        ats_score = _make_ats_score(
            db_session,
            user,
            analysis,
            job_description_source="url",
            job_url="https://jobs.example.com/blocked",
        )

        monkeypatch.setattr(ai_tasks_module, "fetch_job_description", lambda url: None)

        score_ats_task(str(ats_score.id))

        db_session.refresh(ats_score)
        assert ats_score.status == AIJobStatus.FAILED
        assert ats_score.error_message is not None
        assert "resubmit" in ats_score.error_message.lower()
        assert ats_score.job_description is None
        assert ats_score.scored_at is None

    def test_gemini_failure_marks_failed_generically(
        self, db_session, patch_ai_tasks_session, monkeypatch
    ):
        user = _make_user(db_session)
        document = _make_document(db_session, user)
        analysis = _make_resume_analysis(
            db_session,
            user,
            document,
            status=AIJobStatus.COMPLETED,
            raw_text="resume text",
        )
        ats_score = _make_ats_score(
            db_session, user, analysis, job_description="x" * 60
        )

        def _raise(text, jd):
            raise RuntimeError("Gemini call failed")

        monkeypatch.setattr(ai_tasks_module, "score_resume_against_job", _raise)

        score_ats_task(str(ats_score.id))

        db_session.refresh(ats_score)
        assert ats_score.status == AIJobStatus.FAILED
        assert ats_score.error_message == "ATS scoring failed. Please try again."
        assert ats_score.scored_at is None
