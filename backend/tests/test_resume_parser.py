"""
Unit tests for app.services.ai.resume_parser.

extract_text() is tested against real pypdf/python-docx output (no
mocking needed - these are pure local libraries, not a network
boundary). parse_resume() mocks call_structured (the Gemini boundary),
same convention as test_ai_client.py.
"""

import io

import docx
import pytest
from pypdf import PdfWriter

import app.services.ai.resume_parser as resume_parser_module
from app.schemas.ai import ParsedResume
from app.services.ai.resume_parser import (
    UnsupportedResumeFormatError,
    extract_text,
    parse_resume,
)


def _make_pdf_bytes(text: str) -> bytes:
    writer = PdfWriter()
    writer.add_blank_page(width=612, height=792)
    buf = io.BytesIO()
    writer.write(buf)
    return buf.getvalue()


def _make_docx_bytes(text: str) -> bytes:
    document = docx.Document()
    document.add_paragraph(text)
    buf = io.BytesIO()
    document.save(buf)
    return buf.getvalue()


class TestExtractText:
    def test_extracts_docx_text(self):
        file_bytes = _make_docx_bytes("Jane Doe - Senior Engineer")
        text = extract_text(file_bytes, "resume.docx")
        assert "Jane Doe - Senior Engineer" in text

    def test_extracts_pdf_without_error(self):
        # A blank PDF page still exercises the real pypdf extraction path
        # (returns empty string rather than raising) - the point here is
        # confirming the .pdf branch is wired up, not exact text content.
        file_bytes = _make_pdf_bytes("irrelevant")
        text = extract_text(file_bytes, "resume.pdf")
        assert isinstance(text, str)

    def test_rejects_unsupported_extension(self):
        with pytest.raises(UnsupportedResumeFormatError):
            extract_text(b"whatever", "resume.doc")

    def test_rejects_missing_extension(self):
        with pytest.raises(UnsupportedResumeFormatError):
            extract_text(b"whatever", "resume")

    def test_dispatch_is_case_insensitive(self):
        file_bytes = _make_docx_bytes("Case Insensitive Test")
        text = extract_text(file_bytes, "RESUME.DOCX")
        assert "Case Insensitive Test" in text


class TestParseResume:
    def test_calls_call_structured_with_parsed_resume_schema(self, monkeypatch):
        expected = ParsedResume(
            full_name="Jane Doe",
            email=None,
            phone=None,
            summary=None,
            skills=["Python"],
            work_experience=[],
            education=[],
            total_years_experience=None,
        )
        captured = {}

        def _fake_call_structured(system_instruction, user_prompt, schema):
            captured["schema"] = schema
            captured["user_prompt"] = user_prompt
            return expected

        monkeypatch.setattr(
            resume_parser_module, "call_structured", _fake_call_structured
        )

        result = parse_resume("Jane Doe resume text")

        assert result is expected
        assert captured["schema"] is ParsedResume
        assert "Jane Doe resume text" in captured["user_prompt"]
