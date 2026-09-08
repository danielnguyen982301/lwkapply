// Template for config.js (gitignored, generated - see
// scripts/use-env.sh). Mirrors webapp's .env.example / mobile's
// .env.example: one source of truth per environment, nothing
// hardcoded in feature code.
export const API_BASE_URL = 'http://localhost:8000/api/v1'

// Mirrors backend/app/api/deps.py's EXTENSION_CLIENT_VALUE - tells the
// API this is a client that needs its refresh token back in the
// response body (no reliable access to the web app's httpOnly cookie
// from a background service worker) and can skip CSRF double-submit
// (see is_token_based_client / verify_csrf_unless_token_based).
export const CLIENT_PLATFORM_HEADER = { 'X-Client-Platform': 'extension' }
