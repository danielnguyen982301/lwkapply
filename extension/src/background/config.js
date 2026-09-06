// Points at the local dev backend (see docker-compose.yml / uvicorn
// --port 8000). Swap for the deployed API origin before shipping past
// local testing, and add that origin to manifest.json's
// host_permissions too - a service worker fetch to a host not listed
// there is blocked the same as an unprivileged cross-origin request.
export const API_BASE_URL = 'http://localhost:8000/api/v1'

// Mirrors backend/app/api/deps.py's EXTENSION_CLIENT_VALUE - tells the
// API this is a client that needs its refresh token back in the
// response body (no reliable access to the web app's httpOnly cookie
// from a background service worker) and can skip CSRF double-submit
// (see is_token_based_client / verify_csrf_unless_token_based).
export const CLIENT_PLATFORM_HEADER = { 'X-Client-Platform': 'extension' }
