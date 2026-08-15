"""
Google Gemini client - the network-client boundary for both AI features
(Resume Parser, ATS Score). Same "isolate the network client behind one
module, lazy-init on first use" shape as app/services/r2.py/email.py/
push.py: importing this module must not crash app startup just because
GEMINI_API_KEY isn't configured yet (e.g. local dev before an AI Studio
key exists).
"""

from typing import TypeVar

from google import genai
from google.genai import types
from pydantic import BaseModel

from app.core.config import settings

_client: genai.Client | None = None

T = TypeVar("T", bound=BaseModel)


def is_ai_configured() -> bool:
    return bool(settings.GEMINI_API_KEY)


def get_client() -> genai.Client:
    """Lazily initializes the Gemini client on first use - mirrors
    push.py's _get_app(). Callers should check is_ai_configured() first
    (the API endpoints do, returning 503 rather than reaching here) so
    this is only ever called when a key is actually set."""
    global _client
    if _client is not None:
        return _client

    if not settings.GEMINI_API_KEY:
        raise RuntimeError(
            "GEMINI_API_KEY is not set - AI features are not configured."
        )

    _client = genai.Client(api_key=settings.GEMINI_API_KEY)
    return _client


def call_structured(system_instruction: str, user_prompt: str, schema: type[T]) -> T:
    """Calls Gemini with structured-output mode (response_schema=schema),
    which guarantees a JSON response matching the schema - more reliable
    than asking for JSON in prose. `schema` must have every field
    required (Field(...), no Python-side defaults) even where the type
    itself is nullable - see app/schemas/ai.py's module docstring for why
    (Gemini's API rejects a response_schema containing default values).

    Prefers the SDK's own response.parsed (already an instance of
    `schema`); falls back to re-validating response.text if that's ever
    unset. Either path re-validates against `schema` rather than trusting
    the SDK blindly, so a malformed/incomplete response raises a
    pydantic.ValidationError instead of silently returning partial data -
    callers (app/tasks/ai.py) let that propagate as a real task failure.
    """
    client = get_client()
    response = client.models.generate_content(
        model=settings.GEMINI_MODEL,
        contents=user_prompt,
        config=types.GenerateContentConfig(
            system_instruction=system_instruction,
            response_mime_type="application/json",
            response_schema=schema,
        ),
    )
    if isinstance(response.parsed, schema):
        return response.parsed
    if response.text is None:
        raise ValueError("Gemini returned an empty response")
    return schema.model_validate_json(response.text)
