"""
Unit tests for app.services.ai.job_description_fetcher.

Mocking strategy: httpx.stream is the actual network boundary here (the
module-level convenience function doesn't accept an injectable
`transport=`, unlike constructing an httpx.Client directly), so these
tests patch `job_description_fetcher.httpx.stream` with a fake response
object rather than hitting real network - same "mock only the network
call, not the surrounding logic" convention as
app.services.r2._r2_client in test_documents_endpoints.py. socket.
getaddrinfo is separately patched to control DNS resolution
deterministically for the SSRF guard tests, which is the
security-critical part of this module and gets direct coverage rather
than only being exercised incidentally by the happy-path tests.
"""

import httpx
import pytest

import app.services.ai.job_description_fetcher as fetcher_module
from app.services.ai.job_description_fetcher import (
    _is_safe_url,
    fetch_job_description,
)

_REALISTIC_JOB_HTML = """
<!DOCTYPE html>
<html>
<head><title>Senior Backend Engineer - Acme Corp</title></head>
<body>
<article>
<h1>Senior Backend Engineer</h1>
<p>Acme Corp is looking for a Senior Backend Engineer to join our
platform team. You will design and build scalable APIs, work closely
with product and design, and mentor junior engineers on the team.</p>
<h2>Requirements</h2>
<p>5+ years of experience with Python, strong knowledge of PostgreSQL
and distributed systems, experience with Docker and Kubernetes in
production, and excellent written and verbal communication skills.</p>
<h2>Nice to have</h2>
<p>Experience with FastAPI, Celery, and cloud object storage such as
S3 or Cloudflare R2. Prior experience mentoring other engineers.</p>
</article>
</body>
</html>
"""


class _FakeResponse:
    def __init__(
        self, status_code, headers=None, body=b"", url="https://example.com/job"
    ):
        self.status_code = status_code
        self.headers = headers or {}
        self._body = body
        self.url = httpx.URL(url)
        self.encoding = None

    @property
    def is_redirect(self):
        return 300 <= self.status_code < 400

    def iter_bytes(self):
        yield self._body

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


@pytest.fixture(autouse=True)
def _allow_all_dns(monkeypatch):
    """Default: every hostname resolves to a public IP, so tests that
    aren't specifically about the SSRF guard don't need to think about
    DNS. Individual tests override this via monkeypatch as needed."""
    monkeypatch.setattr(
        fetcher_module.socket,
        "getaddrinfo",
        lambda host, port: [(None, None, None, None, ("93.184.216.34", 0))],
    )


class TestIsSafeUrl:
    def test_rejects_non_http_scheme(self):
        assert _is_safe_url("ftp://example.com/job") is False
        assert _is_safe_url("file:///etc/passwd") is False

    def test_rejects_url_with_no_hostname(self):
        assert _is_safe_url("http://") is False

    def test_accepts_public_ip(self, monkeypatch):
        monkeypatch.setattr(
            fetcher_module.socket,
            "getaddrinfo",
            lambda host, port: [(None, None, None, None, ("93.184.216.34", 0))],
        )
        assert _is_safe_url("http://example.com/job") is True

    @pytest.mark.parametrize(
        "ip",
        [
            "10.0.0.5",  # private
            "127.0.0.1",  # loopback
            "169.254.169.254",  # link-local / cloud metadata endpoint
            "192.168.1.1",  # private
            "224.0.0.1",  # multicast
        ],
    )
    def test_rejects_internal_ip(self, monkeypatch, ip):
        monkeypatch.setattr(
            fetcher_module.socket,
            "getaddrinfo",
            lambda host, port: [(None, None, None, None, (ip, 0))],
        )
        assert _is_safe_url("http://internal.example.com/job") is False

    def test_rejects_when_dns_fails(self, monkeypatch):
        import socket

        def _raise(host, port):
            raise socket.gaierror("not found")

        monkeypatch.setattr(fetcher_module.socket, "getaddrinfo", _raise)
        assert _is_safe_url("http://does-not-resolve.example/job") is False


