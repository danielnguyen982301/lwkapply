"""
Unit tests for app.services.ai.ats_scorer. Mocks call_structured (the
Gemini boundary), same convention as test_resume_parser.py.
"""

import app.services.ai.ats_scorer as ats_scorer_module
from app.schemas.ai import AtsScoreResult
from app.services.ai.ats_scorer import score_resume_against_job


class TestScoreResumeAgainstJob:
    def test_calls_call_structured_with_ats_score_result_schema(self, monkeypatch):
        expected = AtsScoreResult(
            score=72,
            summary="Decent match",
            matched_keywords=["Python"],
            missing_keywords=["Kubernetes"],
            suggestions=["Add container orchestration experience"],
        )
        captured = {}

        def _fake_call_structured(system_instruction, user_prompt, schema):
            captured["schema"] = schema
            captured["user_prompt"] = user_prompt
            return expected

        monkeypatch.setattr(ats_scorer_module, "call_structured", _fake_call_structured)

        result = score_resume_against_job("resume text here", "job description here")

        assert result is expected
        assert captured["schema"] is AtsScoreResult
        assert "resume text here" in captured["user_prompt"]
        assert "job description here" in captured["user_prompt"]
