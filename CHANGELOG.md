# Changelog

## v0.4.0 (in progress)

### Added

- Frontend project scaffold (`webapp/`): Vite + Vue 3 + TypeScript +
  Pinia + Vue Router + Tailwind CSS + PrimeVue
- Auth screens: Login and Register, with client-side field validation,
  inline errors, and loading states
- Auth-aware routing: `authGuard` (pulled out as a standalone, unit-tested
  function) redirects unauthenticated visitors away from protected routes
  and authenticated visitors away from guest-only routes (login/register)
- Pinia `auth` store + Axios API client (`src/lib/api.ts`): bearer-token
  injection, a queued refresh-on-401 interceptor (prevents duplicate
  refresh calls when several requests 401 concurrently)
- httpOnly-cookie refresh-token flow, replacing the original JSON-body
  refresh token: backend sets `refresh_token` (httpOnly) and `csrf_token`
  (JS-readable) cookies on login/refresh; frontend sends
  `withCredentials: true` and echoes the CSRF cookie back as an
  `X-CSRF-Token` header on state-changing requests; refresh token now
  rotates on every use
- WebApp CI (`.github/workflows/webapp-ci.yml`, repo root): eslint →
  prettier --check → vue-tsc type-check → vitest with coverage → build,
  triggered on changes under `webapp/**`
- Webapp pre-commit hooks (eslint --fix, prettier --write), merged into
  the existing `.pre-commit-config.yaml` alongside the backend's ruff hooks
- Webapp unit tests: `authGuard` (redirect logic), `LoginView`
  (validation, successful-login redirect, error display), and the API
  client's error-message extraction helper

### Fixed

- `/auth/me` moved to `/users/me` to correctly reflect the user resource
  route (frontend's `fetchCurrentUser` updated to match)
- Response interceptor infinite-loop bug: a 401 from `/auth/refresh`
  itself was triggering another refresh attempt, which 401'd again,
  forever — auth endpoints are now excluded from the retry-on-401 logic
- ESLint/Prettier fighting each other on the same files (`lint:fix` and
  `format` each "fixing" to a different style) — added
  `eslint-config-prettier` so ESLint only checks correctness, Prettier
  owns all formatting
- Pre-commit hook was using `prettier --check`/no-`--fix` (a CI-style
  check, not a local auto-fix) and `cd webapp && npx ...` (breaks path
  resolution, since pre-commit passes file paths relative to the repo
  root) — switched to calling the binaries directly with `--write`/`--fix`
  and `pass_filenames: true`
- ESLint pre-commit hook failing with "couldn't find eslint.config.js" —
  ESLint 9's flat config only looks in the process's current working
  directory (the repo root, when run via pre-commit), not near the file
  being linted; fixed by passing `--config webapp/eslint.config.js` explicitly
- Production build (`vue-tsc -b`) failing on a `chai` type-declaration
  error surfaced through Vitest's own types — added `skipLibCheck: true`
  to **both** `tsconfig.app.json` and `tsconfig.node.json` (the latter,
  which compiles `vite.config.ts`, was the actual source, since
  `vite.config.ts` imports from `vitest/config`) and excluded test files
  from the production-build type-check

### Changed

- CORS now requires `allow_credentials=True` with an explicit
  `FRONTEND_ORIGIN` (no wildcard) to support the cross-site cookie, since
  frontend (Vercel) and backend (Railway/Render) are on different domains

## v0.3.0 (in progress)

### Added

- Interview endpoints: full CRUD, nested under `/applications/{id}/interviews`
- Contact endpoints: full CRUD, nested under `/applications/{id}/contacts`
- Document endpoints: multipart upload to S3, list, get metadata, presigned
  download URLs, update (`file_type`), delete — nested under
  `/applications/{id}/documents`
- `app/services/s3.py`: upload/delete/presigned-download helpers, with
  content-type validation and chunked size-limit enforcement
- Unit tests for Interview, Contact, and Document schemas
- Initial Alembic migration (`0001`), generated from models against a real
  Postgres instance

### Fixed

- Two enum columns (`interviews.result`, `documents.file_type`) were
  missing `nullable=False` in an earlier hand-drafted version of the
  initial migration; resolved by regenerating the migration via
  `alembic revision --autogenerate` directly from the models instead of
  hand-authoring it

### Changed

- All ownership checks for Interview/Contact/Document resources join
  through `Application.user_id`, matching the IDOR-prevention pattern
  already used by the Applications endpoints

## v0.2.0

### Added

- FastAPI backend project structure (`backend/app/...`)
- SQLAlchemy models: User, Application, Interview, Document, Contact
- Alembic migrations wired up
- JWT auth: register, login, refresh, password reset request/confirm, `/me`
- Application CRUD API with pagination, status filter, and search
- Docker Compose for local dev (API + Postgres + Redis)
- Unit tests for security, application schema and user schema.

## v0.1.0

### Added

- Documentation
- Architecture planning

## Upcoming

- Applications/Kanban UI (frontend Phase 2)
- Analytics endpoints
- Celery tasks (resume parsing, email sending, AI processing)
- RBAC beyond a `role` column
- Interview reminder system
