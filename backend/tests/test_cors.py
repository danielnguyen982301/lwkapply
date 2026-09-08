"""
CORS behavior for browser-extension origins (app/main.py).

Chrome exempts host_permissions-covered origins from CORS entirely for
extension background requests, so it never needed anything here -
Firefox enforces ordinary CORS instead (confirmed against a real
rejection from the LwkApply browser extension running there: "CORS
header 'Access-Control-Allow-Origin' missing"). These tests guard the
allow_origin_regex fix for that, and confirm it stays scoped to actual
extension-shaped origins rather than accidentally widening CORS to
anything else.
"""

HEALTH_URL = "/health"


class TestExtensionOriginCors:
    def test_allows_a_firefox_extension_origin(self, client):
        response = client.get(
            HEALTH_URL,
            headers={"Origin": "moz-extension://12345678-abcd-1234-abcd-1234567890ab"},
        )
        assert (
            response.headers.get("access-control-allow-origin")
            == "moz-extension://12345678-abcd-1234-abcd-1234567890ab"
        )

    def test_allows_a_chrome_extension_origin(self, client):
        response = client.get(
            HEALTH_URL,
            headers={"Origin": "chrome-extension://abcdefghijklmnopabcdefghijklmnop"},
        )
        assert (
            response.headers.get("access-control-allow-origin")
            == "chrome-extension://abcdefghijklmnopabcdefghijklmnop"
        )

    def test_does_not_allow_an_unrelated_origin(self, client):
        response = client.get(
            HEALTH_URL, headers={"Origin": "https://evil-chrome-extension.example.com"}
        )
        assert "access-control-allow-origin" not in response.headers

    def test_still_allows_the_webapp_dev_origin(self, client):
        """Regression guard: allow_origin_regex is additive here, not a
        replacement for the existing static allow_origins list."""
        response = client.get(HEALTH_URL, headers={"Origin": "http://localhost:5173"})
        assert (
            response.headers.get("access-control-allow-origin")
            == "http://localhost:5173"
        )


class TestExtensionPreflightAllowsClientPlatformHeader:
    """Regression guard for a second, distinct Firefox failure: origin
    matching alone isn't enough, because Starlette's CORSMiddleware
    rejects the preflight itself with a 400 ("Disallowed CORS headers")
    if a requested header isn't in allow_headers - the browser never
    even sees a response worth reading. This was invisible on Chrome
    (extension origins bypass CORS there entirely) and on mobile (not a
    browser, no CORS), so only the extension's real login preflight
    (which requests X-Client-Platform, per app/api/deps.py's
    is_token_based_client) ever exercised this path."""

    def test_preflight_allows_x_client_platform_header(self, client):
        response = client.options(
            "/api/v1/auth/login",
            headers={
                "Origin": "moz-extension://12345678-abcd-1234-abcd-1234567890ab",
                "Access-Control-Request-Method": "POST",
                "Access-Control-Request-Headers": "content-type,x-client-platform",
            },
        )
        assert response.status_code == 200
        allowed = response.headers.get("access-control-allow-headers", "")
        assert "x-client-platform" in allowed.lower()
