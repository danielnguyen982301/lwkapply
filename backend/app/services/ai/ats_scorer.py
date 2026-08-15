"""
ATS Score (TODO.md "AI Features"): scores an already-parsed resume
against a job description via Gemini.
"""

from app.schemas.ai import AtsScoreResult
from app.services.ai.client import call_structured

_SYSTEM_INSTRUCTION = (
    "You are an ATS (applicant tracking system) scoring assistant. Given "
    "a candidate's resume text and a job description, score how well the "
    "resume matches the job on a 0-100 scale, as a real ATS keyword/"
    "skills matcher would - not a general writing-quality judgment. "
    "List the specific keywords/skills from the job description that the "
    "resume does and doesn't cover, and give concrete, actionable "
    "suggestions for closing the gap."
)


def score_resume_against_job(resume_text: str, job_description: str) -> AtsScoreResult:
    return call_structured(
        system_instruction=_SYSTEM_INSTRUCTION,
        user_prompt=(
            f"Resume:\n\n{resume_text}\n\n" f"Job description:\n\n{job_description}"
        ),
        schema=AtsScoreResult,
    )
