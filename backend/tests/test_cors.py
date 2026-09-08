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
