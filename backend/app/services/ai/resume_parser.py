"""
Resume Parser (TODO.md "AI Features"): extract text from an uploaded
resume file, then structured data from that text via Gemini.

extract_text() supports PDF and DOCX only - the two by far most common
resume formats today. Legacy binary .doc (still one of r2.py's
ALLOWED_CONTENT_TYPES, since Word documents in general are accepted at
upload time) is a deliberate, documented gap: python-docx only reads the
OOXML .docx format, and pulling in a heavier legacy-.doc extraction
dependency (textract/antiword/LibreOffice conversion) for a shrinking
share of uploads isn't worth it for this pass. Raises
UnsupportedResumeFormatError, which app/tasks/ai_celery.py::parse_resume_task
turns into status=failed with a "please re-upload as PDF or DOCX"
message.
"""

import io
from pathlib import Path

import docx
from pypdf import PdfReader

from app.schemas.ai import ParsedResume
from app.services.ai.client import call_structured

_SUPPORTED_SUFFIXES = {".pdf", ".docx"}


class UnsupportedResumeFormatError(Exception):
    pass


def extract_text(file_bytes: bytes, file_name: str) -> str:
    suffix = Path(file_name).suffix.lower()
    if suffix not in _SUPPORTED_SUFFIXES:
        raise UnsupportedResumeFormatError(
            f"Unsupported resume format {suffix or '(unknown)'!r} - "
            "please re-upload this resume as PDF or DOCX to use AI parsing."
        )

    if suffix == ".pdf":
        reader = PdfReader(io.BytesIO(file_bytes))
        return "\n".join(page.extract_text() or "" for page in reader.pages)

    document = docx.Document(io.BytesIO(file_bytes))
    return "\n".join(paragraph.text for paragraph in document.paragraphs)


_SYSTEM_INSTRUCTION = (
    "You are a resume-parsing assistant. Extract structured information "
    "from the resume text provided. Only use information explicitly "
    "present in the text - never invent or infer details that aren't "
    "there. Use null for any field that genuinely isn't present, and an "
    "empty list for skills/work_experience/education if none are found."
)


def parse_resume(text: str) -> ParsedResume:
    return call_structured(
        system_instruction=_SYSTEM_INSTRUCTION,
        user_prompt=f"Resume text:\n\n{text}",
        schema=ParsedResume,
    )
