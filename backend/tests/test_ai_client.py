"""
Unit tests for app.services.ai.client.

Mocking strategy: only get_client() (the actual Gemini network-client
boundary) is patched, same "mock only the network call" convention as
_r2_client/_get_app elsewhere in this test suite. call_structured()'s
own prompt-construction and response-validation logic runs for real.
"""

from unittest.mock import MagicMock

import pytest
from pydantic import BaseModel, Field, ValidationError

import app.services.ai.client as client_module
from app.core.config import settings
from app.services.ai.client import call_structured, is_ai_configured


class _DummySchema(BaseModel):
    value: str = Field(...)


class TestIsAiConfigured:
    def test_false_when_key_unset(self, monkeypatch):
        monkeypatch.setattr(settings, "GEMINI_API_KEY", "")
        assert is_ai_configured() is False

    def test_true_when_key_set(self, monkeypatch):
        monkeypatch.setattr(settings, "GEMINI_API_KEY", "fake-key")
        assert is_ai_configured() is True


class TestCallStructured:
    def test_prefers_response_parsed(self, monkeypatch):
        fake_response = MagicMock()
        fake_response.parsed = _DummySchema(value="from-parsed")
        fake_client = MagicMock()
        fake_client.models.generate_content.return_value = fake_response
        monkeypatch.setattr(client_module, "get_client", lambda: fake_client)

        result = call_structured("system", "prompt", _DummySchema)

        assert result == _DummySchema(value="from-parsed")
        fake_client.models.generate_content.assert_called_once()

    def test_falls_back_to_response_text(self, monkeypatch):
        fake_response = MagicMock()
        fake_response.parsed = None
        fake_response.text = '{"value": "from-text"}'
        fake_client = MagicMock()
        fake_client.models.generate_content.return_value = fake_response
        monkeypatch.setattr(client_module, "get_client", lambda: fake_client)

        result = call_structured("system", "prompt", _DummySchema)

        assert result == _DummySchema(value="from-text")

    def test_malformed_response_raises_validation_error(self, monkeypatch):
        fake_response = MagicMock()
        fake_response.parsed = None
        fake_response.text = "{}"  # missing required "value"
        fake_client = MagicMock()
        fake_client.models.generate_content.return_value = fake_response
        monkeypatch.setattr(client_module, "get_client", lambda: fake_client)

        with pytest.raises(ValidationError):
            call_structured("system", "prompt", _DummySchema)
