# Changelog

## v0.5.0 (in progress)

### Changed

- **Migrated document storage from AWS S3 to Cloudflare R2**, ahead of
  ever putting real traffic on S3, so this was a client/config swap with
  no data to migrate:
  - Created `app/services/r2.py`; `upload_document`, `delete_document`, and
    `generate_download_url` kept their existing logic unchanged, since R2
    implements the same S3-compatible API for `put_object`,
    `delete_object`, and `generate_presigned_url` — confirmed against
    Cloudflare's current docs rather than assumed, per the "don't assume
    parity" note this item carried as a Planned item
  - `boto3.client("s3", ...)` is still the call used — that argument
    selects boto3's client protocol, not a company — now pointed at R2 via
    `endpoint_url=f"https://{R2_ACCOUNT_ID}.r2.cloudflarestorage.com"` and
    `region_name="auto"` (R2 has no AWS-style regions; `"auto"` is a
    required literal, not a placeholder)
  - Config: Added `R2_ACCOUNT_ID` / `R2_ACCESS_KEY_ID` /
    `R2_SECRET_ACCESS_KEY` / `R2_BUCKET`
  - `documents.py` endpoint import updated to `app.services.r2`
  - Test mocking boundary moved to `app.services.r2._r2_client`
    (`test_documents_endpoints.py`'s fixture renamed `fake_r2_client`);
    content-type validation, chunked size-limit enforcement, and
    object-key construction still run for real against the fake client,
    unchanged from the S3 version's mocking strategy
  - Presigned URL expiry (5 min) and the chunked upload size-limit check
    confirmed to behave identically against R2 — no parity gap found
  - `BACKEND_SUMMARY.md`, `ARCHITECTURE.md`, `AI_CONTEXT.md`, and
    `TODO.md` updated to reflect R2 as the live provider, per this same
    Planned item's original note to update docs once it's live rather
    than prospectively
- Form validation library, webapp-wide: replaced hand-rolled `reactive()` +
  manual `validate()` functions (`LoginView.vue`, `RegisterView.vue`,
  `ApplicationFormView.vue`, and the Contacts/Interviews/Documents panel
  dialogs) with **vee-validate** + **`@vee-validate/zod`**'s
  `toTypedSchema`, backed by reusable field-wrapper components
  (`src/components/custom_form_fields/CustomInputText.vue`,
  `CustomPassword.vue`) that internalize `useField()` binding and
  error-message display — consuming views just pass `name` plus
  presentational props, matching the `name`-based ergonomics we originally
  wanted from PrimeVue Forms, without PrimeVue Forms itself
- **`zod` pinned to `^3.24.0`** (not v4): `@vee-validate/zod`'s
  `toTypedSchema` declares a hard peer dependency on `zod@^3.24.0` and does
  not support Zod v4 — its typed-schema introspection reaches into Zod's
  internal schema representation, which changed shape in v4 (see
  [logaretm/vee-validate#5091](https://github.com/logaretm/vee-validate/issues/5091),
  [#5024](https://github.com/logaretm/vee-validate/issues/5024)). vee-validate
  v5 removes `toTypedSchema` in favor of Standard Schema (which would
  support Zod v4 natively) but was still beta and reportedly broken at the
  time of this migration
  ([#5151](https://github.com/logaretm/vee-validate/issues/5151)) — revisit
  the Zod v4 upgrade once v5 is stable, not before
- **Abandoned an earlier attempt on PrimeVue Forms** (`@primevue/forms` +
  its own `zodResolver`) after hitting several confirmed, currently-open
  upstream bugs rather than app-level mistakes:
  - `DatePicker` bound via Forms' `name` system ignores `dateFormat` and
    displays the raw `Date.toString()` instead of a formatted string
    ([primefaces/primevue#7995](https://github.com/primefaces/primevue/issues/7995));
    manually-typed dates are relayed to the form as the formatted display
    string rather than a `Date`/ISO value
    ([#7545](https://github.com/primefaces/primevue/issues/7545))
  - No reliable way to re-baseline a form's dirty-tracking after loading
    existing data asynchronously (the whole point of an edit form):
    reactively reassigning `:initial-values` after a fetch isn't
    consistently picked up
    ([#7184](https://github.com/primefaces/primevue/issues/7184)), and
    working around it via `$form`'s per-field `.dirty` plus the exposed
    `setValues()` instance method still left the Save button permanently
    enabled on `ApplicationFormView.vue`'s edit route
  - Cross-field validation (the salary-range `min <= max` check) went
    stale: editing one field after the other had already been validated
    didn't reliably re-run the shared `.refine()`, requiring a manual
    forced revalidation workaround that still wasn't a real fix

### Known issues

- vee-validate + `@vee-validate/zod` validation does not resolve
  synchronously (unlike the hand-rolled `validate()` functions it
  replaced) — any test asserting on validation-error text or a
  `handleSubmit`-gated store call after `trigger('submit')` must wrap that
  assertion in `vi.waitFor(() => { ... })`. `LoginView.spec.ts` hit this
  directly: `auth.login` appeared to never be called even with valid
  input, and field-error text appeared to never render, purely because
  the assertions ran before validation had actually resolved

### Planned

- Cross-application Interviews directory: a top-level, read-only view
  listing every interview across every application the user owns — not
  just one application's panel — mirroring the `ContactDirectoryView.vue`
  - `GET /contacts` pattern from v0.4.0. Needs a new paginated backend
    endpoint analogous to `GET /contacts` (`GET /interviews`, aggregating
    via the same `Interview.application_id` → `Application.user_id` join),
    plus a matching frontend store/view
- Cross-application Documents directory: same shape as above (`GET
/documents`, `DocumentDirectoryView.vue`)

## v0.4.0

### Added

- Backend integration test infrastructure (`backend/tests/conftest.py`):
  session-scoped real-Postgres engine, per-test SAVEPOINT-based
  transaction isolation (endpoint `db.commit()` calls only close a
  savepoint, not the outer transaction, so nothing persists and tests
  can't leak state into each other), an authenticated `TestClient`
  fixture wired through the app's real `get_current_user`/
  `create_access_token` path rather than mocked, and `make_user`/
  `auth_headers` factory fixtures — the reusable base for every future
  endpoint test, not just this one
- `GET /contacts` integration tests
  (`backend/tests/test_contacts_directory.py`): the first API-level
  (DB + HTTP) test in the suite, covering authentication (missing/
  invalid/wrong-token-type), cross-application contact aggregation, the
  ownership/IDOR check (a user must never see another user's contacts,
  including via the `search` param), search, and pagination
- `Settings.TEST_DATABASE_URL` (`backend/app/core/config.py`): a
  separate throwaway-database setting for integration tests, loaded the
  same way as every other setting (`.env.local` locally, a real env var
  in CI), defaulting to a `lwkapply_test` database alongside the dev
  database
- `backend-ci.yml`: enabled the previously-commented-out Postgres
  `services:` block in the `test` job, with `TEST_DATABASE_URL` set as a
  job-level env var; added `httpx` to `requirements-dev.txt`, required by
  `fastapi.testclient.TestClient` now that a test exercises the HTTP
  layer
- Applications CRUD integration tests
  (`backend/tests/test_applications_endpoints.py`): auth, create
  (including confirming a spoofed `user_id` in the request body is
  ignored — ownership always comes from the authenticated user), the
  ownership/IDOR check on get/update/delete (each confirms the row is
  actually untouched, not just that the HTTP call failed), status filter,
  company/position search, pagination, and list ordering (using explicit
  `updated_at` timestamps rather than wall-clock gaps between inserts,
  since Postgres's `now()` is transaction-scoped and every insert in a
  test shares one real transaction under the SAVEPOINT isolation
  strategy)
- `ApplicationUpdate` salary-range validation
  (`backend/app/schemas/application.py`,
  `backend/app/api/v1/endpoints/applications.py`): the `salary_min <=
salary_max` check previously only existed on `ApplicationCreate`, so a
  PATCH could silently invert a valid range. Fixed at two levels: a
  shared `SalaryRangeValidationMixin` now backs both `ApplicationCreate`
  and `ApplicationUpdate` (catches both fields sent inconsistently in one
  request), and `update_application` additionally checks the _merged_
  effective range (request value if provided, otherwise the value
  already on the row) before applying any change, since the schema alone
  can't see a partial PATCH that conflicts with existing stored data
- Interviews CRUD integration tests
  (`backend/tests/test_interviews_endpoints.py`): auth, create/update
  validation (duration bounds, invalid enum values), ownership/IDOR
  across users, and — specific to this resource, since it's nested two
  levels deep (Interview -> Application -> User) — a dedicated scoping
  check confirming an interview under one application isn't reachable
  through a _sibling_ application's URL even for the same user. Also
  directly verifies `Interview.result`'s `server_default` behavior
  end-to-end (see Fixed, below)
- Pagination for `GET /applications/{id}/interviews`
  (`backend/app/schemas/interview.py`,
  `backend/app/api/v1/endpoints/interviews.py`): `page`/`page_size` query
  params and response fields, matching the existing Applications/Contacts
  pattern; previously this was the only list endpoint returning every row
  unpaginated
- Documents CRUD integration tests
  (`backend/tests/test_documents_endpoints.py`): upload (content-type
  rejection, chunked size-limit enforcement, simulated S3 failure),
  download (presigned URL, confirms the exact S3 object key used matches
  the stored `file_url`), update, delete, ownership/IDOR, and the same
  sibling-application scoping check as Interviews. Only
  `app.services.s3._s3_client` (the actual `boto3.client(...)` factory)
  is mocked — everything else in `s3.py` (content-type validation, the
  chunked size check, object-key construction) runs for real against the
  fake client, so these tests exercise that logic rather than assuming
  it works. Also confirms delete still succeeds and removes the DB row
  even when the S3-side delete fails, per `delete_document`'s
  best-effort-cleanup contract
- Pagination for `GET /applications/{id}/documents`
  (`backend/app/schemas/document.py`,
  `backend/app/api/v1/endpoints/documents.py`): same `page`/`page_size`
  pattern as Applications/Interviews/Contacts-directory
- Nested Contacts CRUD integration tests
  (`backend/tests/test_contacts_endpoints.py`): covers
  create/get/update/delete/list under
  `/applications/{application_id}/contacts` — previously only the
  separate, flat `GET /contacts` directory route had integration
  coverage (`test_contacts_directory.py`). Same auth, ownership/IDOR, and
  sibling-application-scoping shape as the Interviews/Documents suites.
  Confirmed as a deliberate design decision (not an oversight,
  previously flagged as an open gap in docs): the nested list stays
  unpaginated, since a single application's contact count is naturally
  small, while the directory route — which aggregates across every
  application a user has ever tracked — keeps its existing pagination.
  See BACKEND_SUMMARY.md's note on the contacts directory endpoint.

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
- Applications UI (Phase 2): Pinia `applications` store
  (`src/stores/applications.ts`) with typed API calls for list, detail,
  create, update, delete, and board fetch; server-side pagination, status
  filter, and debounced search
- Application List view (`ApplicationListView.vue`): PrimeVue `DataTable`,
  `Paginator`, `Select`, and status `Tag` badges; edit/delete actions
  with `ConfirmDialog` for destructive operations
- Application Details / New view (`ApplicationFormView.vue`): shared
  create/edit form with client-side validation; PrimeVue form controls
  (`InputText`, `Select`, `InputNumber`, `DatePicker`, `Textarea`)
- Kanban board (`ApplicationBoardView.vue`): drag-and-drop status changes
  via `vue-draggable-plus`, keyboard-accessible status `Select` on each
  card, List/Board toggle via `TabMenu` (`ViewTabs.vue`)
- PrimeVue adopted across all existing screens: auth forms, app shell,
  layouts, dashboard/404 placeholders — Aura theme, `primeicons`,
  `ConfirmationService` for delete confirmations; shared helpers in
  `src/lib/application-ui.ts` and `ApplicationStatusTag.vue`
- Test helper `src/test/primevue.ts` so component tests can mount
  PrimeVue controls (used by `LoginView.spec.ts`)
- Contact management UI (Phase 4, frontend): Pinia `contacts` store
  (`src/stores/contacts.ts`), scoped to one application's contacts at a
  time; `ContactsPanel.vue`, rendered on `ApplicationFormView.vue` once an
  application exists — add/edit via a PrimeVue `Dialog` (name required,
  client-side email-format validation, title, LinkedIn URL), delete via
  the existing `ConfirmDialog` pattern
- Cross-application contacts directory (backend + frontend): read-only
  `GET /contacts` endpoint (`directory_router` in
  `app/api/v1/endpoints/contacts.py`), aggregating every contact across
  every application the authenticated user owns, with the parent
  application's company/position/status attached — paginated,
  search-by-name-or-company, ownership enforced via the same
  `Contact.application_id` → `Application.user_id` join the nested
  endpoints already use, no new column or migration required; new schemas
  `ApplicationSummary` / `ContactWithApplicationRead` /
  `ContactWithApplicationListResponse`. Frontend: `ContactDirectoryView.vue`
  (route `/contacts`) + Pinia `contactDirectory` store, same
  `DataTable`/`Paginator`/debounced-search skeleton as
  `ApplicationListView.vue`; each row links back to the owning
  application's detail page
- Backend schema tests extended to cover the three new directory-response
  schemas above, including construction via `model_validate()` from
  ORM-style attribute objects (not just dicts), matching how the endpoint
  actually builds the response off `contains_eager(Contact.application)`
- Interviews UI (Phase 4, frontend): Pinia `interviews` store
  (`src/stores/interviews.ts`), scoped to one application's interviews at
  a time, same application-scoping/reset-on-unmount pattern as the
  Contacts store, plus server-side pagination (unlike Contacts, this list
  endpoint is paginated); `InterviewsPanel.vue`, rendered on
  `ApplicationFormView.vue` alongside `ContactsPanel.vue`. Schedule/edit
  via a PrimeVue `Dialog` (type, date & time, duration, result, feedback);
  delete via the existing `ConfirmDialog` pattern. Create/update refetch
  the current page rather than patch client-side, since the list is
  server-sorted by `scheduled_at` and a client-side guess at insert
  position could land wrong after either a create or a date change.
  New `src/types/interview.ts` and `src/lib/interview-ui.ts` (type/result
  labels, select options, result-severity mapping — mirrors
  `application-ui.ts`'s conventions)
- Documents UI (Phase 3, frontend): Pinia `documents` store
  (`src/stores/documents.ts`), same application-scoping pattern, plus
  multipart upload (`FormData`) and on-demand presigned-download-URL
  fetching (opened directly via `window.open`, never routed back through
  the API — the endpoint returns a short-lived S3 URL, not a permanent
  one); `DocumentsPanel.vue`, rendered alongside `ContactsPanel.vue`/
  `InterviewsPanel.vue`. Upload dialog (native file input + type select),
  a separate lightweight edit dialog for the one user-editable field
  (`file_type`), download/delete actions per row. New
  `src/types/document.ts` and `src/lib/document-ui.ts`

### Known issues

- `primevue` is pinned to exactly `4.5.4` in `package.json` (not a caret
  range) — `4.5.5` has a regression affecting `DatePicker` fields where
  manually-typed text doesn't reliably commit on blur, which surfaced on
  both the Interviews scheduling field and the Application `applied_date`
  field. Do not bump PrimeVue past `4.5.4` until that's confirmed fixed
  upstream
- The Application edit form's "Save changes" button doesn't yet track
  dirty state (it's enabled even with no changes made). Planned, not yet
  scheduled: adopt PrimeVue Forms + a validation library for the
  Application form generally, with dirty-tracking as part of that change
  rather than a one-off manual diff

### Fixed

- `BACKEND_SUMMARY.md`'s note on `Document.file_type`/`Interview.result`
  incorrectly claimed both used a Python-side `default=`. `Interview.result`
  actually uses `server_default=InterviewResult.PENDING` (the raw enum
  member, not `.value`) — confirmed working correctly via a dedicated
  integration test rather than assumed; doc corrected to match. (`Document.file_type`
  wasn't re-checked against its model file, so the note no longer makes a
  claim about it either way.)
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
- All interactive UI migrated from hand-rolled HTML/Tailwind controls to
  PrimeVue components where appropriate; Tailwind retained for layout,
  spacing, and custom branding (sidebar, typography)
- `AppLayout.vue`'s "Contacts" nav item enabled (was a disabled
  placeholder pointing at `/`) — now routes to `/contacts`
- `router.py`'s nested-resource comment updated: Contacts is no longer
  purely nested-only now that `GET /contacts` exists as a flat, top-level,
  read-only route alongside the nested CRUD

## v0.3.0

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

- Analytics endpoints and dashboard charts
- Celery tasks (resume parsing, email sending, AI processing)
- RBAC beyond a `role` column
- Interview reminder system
- Application edit form: adopt PrimeVue Forms + a validation library,
  including dirty-state tracking for the "Save changes" button (see
  v0.4.0's Known Issues)
- Webapp component/store tests for Applications UI, and the Contacts/
  Interviews/Documents UI added in v0.4.0
- Backend endpoint/integration test harness (test DB + fixtures + auth
  test client) — none exists yet; `GET /contacts` is the first endpoint
  that needs one
