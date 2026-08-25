"""
Integration tests for app.tasks.ai_inline (process_resume_analysis,
process_ats_score) - the in-process equivalent of
app.tasks.ai_celery.parse_resume_task / score_ats_task, covered by
test_ai_celery_tasks.py. Same pipeline, same mocking strategy - see that
file's module docstring for the SessionLocal-patching and
patched-in-the-calling-module's-namespace reasoning, both of which apply
identically here.
"""

import uuid
from datetime import datetime, timezone

import pytest
from sqlalchemy.orm import sessionmaker

import app.tasks.ai_inline as ai_inline_module
from app.models.ats_score import AtsScore
from app.models.document import Document, DocumentType
from app.models.resume_analysis import AIJobStatus, ResumeAnalysis
from app.schemas.ai import AtsScoreResult, ParsedResume
from app.services.ai.resume_parser import UnsupportedResumeFormatError
from app.tasks.ai_inline import (
    _generate_analysis_name,
    process_ats_score,
    process_resume_analysis,
)


@pytest.fixture()
def patch_ai_inline_session(monkeypatch, db_session):
    connection = db_session.connection()
    task_session_factory = sessionmaker(
        bind=connection, join_transaction_mode="create_savepoint"
    )
    monkeypatch.setattr(ai_inline_module, "SessionLocal", task_session_factory)
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


class TestProcessResumeAnalysis:
    def test_success_path_populates_parsed_data(
        self, db_session, patch_ai_inline_session, monkeypatch
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
            ai_inline_module, "download_document", lambda key: b"fake bytes"
        )
        monkeypatch.setattr(
            ai_inline_module, "extract_text", lambda file_bytes, name: "resume text"
        )
        monkeypatch.setattr(ai_inline_module, "parse_resume", lambda text: parsed)

        process_resume_analysis(str(analysis.id))

        db_session.refresh(analysis)
        assert analysis.status == AIJobStatus.COMPLETED
        assert analysis.raw_text == "resume text"
        assert analysis.parsed_data is not None
        assert analysis.parsed_data["full_name"] == "Jane Doe"
        assert analysis.completed_at is not None
        assert analysis.analysis_name is not None

    def test_unsupported_format_marks_failed_with_clear_message(
        self, db_session, patch_ai_inline_session, monkeypatch
    ):
        user = _make_user(db_session)
        document = _make_document(db_session, user, file_name="resume.doc")
        analysis = _make_resume_analysis(db_session, user, document)

        monkeypatch.setattr(
            ai_inline_module, "download_document", lambda key: b"fake bytes"
        )

        def _raise_unsupported(file_bytes, name):
            raise UnsupportedResumeFormatError("please re-upload as PDF or DOCX")

        monkeypatch.setattr(ai_inline_module, "extract_text", _raise_unsupported)

        process_resume_analysis(str(analysis.id))

        db_session.refresh(analysis)
        assert analysis.status == AIJobStatus.FAILED
        assert "PDF or DOCX" in analysis.error_message

    def test_unexpected_error_marks_failed_generically(
        self, db_session, patch_ai_inline_session, monkeypatch
    ):
        user = _make_user(db_session)
        document = _make_document(db_session, user)
        analysis = _make_resume_analysis(db_session, user, document)

        def _raise(key):
            raise RuntimeError("R2 is down")

        monkeypatch.setattr(ai_inline_module, "download_document", _raise)

        process_resume_analysis(str(analysis.id))

        db_session.refresh(analysis)
        assert analysis.status == AIJobStatus.FAILED
        assert analysis.error_message == "Resume parsing failed. Please try again."


class TestProcessAtsScore:
    def test_pasted_job_description_skips_fetcher(
        self, db_session, patch_ai_inline_session, monkeypatch
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
            ai_inline_module, "fetch_job_description", _fetcher_should_not_run
        )
        monkeypatch.setattr(
            ai_inline_module, "score_resume_against_job", lambda text, jd: result
        )

        process_ats_score(str(ats_score.id))

        db_session.refresh(ats_score)
        assert fetcher_called["called"] is False
        assert ats_score.status == AIJobStatus.COMPLETED
        assert ats_score.score == 80

    def test_job_url_fetch_failure_marks_failed_with_resubmit_message(
        self, db_session, patch_ai_inline_session, monkeypatch
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

        monkeypatch.setattr(ai_inline_module, "fetch_job_description", lambda url: None)

        process_ats_score(str(ats_score.id))

        db_session.refresh(ats_score)
        assert ats_score.status == AIJobStatus.FAILED
        assert "resubmit" in ats_score.error_message.lower()

    def test_gemini_failure_marks_failed_generically(
        self, db_session, patch_ai_inline_session, monkeypatch
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

        monkeypatch.setattr(ai_inline_module, "score_resume_against_job", _raise)

        process_ats_score(str(ats_score.id))

        db_session.refresh(ats_score)
        assert ats_score.status == AIJobStatus.FAILED
        assert ats_score.error_message == "ATS scoring failed. Please try again."