class TestFetchJobDescription:
    def test_returns_extracted_text_on_success(self, monkeypatch):
        monkeypatch.setattr(
            fetcher_module.httpx,
            "stream",
            lambda *a, **k: _FakeResponse(
                200,
                headers={"content-type": "text/html; charset=utf-8"},
                body=_REALISTIC_JOB_HTML.encode(),
            ),
        )
        result = fetch_job_description("https://jobs.example.com/posting/123")
        assert result is not None
        assert "Backend Engineer" in result

    def test_follows_redirect_then_extracts(self, monkeypatch):
        calls = {"n": 0}

        def _fake_stream(method, url, **kwargs):
            calls["n"] += 1
            if calls["n"] == 1:
                return _FakeResponse(
                    302,
                    headers={"location": "/final-posting"},
                    url="https://jobs.example.com/posting/123",
                )
            return _FakeResponse(
                200,
                headers={"content-type": "text/html"},
                body=_REALISTIC_JOB_HTML.encode(),
            )

        monkeypatch.setattr(fetcher_module.httpx, "stream", _fake_stream)
        result = fetch_job_description("https://jobs.example.com/posting/123")
        assert result is not None
        assert calls["n"] == 2

    def test_blocks_redirect_to_internal_ip(self, monkeypatch):
        def _resolve(host, _port):
            if host == "jobs.example.com":
                return [(None, None, None, None, ("93.184.216.34", 0))]
            return [(None, None, None, None, ("127.0.0.1", 0))]

        monkeypatch.setattr(fetcher_module.socket, "getaddrinfo", _resolve)
        monkeypatch.setattr(
            fetcher_module.httpx,
            "stream",
            lambda *a, **k: _FakeResponse(
                302,
                headers={"location": "http://internal.local/secret"},
                url="https://jobs.example.com/posting/123",
            ),
        )
        assert fetch_job_description("https://jobs.example.com/posting/123") is None

    def test_returns_none_on_non_200(self, monkeypatch):
        monkeypatch.setattr(
            fetcher_module.httpx, "stream", lambda *a, **k: _FakeResponse(404)
        )
        assert fetch_job_description("https://jobs.example.com/gone") is None

    def test_returns_none_when_response_too_large(self, monkeypatch):
        monkeypatch.setattr(fetcher_module, "_MAX_RESPONSE_BYTES", 10)
        monkeypatch.setattr(
            fetcher_module.httpx,
            "stream",
            lambda *a, **k: _FakeResponse(
                200,
                headers={"content-type": "text/html"},
                body=_REALISTIC_JOB_HTML.encode(),
            ),
        )
        assert fetch_job_description("https://jobs.example.com/posting/123") is None

    def test_returns_none_for_non_html_content_type(self, monkeypatch):
        monkeypatch.setattr(
            fetcher_module.httpx,
            "stream",
            lambda *a, **k: _FakeResponse(
                200,
                headers={"content-type": "application/pdf"},
                body=b"%PDF-1.4",
            ),
        )
        assert fetch_job_description("https://jobs.example.com/posting.pdf") is None

    def test_returns_none_on_too_short_extraction(self, monkeypatch):
        monkeypatch.setattr(
            fetcher_module.httpx,
            "stream",
            lambda *a, **k: _FakeResponse(
                200,
                headers={"content-type": "text/html"},
                body=b"<html><body><p>Hi</p></body></html>",
            ),
        )
        assert fetch_job_description("https://jobs.example.com/thin") is None

    def test_returns_none_on_unsafe_url(self):
        assert fetch_job_description("ftp://jobs.example.com/posting") is None

    def test_returns_none_on_http_error(self, monkeypatch):
        def _raise(*a, **k):
            raise httpx.ConnectTimeout("timed out")

        monkeypatch.setattr(fetcher_module.httpx, "stream", _raise)
        assert fetch_job_description("https://jobs.example.com/posting/123") is None
