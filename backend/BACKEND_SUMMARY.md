# Backend — Job Application Tracker API

FastAPI + SQLAlchemy + PostgreSQL backend implementing Phase 1 (Foundation),
Phase 2 (Application Tracking), the start of Phase 3 (Resume Management),
Phase 4 (Interview Management, including its reminder system), and the
start of Phase 7 (AI Features — Resume Parser + ATS Score, backend only
so far) from the project roadmap.

## What's implemented

- **Auth**: register, login (JWT access + refresh tokens), token refresh,
  password reset (request/confirm). As of this pass, `/login`,
  `/refresh`, and `/logout` also support the mobile client — see "A note
  on mobile-client auth support" below and `mobile/MOBILE_SUMMARY.md`.
  Register/login/refresh also accept an optional client-reported
  `timezone` — see "Timezone reporting" below
- **Interview reminders**: email (Resend prod / MailHog local) and push
  (FCM, Android) reminders sent a configurable lead time before a
  scheduled interview, via a Celery beat task — see "Interview reminder
  system" below
- **Device tokens**: `POST`/`DELETE /users/me/device-tokens`, backing
  the mobile client's push-notification registration — see "Interview
  reminder system" below
- **Applications**: full CRUD, pagination, status filter,
  company/position/`application_name` search — all scoped to the
  authenticated user. `application_name` is an optional, user-chosen
  label (e.g. "Re-applied after rejection") so applications that share
  the same company/position are still easy to tell apart in list views —
  purely a display/search convenience, no other endpoint behavior depends
  on it. Embedded in the Interviews directory endpoint's
  `ApplicationSummary` too (see the note below)
- **Interviews**: full CRUD, pagination, nested under
  `/applications/{application_id}/interviews`; plus a read-only, top-level
  `GET /interviews` — a cross-application directory of every interview
  the authenticated user owns, with the parent application's
  company/position/status attached, paginated and filterable by `result`
  (backs the webapp's "Interviews" nav item)
- **Contacts**: a top-level, user-owned resource (like `Document`), not
  nested under any application — create, list (paginated, searchable by
  `name`), get, patch, delete, all at `/contacts`. Reusable across zero,
  one, or several applications via a separate many-to-many link:
  `POST`/`GET`/`DELETE /applications/{application_id}/contacts` attaches,
  lists, and detaches which contacts are currently linked to one
  application (`ApplicationContact`) — see "A note on Contact /
  ApplicationContact" below for why this replaced the old
  one-application-per-contact model
- **Documents**: a top-level, user-owned resource (like `Application`),
  not nested under any application — upload (multipart, streamed to
  Cloudflare R2), list (paginated, searchable by `file_name`, filterable
  by `file_type`), get metadata, presigned download URLs, update
  (`file_type` only), delete, all at `/documents`. Reusable across zero,
  one, or several applications via a separate many-to-many link:
  `POST`/`GET`/`DELETE /applications/{application_id}/documents` attaches,
  lists, and detaches which documents are currently linked to one
  application (`ApplicationDocument`) — see "A note on Document /
  ApplicationDocument" below for why this replaced the old
  one-application-per-document model
- **Analytics**: four read-only, real-time endpoints — `GET /analytics/summary`,
  `/funnel`, `/activity`, `/interviews` — all scoped to the authenticated
  user, no precomputation/caching (see "A note on the analytics endpoints"
  below for why real-time was the right call at this data scale)
- **Application status history**: `application_status_history` — an
  append-only audit log of every `Application.status` transition, written
  alongside every create/update. Not yet read by the analytics endpoints
  above (see the note below for why the funnel is a current-state
  snapshot instead)
- **Users**: the current endpoints only contain `/users/me`, this is moved from `/auth/me` to
  reflect the users route better.
- **AI features (Resume Parser + ATS Score)**: `POST`/`GET /ai/resume-analyses`
  and `POST`/`GET /ai/ats-scores`, both async (create returns `202` with a
  `pending` row, a Celery task fills it in, client polls `GET .../{id}`) —
  see "AI features" below
- **Models**: User (now with `timezone`), Application, Interview,
  Document and Contact (both top-level/user-owned, no longer a single
  `application_id` FK — see "A note on Document / ApplicationDocument"
  and "A note on Contact / ApplicationContact" below) (matches
  `docs/DATABASE.md`, though that doc doesn't yet reflect either
  decoupling), plus `InterviewReminder` and `DeviceToken` (reminder
  system), `ApplicationStatusHistory` (audit log — not yet reflected in
  `docs/DATABASE.md` either), `ApplicationDocument`/`ApplicationContact`
  (many-to-many joins between Application and Document/Contact), and
  `ResumeAnalysis`/`AtsScore` (AI features — `AtsScore` no longer links
  to `Application` at all; see "AI features" below)
- **Infra**: Alembic migration `0001` applied (autogenerated from models —
  see note below), Docker Compose (API + Postgres + Redis)
- **Tests**: Unit tests for security, application/interview/contact/document
  schemas, user schema. Neither Contact nor Document has a
  cross-application-directory schema any more —
  `ContactWithApplicationRead`/`ContactWithApplicationListResponse` and
  `DocumentWithApplicationRead` were both removed along with the old
  directories they backed (see "A note on Contact / ApplicationContact"
  and "A note on Document / ApplicationDocument" below); `ContactRead`/
  `DocumentRead` now cover every read path, unit-tested directly in
  `test_contact_schema.py`/`test_document_schema.py`. The equivalent
  Interview directory schema — `InterviewWithApplicationRead` — still
  exists (Interview is still nested-only) and still only has integration
  coverage, not this schema-unit-test treatment.
  Integration test suites (real Postgres + HTTP layer, not just
  schema validation) now exist for every CRUD endpoint in the API, plus
  the one remaining cross-application directory endpoint, `GET /interviews`
  (`test_interviews_directory.py`), top-level Contacts CRUD
  (`test_contacts_endpoints.py` — create/list/search/paginate/get/patch/
  delete, all unnested now), Applications CRUD
  (`test_applications_endpoints.py`), Interviews CRUD
  (`test_interviews_endpoints.py`), top-level Documents CRUD
  (`test_documents_endpoints.py` — upload/list/search/filter/get/patch/
  delete/download, all unnested now), the Document ↔ Application
  attach/detach link (`test_application_documents_endpoints.py` — the
  direct successor to the old `test_documents_directory.py`, now testing
  a many-to-many join instead of a read-only flat listing; see "A note on
  Document / ApplicationDocument" below), and the Contact ↔ Application
  attach/detach link (`test_application_contacts_endpoints.py` — the
  direct successor to the old `test_contacts_directory.py`, same
  relationship; see "A note on Contact / ApplicationContact" below).
  Interviews is the only suite left covering two-levels-deep ownership
  scoping (a resource under one application must not be reachable via a
  sibling application's URL, even for the same user) — Contacts had this
  case before its decoupling and dropped it for the same reason Documents
  never needed it: neither is reachable through any application's URL any
  more except via its attach/detach link. Interviews also confirms
  `Interview.result`'s `server_default` behavior directly (see note
  below), and Documents mocks only the actual `boto3` client boundary
  (`app.services.r2._r2_client`), so the real content-type validation,
  chunked size-limit enforcement, and best-effort
  R2-cleanup-on-delete-failure logic all still run for real in those
  tests. AI features add their own suite —
  `test_ai_schemas.py`, `test_ai_client.py`, `test_resume_parser.py`,
  `test_ats_scorer.py`, `test_job_description_fetcher.py` (the SSRF
  guard gets direct coverage, not just incidental exercise via the
  happy-path tests), `test_ai_tasks.py`, and `test_ai_endpoints.py` — see
  "AI features" below for the new `join_transaction_mode` pattern
  `test_ai_tasks.py` establishes for testing a per-request Celery task.
  `application_name` round-trip/search coverage lives in
  `test_applications_endpoints.py`; its presence in the embedded
  `ApplicationSummary` is covered directly in `test_interviews_directory.py`

All Interview endpoints enforce ownership by joining through
`Application.user_id`, the same IDOR-prevention approach the
Applications endpoints already used, just one hop further through the FK
chain (Interview → Application → User). Document and Contact are both
exceptions now — ownership on each is a direct `user_id` FK equality
check, the same pattern as `ResumeAnalysis`/`AtsScore` (see "A note on
Document / ApplicationDocument" and "A note on Contact /
ApplicationContact" below for why); `ApplicationDocument`/
`ApplicationContact` (the attach/detach links) check ownership on
**both** sides — the application via `Application.user_id`, the
document/contact via `Document.user_id`/`Contact.user_id` — since
attaching requires owning both ends of the link.

### A note on mobile-client auth support

`/auth/login`, `/auth/refresh`, and `/auth/logout` now branch on whether
a request came from the mobile app or the web app. Full detail on the
mobile side of this is in `mobile/MOBILE_SUMMARY.md`; here's the
backend half:

- **Detection**: `app/api/deps.py::is_mobile_client(request)` checks for
  an `X-Client-Platform: mobile` header. Header lookups on
  `request.headers` are case-insensitive, so this matches regardless of
  how a client capitalizes it.
- **`TokenResponse.refresh_token`** (`app/schemas/auth.py`) is a new,
  optional field, populated **only** when `is_mobile_client()` is true.
  Web's response body never includes it — it keeps getting its refresh
  token exclusively via the existing httpOnly cookie. This is the one
  detail to never get wrong here: populating this field unconditionally
  would let any XSS payload on the web app read the refresh token
  straight out of the fetch response, defeating the entire reason that
  cookie is httpOnly in the first place. Don't add a call site that
  passes `refresh_token` to `_issue_tokens()` without checking
  `is_mobile_client()` first.
- **New `RefreshRequest` schema** (`app/schemas/auth.py`): mobile has no
  cookie to read a refresh token from (see MOBILE_SUMMARY.md's token-
  storage-strategy note — mobile deliberately doesn't persist a cookie
  jar), so it sends the refresh token explicitly in the `/auth/refresh`
  request body. Web's refresh flow sends no body at all and is
  unaffected — the `payload` parameter on the `refresh` endpoint is
  `Optional`.
- **CSRF**: `/auth/refresh` and `/auth/logout` moved from
  `Depends(verify_csrf)` to a new `Depends(verify_csrf_unless_mobile)`
  (`app/api/deps.py`). CSRF double-submit exists specifically to stop a
  _browser_ from silently riding a cookie it holds for our site into a
  request from some other site's page. The mobile app never holds that
  cookie meaningfully, so there's no cookie for a hostile page to ride
  in the first place — the check simply doesn't apply to it. Web's CSRF
  enforcement is completely unchanged; `verify_csrf` itself wasn't
  touched, `verify_csrf_unless_mobile` just wraps it with an early
  return for mobile requests.
- **`/auth/register` deliberately NOT changed** — it still only creates
  the account and returns `UserRead`, no auto-login, no tokens. Giving
  mobile a different (auto-login) contract here would mean either two
  diverging behaviors for the same endpoint, or changing web's contract
  too for no reason tied to mobile. The mobile client instead calls
  `/auth/register` then an explicit `/auth/login` afterward — see
  MOBILE_SUMMARY.md's `auth_api.dart` note.
- **No server-side refresh-token revocation exists for either client
  type** — refresh tokens are stateless, signature-verified JWTs, not
  tracked in the DB, so `/auth/logout` is just cookie-clearing (web) or
  a no-op (mobile, which only deletes its local secure-storage copy
  client-side). This was already true before mobile support was added;
  worth remembering if a future change assumes logout revokes anything
  server-side.

### A note on the analytics endpoints

`app/api/v1/endpoints/analytics.py`, four routes, all real-time
aggregation queries (`COUNT`/`GROUP BY`) with no precomputation or
caching layer:

- **`GET /analytics/summary`**: `total_applications`, `active_applications`
  (everything except rejected/withdrawn), `offers_received` (offer +
  accepted — an accepted offer still counts as one received),
  `interviews_scheduled` (interviews with `result=pending`, regardless of
  `scheduled_at`), `response_rate` (applications that moved past
  `applied`, over applications actually submitted — a documented proxy,
  not a tracked metric, since the data model has no explicit "employer
  responded" event; the field's own schema description says so, so it
  surfaces in `/docs`, not just a code comment)
- **`GET /analytics/funnel`**: current-status snapshot counts in pipeline
  order (`saved` → `accepted`), with `rejected`/`withdrawn` broken out
  separately as `off_ramps`. Deliberately **not** a true conversion
  funnel — see the status-history note below for why, and why that's a
  real limitation, not an oversight
- **`GET /analytics/activity`**: monthly application-creation counts,
  zero-filled, `months` query param (1–24, default 6)
- **`GET /analytics/interviews`**: result breakdown + `pass_rate`
  (`passed / (passed + failed)`, excluding pending/cancelled from both
  sides — also documented in the schema, not just here)

**Why real-time instead of precomputed/cached**: per-user data volumes
here are realistically in the hundreds, not millions — a handful of
indexed queries run in single-digit milliseconds. Precomputing (a
nightly rollup table) or caching (Redis, short TTL) would solve a scale
problem this app doesn't have yet, at the cost of either staleness or
added infrastructure. Revisit only if a dashboard load is actually
observed to be slow in practice.

Every query is scoped to `current_user` — same ownership pattern as
every other endpoint (`Application.user_id` direct;
`Interview`/via a join through `Application.user_id`).

### A note on `application_status_history`

An append-only audit log of every `Application.status` transition
(`app/models/application_status_history.py`), written by
`app/services/application_history.py::record_status_change()` inside the
same transaction as the Application create/update endpoints that cause a
transition — mirrors `sync_interview_reminders`'s "service function only
calls `db.add()`, the endpoint's existing commit covers it" shape.

**Not currently read by any analytics endpoint.** This was a deliberate,
discussed decision, not an oversight: a real conversion funnel ("did this
application ever reach `interviewing`") needs to distinguish a genuine
multi-day stay in a status from a same-session accidental mis-click
(e.g. dragging a Kanban card to the wrong column, then back) — the table
records every transition faithfully, including accidental ones, and
intentionally does **not** try to filter or deduplicate them at write
time (see the model's own module docstring, and
`test_application_status_history.py`'s
`test_flip_and_revert_records_both_transitions_undeduplicated`, which
asserts this behavior explicitly so a future pass doesn't "fix" it into
silently deduplicating). That filtering (e.g. a minimum-dwell-time rule
before counting a transition as real) belongs to whatever future reader
of this table implements a true funnel — not to the write path, and not
built yet. Until then, `GET /analytics/funnel` reads `Application.status`
directly as a current-state snapshot, which is immune to the
accidental-toggle problem by construction (it just reflects wherever an
application ended up, same as if the mis-click never happened) — a
correct, if less complete, metric.

**Enum-reuse migration gotcha hit while building this** (worth knowing
before adding any other new table that reuses an existing Postgres enum
type): `sa.Enum(..., create_type=False)` does **not** reliably suppress
`CREATE TYPE` when reusing an already-existing enum for a new table's
column — `create_type` is only reliably honored on
`sqlalchemy.dialects.postgresql.ENUM` specifically, not the generic
`sqlalchemy.Enum`, which silently drops the flag somewhere in its
adaptation into Postgres-native DDL. Confirmed the hard way against this
exact migration (`DuplicateObject: type "application_status" already
exists`, even with `create_type=False` set). Both the model
(`application_status_history.py`) and the migration file import `ENUM`
from `sqlalchemy.dialects.postgresql`, not `Enum` from `sqlalchemy`, for
exactly this reason. This is on top of the existing "Alembic sometimes
needs a manual nudge on enum type changes" note further down this
file — autogenerate reproduces whatever the model says, so if the model
itself uses the wrong class, autogenerate faithfully regenerates the
broken migration too.

### A note on the SQLAlchemy 2.0 query-style migration

Every endpoint file plus `deps.py`, `services/reminders.py`, and
`tasks/reminders.py` — ten files total — moved from the legacy
`db.query(Model).filter(...)` API to 2.0-style
`db.execute(select(Model).where(...))`. `db.query()` still works (2.0
kept it as a supported "legacy" wrapper around `select()`), so this was
a deliberate consistency pass, not a bug fix — done in one mechanical
sweep across every file at once rather than left half-migrated, per
`AI_CONTEXT.md`'s guidance against leaving a codebase in a mixed-style
state. A few non-mechanical translations worth knowing if this pattern
gets extended:

- **Paginated `total` counts**: `Query.count()` has no direct 2.0
  equivalent. Replaced with `db.scalar(select(func.count()).select_from(stmt.subquery()))`,
  where `stmt` is built _without_ `.order_by()`/`.offset()`/`.limit()`
  and those three get chained on separately only for the actual items
  fetch — avoids the count query doing pointless sort work.
  `db.scalar()`'s return type is `int | None` even though `COUNT(*)`
  never actually returns `NULL` — every call site appends `or 0` to
  satisfy both the type checker and defend against a scenario that
  shouldn't occur at runtime.
- **`users.py`'s bulk device-token delete**: the one genuine
  Query-API-specific construct (not just `.filter()` → `.where()`) —
  `db.query(DeviceToken).filter(...).delete()` became
  `db.execute(delete(DeviceToken).where(...))` using SQLAlchemy's
  `delete()` construct.
- **`tasks/reminders.py`'s `and_()`** — dropped. `.where()`, like
  `.filter()` before it, ANDs multiple positional arguments implicitly.
- Selecting individual columns instead of full entities (e.g.
  `select(Application.status, func.count(Application.id))` in the
  analytics endpoints) returns plain `Row` tuples from
  `db.execute(...).all()` — no `.scalars()` on those, since `.scalars()`
  would only unwrap the first column. Building a `dict` from those rows
  should go through a dict comprehension
  (`{status: count for status, count in rows}`), not `dict(rows)`
  directly — the latter is fine at runtime but trips a static-analysis
  overload-resolution false positive on `Row` objects in some type
  checkers (Pyright/Pylance).

Contact used to have a `GET /contacts` directory route here
(`app/api/v1/endpoints/contacts.py::directory_router`) with exactly the
shape the Interview note below still has — nested-only create/update/
delete plus a flat, `ApplicationSummary`-embedding read route. It doesn't
any more: Contact went further and became a fully top-level, user-owned
resource, the same way Document already had — see "A note on Contact /
ApplicationContact" below, including the note on why the many-to-many
join this file used to say was "deliberately deferred" ended up getting
built after all.

### A note on the interviews directory endpoint

`GET /interviews` (`app/api/v1/endpoints/interviews.py::directory_router`)
is the one Interview route that isn't nested under `/applications/{id}`:

- The response embeds a minimal `ApplicationSummary` (company, position,
  `application_name`, status) per interview, via
  `contains_eager(Interview.application)` on the same join used for the
  ownership filter — one query, not N+1. This relies on the join/filter
  staying the actual source of that relationship data, so don't reorder
  the query without care.
- No text `search` param — `Interview` has no name-like field to match
  against. The filter here is `result`
  (`pending`/`passed`/`failed`/`cancelled`), scoped by the same
  `Application.user_id` ownership filter so it can't be used to find
  another user's interviews.
- Create/update/delete remain nested-only; this route is read-only.
- Ordered by `scheduled_at` ascending, matching the nested
  `GET /applications/{id}/interviews` route's ordering. This route is
  paginated regardless — an interview count across every application a
  user has ever tracked has no natural ceiling, same reasoning `/contacts`
  and `/documents` are paginated for now that both are top-level lists.

### A note on Document / ApplicationDocument (documents decoupled from applications)

`Document` used to belong to exactly one `Application`
(`application_id`, `NOT NULL`, `ondelete="CASCADE"`) — the model this
file described for a while, built the same nested way as
Interview/Contact. That's gone.

The trigger was `AtsScore`, not Document itself: it carried its own,
independent `application_id` alongside `resume_analysis_id`, and nothing
anywhere cross-checked that the two actually agreed (i.e. that the
scored application was the same one
`resume_analysis.document.application_id` pointed at) — a caller could
score a resume against a different application's job posting than the
one it was really attached to, with no error, no warning, nothing. The
fix considered first — derive `AtsScore.application_id` server-side
instead of trusting the client-supplied one — doesn't actually close the
gap: `job_description`/`job_url` are always caller-supplied free text,
so even a perfectly-derived link can't verify they're the *right* job.
Rather than keep a link that only ever looked trustworthy,
`AtsScore.application_id` was dropped entirely (see "Job description
sourcing" below) — and since reusing one resume/cover-letter document
against several different job postings over time is a real, common use
case (not a bug to close off), `Document` itself was decoupled from
`Application` too, rather than leaving it as the one remaining
single-application assumption in an otherwise-decoupled feature.

- **`Document` is now top-level and user-owned** (`user_id`, direct FK,
  same ownership pattern as `ResumeAnalysis`/`AtsScore`) — reachable at
  `/documents`, not nested under any application. Upload, list (search by
  `file_name`, filter by `file_type`), get, patch, delete, and download
  all moved there from the old `/applications/{application_id}/documents`.
  An unattached document (never linked to any application) is a normal,
  supported state, not an edge case.
- **`ApplicationDocument`** (`app/models/application_document.py`) is the
  new many-to-many join — `application_id` + `document_id`, unique
  together, both `ondelete="CASCADE"`.
  `POST`/`GET`/`DELETE /applications/{application_id}/documents`
  (`app/api/v1/endpoints/application_documents.py`) attach, list, and
  detach; ownership is checked on **both** sides (the application via
  `Application.user_id`, the document via `Document.user_id`), since
  attaching requires owning both ends of the link. The same document can
  be attached to several applications at once (e.g. one base resume
  tailored and reused across many job postings) — this reuse case was
  the actual point of decoupling, not just an incidental side effect.
- **Deleting an application no longer deletes its documents.** Only the
  `ApplicationDocument` join rows cascade-delete; the document rows
  themselves are untouched, since a document is the user's own resource
  now, not the application's. Deleting a document, conversely, still
  cascade-deletes its `ApplicationDocument` links (and, unchanged, its
  `ResumeAnalysis`/`AtsScore` rows via the existing FK chain).
- **`app/services/r2.py`'s object key format changed** —
  `_build_object_key` dropped its `application_id` parameter entirely
  (`users/{user_id}/applications/{application_id}/...` became
  `users/{user_id}/documents/...`), since a document is no longer
  created in the context of one application to namespace the key by.
- **The old flat directory concept is gone, not moved.** There used to
  be a nested `GET /applications/{id}/documents` *and* a separate
  cross-application `GET /documents` directory embedding the parent
  application's company/position/status per row
  (`DocumentWithApplicationRead`, via `contains_eager(Document.application)`
  on the ownership join). Now that `/documents` is simply the one and
  only top-level list, that embed doesn't make sense any more — a
  document can belong to zero, one, or several applications, so there's
  no single parent left to embed. The old company-name search dropped
  for the same reason; `search` on `/documents` now only matches
  `file_name`.

### A note on Contact / ApplicationContact (contacts decoupled from applications)

`Contact` used to belong to exactly one `Application` (`application_id`,
`NOT NULL`, `ondelete="CASCADE"`) — the same nested shape Interview still
has. That's gone, following the exact precedent Document set above.

The trigger this time was product, not a data-integrity gap like
`AtsScore`'s: deleting an application cascade-deleted every contact
attached to it, with no way to keep a recruiter or hiring manager around
after the application they were originally tied to got deleted or after
the same person turned out to be relevant to a different application too
(e.g. a recruiter who reaches out about a second role). This is exactly
the many-to-many shape this file previously called "considered, and
deliberately deferred" for Contact, on the reasoning that "nothing in the
roadmap currently calls for contact reuse across applications" — that
stopped being true once users wanted their contact directory to survive
application deletions, so the deferred design got built.

- **`Contact` is now top-level and user-owned** (`user_id`, direct FK,
  same ownership pattern as `Document`/`ResumeAnalysis`/`AtsScore`) —
  reachable at `/contacts`, not nested under any application. Create,
  list (paginated, searchable by `name`), get, patch, delete all moved
  there from the old `/applications/{application_id}/contacts`. A
  contact with no application attached (never linked, or its only
  application was since deleted) is a normal, supported state, not an
  edge case — this is the whole point of the change.
- **`ApplicationContact`** (`app/models/application_contact.py`) is the
  new many-to-many join — `application_id` + `contact_id`, unique
  together, both `ondelete="CASCADE"`.
  `POST`/`GET`/`DELETE /applications/{application_id}/contacts`
  (`app/api/v1/endpoints/application_contacts.py`) attach, list, and
  detach; ownership is checked on **both** sides (the application via
  `Application.user_id`, the contact via `Contact.user_id`), since
  attaching requires owning both ends of the link. The same contact can
  be attached to several applications at once now.
- **Deleting an application no longer deletes its contacts.** Only the
  `ApplicationContact` join rows cascade-delete; the contact rows
  themselves are untouched, since a contact is the user's own resource
  now, not the application's. Deleting a contact, conversely, still
  cascade-deletes its `ApplicationContact` links.
- **The old flat directory concept is gone, not moved** — same as
  Document's `DocumentWithApplicationRead`. There used to be a nested
  `GET /applications/{id}/contacts` *and* a separate cross-application
  `GET /contacts` directory embedding the parent application's company/
  position/status per row (`ContactWithApplicationRead`, via
  `contains_eager(Contact.application)` on the ownership join, plus its
  `ApplicationSummary`). Now that `/contacts` is simply the one and only
  top-level list, that embed doesn't make sense any more — a contact can
  belong to zero, one, or several applications, so there's no single
  parent left to embed. The old company-name search dropped for the same
  reason; `search` on `/contacts` now only matches `name`.
- The nested `GET /applications/{id}/contacts` route used to be
  deliberately unpaginated (small, bounded list). It's paginated now,
  reusing `ContactListResponse` — same call Document/`ApplicationDocument`
  made, for consistency and because "how many contacts one application
  accumulates" no longer has as tight a natural ceiling once contacts get
  reused across applications instead of created fresh each time.

### A note on the integration test setup

`backend/tests/conftest.py` establishes the pattern every future endpoint
test (Applications, Interviews, Documents) can reuse as-is:

- Real Postgres only, via `Settings.TEST_DATABASE_URL` (defaults to a
  separate `job_tracker_test` database) — same constraint as the
  migration note below: Postgres-specific `UUID` and enum types don't
  behave the same, or at all, against an in-memory SQLite DB.
- Per-test isolation via SAVEPOINT nesting rather than truncating tables
  between tests: each test gets its own connection + outer transaction,
  with a nested SAVEPOINT recreated every time endpoint code calls
  `db.commit()` (via an `after_transaction_end` listener), and the outer
  transaction rolls back at teardown. Nothing a test writes is ever
  actually persisted, and tests never see each other's data.
- The `client` (`TestClient`), `make_user`, and `auth_headers` fixtures go
  through the app's real dependency-injection and JWT path
  (`get_current_user`, `create_access_token`) rather than mocking them,
  so these are true integration tests, not schema tests with an HTTP
  wrapper on top.
- `backend-ci.yml`'s `test` job now runs a `postgres:16-alpine` service
  container with `TEST_DATABASE_URL` set as a job-level env var. Locally,
  set `TEST_DATABASE_URL` in `.env.local` (or rely on the default) —
  never point it at the same database `DATABASE_URL` uses, since tables
  are created/dropped every test session.

### A note on the first migration

The initial schema migration went through a few iterations before landing
correctly — worth knowing about since it's the kind of thing that can bite
again:

1. A hand-written first pass missed `nullable=False` on two enum columns
   (`interviews.result`, `documents.file_type`).
2. Once regenerated via `alembic revision --autogenerate` against a real
   Postgres instance, that class of error went away — the models are now
   the actual source of truth for the schema, not a manual transcription.
3. `Interview.result` actually uses `server_default=InterviewResult.PENDING`
   (the raw enum member, not `.value`) — this note previously claimed a
   Python-side `default=` instead, which didn't match the code. Confirmed
   via `backend/tests/test_interviews_endpoints.py::TestInterviewResultServerDefault`,
   which inserts a row through the ORM with `result` omitted entirely: it
   resolves to `InterviewResult.PENDING` correctly, so the raw-enum
   `server_default` does compile into valid DDL for this Postgres enum
   column, despite looking like it shouldn't. `Document.file_type` wasn't
   re-checked against its actual model file, so don't assume the same
   holds there without looking.
4. If enum columns are ever added to another model, double check
   `values_callable` is set so Postgres stores the enum's lowercase
   `.value` (`"resume"`) rather than the uppercase `.name` (`"RESUME"`) —
   otherwise API-level values and DB-level values silently diverge.

### A note on the AWS S3 → Cloudflare R2 migration

Object storage is Cloudflare R2, not AWS S3 — this was decided and
executed in v0.5.0 before S3 ever carried real traffic (see CHANGELOG.md),
so there was no data to migrate, only the client/config layer:

- `app/services/s3.py` was renamed to `app/services/r2.py`
  (`_s3_client()` → `_r2_client()`); `upload_document`, `delete_document`,
  and `generate_download_url` kept their names and logic unchanged, since
  R2 implements the same S3-compatible API for `put_object`,
  `delete_object`, and `generate_presigned_url`.
- The `boto3.client("s3", ...)` call still says `"s3"` — that just tells
  boto3 which client protocol to speak, not which company. The actual
  destination is controlled by `endpoint_url`
  (`https://{R2_ACCOUNT_ID}.r2.cloudflarestorage.com`) and by
  `region_name="auto"`, which R2 requires as a literal string (it has no
  AWS-style regions).
- Config: `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_REGION` /
  `AWS_S3_BUCKET` were replaced outright with `R2_ACCOUNT_ID` /
  `R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY` / `R2_BUCKET` — no AWS
  account, IAM key, or AWS billing relationship exists or is needed
  anywhere in this codebase. R2 credentials come from the Cloudflare
  dashboard (R2 → Manage R2 API Tokens), scoped to the one bucket.
- Test mocking boundary moved from `app.services.s3._s3_client` to
  `app.services.r2._r2_client`; the fixture is now `fake_r2_client`. The
  same "only the network client is mocked" property still holds —
  content-type validation, chunked size-limit enforcement, and object-key
  construction all still run for real in `test_documents_endpoints.py`.
- Presigned URL expiry (5 min) and the chunked upload size-limit check
  were confirmed to behave identically against R2's S3-compatible API —
  no parity gap found, so no behavior changed beyond client construction.

- S3 service and config still remain but unused (for fallback and study purpose)

## Interview reminder system (Phase A: email, Phase B: push, Phase C: per-user preferences + in-app feed)

Implements the plan from TODO.md's "Reminder system" entry. Celery/Redis
(already wired up in Docker Compose) now run one real periodic task;
this is the first thing to actually use them.

**Phase C** (this pass) makes two changes on top of Phases A/B: the
reminder lead time is now per-user-configurable instead of one hardcoded
global value, and every reminder gets a third channel — `IN_APP` — that
writes to a new `Notification` feed (`/notifications`) instead of calling
an external provider. Both preferences and the new channel are covered
in their own sections below ("`UserSettings`..." and "In-app notification
feed..."); this section's existing subsections are updated in place
rather than duplicated.

### Data model

- **`InterviewReminder`** (`app/models/interview_reminder.py`):
  `interview_id` (FK, cascade delete), `remind_at`, `sent_at` (nullable
  — the idempotency guard: the beat task only ever selects
  `remind_at <= now() AND sent_at IS NULL`, so a re-run can't
  double-send), `channel` (`email` / `push` / `in_app` as of Phase C,
  `server_default` — not a Python-side `default` — matching
  `Interview.result`'s precedent, since this column needs to be correct
  even for a row inserted outside the ORM's one ordinary code path; see
  the migration note below for why this specific choice mattered enough
  to redo once). `in_app` was added to the existing Postgres enum via
  `ALTER TYPE ... ADD VALUE` in its own migration, separate from the one
  introducing `UserSettings`/`Notification` — Postgres forbids using a
  newly-added enum value in the same transaction that added it. One row
  per `(interview, channel)` pending reminder — see
  `sync_interview_reminders` below for why every channel always gets a
  row regardless of whether the user has push set up (or any preference
  turned off) yet.
- **`User.timezone`** (nullable `String`, IANA name e.g.
  `America/New_York`, UTC fallback everywhere it's read): populated from
  the _client's own reported timezone_ (web: `Intl.DateTimeFormat`,
  mobile: `flutter_timezone`) at register/login/refresh — see "Timezone
  reporting" below — not inferred server-side. Used only for _display_
  (formatting a reminder email's "When:" line in the user's local time);
  `remind_at`'s actual scheduling math is pure UTC arithmetic and doesn't
  need it.
- **`DeviceToken`** (`app/models/device_token.py`, Phase B): `user_id`
  (FK, cascade delete), `platform` (`android`/`ios` — only `android` is
  ever sent today, see MOBILE_SUMMARY.md), `token` (**unique**, not
  unique-per-user — a token is globally unique per app install by FCM's
  own contract, so re-registering an already-known token reassigns it to
  whichever user most recently logged into that device rather than
  leaving a stale row under the previous owner), `last_seen_at`.

### `app/services/reminders.py` — keeping reminders in sync with interviews

`sync_interview_reminders(db, interview)`, called from the interview
create/update endpoints (same transaction, no extra commit boundary
beyond the one already needed to get `interview.id`): computes
`remind_at = scheduled_at - lead_hours`, where `lead_hours` is
`interview.application.user.settings.reminder_lead_hours` if the user has
set one, else `settings.REMINDER_LEAD_HOURS` (the global default — every
account keeps its current behavior until it opts into an override; the
table itself still doesn't assume a single lead time, multi-lead-time
_per interview_ is still deferred — see "Not yet implemented" below) —
and creates/moves/deletes **one pending row per channel** (`EMAIL`,
`PUSH`, and `IN_APP`, all three, unconditionally):

- Cancelled interview, or a `remind_at` that's already in the past
  (same-day scheduling, or a reschedule that moved it closer than the
  lead time) → no pending reminder on any channel. Deliberately not
  sending an immediate "starting soon" variant in the too-late case;
  revisit if product wants that later.
- Push gets a row **even if the user has zero registered devices**, and
  as of Phase C every channel gets a row **even if the user has turned
  that channel, or notifications overall, off** — this is a deliberate,
  now-generalized scope decision (originally Option A for push alone):
  keeps this function's only responsibility "does this interview need a
  reminder", with zero knowledge of device-token *or preference* state.
  Whether there's actually anything to send/write is a _send-time_
  concern, handled by the task below, not a scheduling-time one — so
  flipping a preference takes effect immediately for interviews already
  scheduled, not just ones synced after the change.

### `app/tasks/reminders.py` — the Celery beat task

`send_due_reminders`, scheduled every 10 minutes
(`app/core/celery_app.py`, comfortably inside TODO.md's "every 5-15 min"
target — idempotency is what actually makes a late/duplicate tick
harmless, not the schedule's precision). Queries every
`remind_at <= now() AND sent_at IS NULL` row regardless of channel
(eager-loading `interview.application.user.settings` to avoid an N+1 per
row), then for each due reminder first checks `_channel_enabled(user,
channel)` against `UserSettings` (master switch, then the per-channel
flag) — disabled → mark `sent_at` without dispatching anything, same
"nothing to send, nothing to retry" shape push already used for zero
devices, just gated on a preference instead. Otherwise dispatches per-row:

- **`channel == EMAIL`**: builds a subject/html/text via
  `_build_email`, sends through `app/services/email.py`.
- **`channel == PUSH`**: fans out to _every_ device the user has
  registered (`_send_push_reminder`). Zero devices → nothing to send,
  nothing to retry, marked sent. A token FCM reports as no-longer-valid
  (`PushResult.INVALID_TOKEN`) gets pruned from `device_tokens` right
  there, so one dead install can't cause every future reminder to retry
  against it forever. A transient failure (`PushResult.FAILED`) leaves
  the reminder unsent, retried next tick.
- **`channel == IN_APP`** (Phase C): builds a `(title, body)` via
  `_build_in_app` (same `_interview_summary` pieces the other two
  builders use) and writes a `Notification` row — see "In-app
  notification feed" below. No external provider, so unlike email/push
  this always succeeds once the DB write does; a DB error propagates and
  leaves the reminder unsent for retry next tick, same as any other
  exception in this loop.

Each reminder commits independently (`sent_at` stamped per-row, not
batched at the end of the loop) — one bad send shouldn't leave every
_other_ already-sent reminder in the same run un-stamped, which would
re-send them all next tick.

### `app/services/email.py` — email, Resend (prod) / SMTP (local, MailHog)

Same "isolate the network client behind one module" shape as
`r2.py`. `EMAIL_PROVIDER` config switches between:

- **`resend`** (staging/prod): a direct HTTP call via `httpx`, not the
  `resend` SDK — the one endpoint needed (`POST /emails`) didn't justify
  a new dependency.
- **`smtp`** (local dev default): stdlib `smtplib` against MailHog
  (`docker-compose.yml`'s `mailhog` service — SMTP on `1025`, web UI on
  `8025`; nothing sent locally ever reaches a real inbox).

Both backends catch and log send failures rather than raising — a
failed send for one reminder shouldn't crash the batch the Celery task
is working through.

### `app/services/push.py` — push, Firebase Admin SDK

Same isolation shape again. Lazily initializes the `firebase_admin` app
on first use (not at import time — importing this module must not crash
startup just because Firebase isn't configured yet, e.g. local dev
before a Firebase project exists). Credentials come from either
`FIREBASE_SERVICE_ACCOUNT_JSON` (raw JSON as one env var — the fit for
Railway/Render, which have no first-class "mount a secret file"
primitive) or `FIREBASE_SERVICE_ACCOUNT_PATH` (a file path — the fit for
local Docker Compose, mounting the downloaded service-account file
rather than ever putting its contents in `.env.local`). `send_push()`
returns a `PushResult` enum (`SENT` / `INVALID_TOKEN` / `FAILED`) rather
than a bare bool specifically so the caller (`tasks/reminders.py`) can
tell "prune this token" apart from "retry later" — collapsing that
distinction into a bool would have made stale-token cleanup impossible
without a second round-trip.

### Device-token endpoints (Phase B)

`POST /users/me/device-tokens` and `DELETE /users/me/device-tokens/{token}`
(`app/api/v1/endpoints/users.py`), alongside the existing `/users/me`.
Register upserts by `token` (see the model note above on why), called
by the mobile client on every login/register/silent-restore (not just a
fresh login — see MOBILE_SUMMARY.md); delete is a no-op-not-a-404 if the
token's already gone, since logout must never visibly fail over this.

### Timezone reporting (register/login/refresh)

`app/utils/timezone.py`'s `is_valid_timezone()` is the single shared
IANA-name check, used by every call site below rather than duplicated
per schema. Wired into `UserCreate.timezone` (register),
`LoginRequest.timezone`, and `RefreshRequest.timezone` (`app/schemas/`),
applied in `app/api/v1/endpoints/auth.py`'s `_maybe_update_timezone()` —
silently ignores missing/invalid values and skips the write if
unchanged (this runs on _every_ login/refresh, not worth a DB
round-trip for a no-op). **`RefreshRequest`'s body is no longer
mobile-only** — web's refresh call now also sends an optional body
(previously none at all) purely to carry `timezone`; `refresh_token`
itself is still mobile-only, per the original cookie-vs-explicit-token
split. As of Phase C, `_maybe_update_timezone()` first checks
`user.timezone_is_manual` (`User`, new column) and no-ops entirely when
`True` — otherwise an explicit `PATCH /users/me` timezone choice (see
below) would get silently overwritten by this same auto-detect on the
user's very next login. Only `PATCH /users/me` ever sets the flag; an
explicit `{"timezone": null}` there releases it again without touching
the stored value, letting auto-detect resume.

## Account settings & notification preferences

Everything in this section is **backend only** — no web UI calls any of
it yet (see "Not yet implemented" below). Mobile has its own separate,
even more minimal "Settings screen" (logout only) — see MOBILE_SUMMARY.md.

### `app/models/user_settings.py` — `UserSettings`, a dedicated preferences table

Deliberately **not** columns bolted onto `User`: `users` is read on every
authenticated request (`get_current_user`) and stays focused on
identity/auth, while preferences are a separate, independently-growing
concern — same "separate table per concern" instinct as
`Document`/`ApplicationDocument` or `Interview`/`InterviewReminder`.
Typed columns throughout (no JSONB blob, no key-value/EAV table), matching
every other model in this codebase; the cost is a migration per new
setting, accepted as cheap relative to the alternative.

1:1 with `User` (`user_id` FK, `unique=True`), own `id`/timestamps like
every other model rather than making `user_id` the primary key itself.
Fields: `reminder_lead_hours` (nullable — `NULL` means "use the global
`settings.REMINDER_LEAD_HOURS`"), `notifications_enabled` (master switch),
`email_notifications_enabled`, `push_notifications_enabled` (all default
`True`, so existing accounts' behavior is unchanged until they opt out).

**Deliberately no `in_app_notifications_enabled`.** Email and push both
reach the user *outside* this app (an inbox, a device buzz/badge), so
opting out of that intrusion independently of "notifications at all" is
a real, distinct choice — worth its own flag. The in-app feed is purely
pull-based (a list you only see if you open the bell), with no external
interruption to opt out of, so it's on whenever `notifications_enabled`
(the master switch) is, with no finer-grained control — same pattern
GitHub/Slack use (their notification center has no independent opt-out;
only email/push do). A `user_settings.in_app_notifications_enabled`
column existed briefly during development and was dropped in a follow-up
migration (`0537a87e67b9`) once this reasoning held up — flagged here so
it isn't re-added without re-deriving why it was removed.

**Every user always has exactly one row** — created in
`POST /auth/register` alongside the new `User`, and backfilled for every
pre-existing account by the migration that introduced the table. Code
that reads it (`app/tasks/reminders.py::_channel_enabled`,
`app/services/reminders.py::_compute_remind_at`) still fails open on a
genuinely missing row rather than trusting that invariant blindly.

`GET`/`PATCH /users/me/settings` (`app/api/v1/endpoints/users.py`) read/
update it — `PATCH` applies via `exclude_unset`, so an explicit
`{"reminder_lead_hours": null}` resets to the global default while an
*omitted* field is left untouched, same distinction `documents.py`'s
`PATCH` already relies on. `reminder_lead_hours` is bounded `1..168`
(1 hour to 1 week) at the schema level.

### Profile, password, avatar, and account-deletion endpoints (`app/api/v1/endpoints/users.py`)

All bearer-authenticated (`get_current_user`) — none of these need CSRF,
since that only guards the two cookie-authenticated endpoints
(`/auth/refresh`, `/auth/logout`).

- **`PATCH /users/me`** (`UserProfileUpdate`: `first_name`/`last_name`/
  `timezone`) — a schema deliberately separate from the pre-existing,
  previously-unwired `UserUpdate`, which also has `avatar_url`; a client
  must never be able to set that field directly (only the avatar
  endpoints below control it, since they own the underlying R2 key).
  `UserRead` now returns `timezone`/`timezone_is_manual` too (previously
  write-only from a client's perspective — `User.timezone` existed since
  the original auto-detect work, but no response ever included it) — a
  client can now actually show/edit the stored value instead of guessing.
- **`POST /users/me/password`** (`current_password`/`new_password`) —
  requires the current password even though the request is already
  bearer-authenticated; a change like this shouldn't be possible from
  just a leaked access token alone. `400` (not `401`) on mismatch — this
  is a bad form input on an authenticated request, not a credentials
  failure.
- **`POST /users/me/avatar`** / **`DELETE /users/me/avatar`** — see the
  R2 section below.
- **`DELETE /users/me`** (`password`) — same re-proof-of-password
  reasoning as the password change, for an irreversible action. Before
  deleting the row: queries `Document` directly (`Document.user_id ==
  current_user.id`) — **not** via a `User.documents` relationship, which
  doesn't exist — and calls `r2.delete_document()` per row, plus
  `r2.delete_avatar()` if set. This matters: the DB-level cascade
  (`ondelete="CASCADE"` on the various FKs, plus `cascade="all,
  delete-orphan"` on `User.applications`/`device_tokens`/`settings`/
  `notifications`) cleans up Postgres rows once `db.delete(user)` runs,
  but does nothing about files actually sitting in R2 — skipping this
  would permanently orphan every uploaded resume (real PII) in the
  bucket. (A `User.documents` *relationship* was tried first and
  reverted — see the git history around
  `fix(backend): avoid ORM cascade-null error...` — iterating it caused
  SQLAlchemy to try nulling `documents.user_id`, a `NOT NULL` column, on
  flush, since the relationship had no delete-cascade configured; a
  direct query sidesteps the ORM's child-disassociation behavior
  entirely instead of fighting it.) Finishes with `clear_auth_cookies()`,
  the same helper `/auth/logout` uses.

### Avatar upload (`app/services/r2.py`)

Mirrors `upload_document`/`delete_document`/`generate_download_url`, but
simpler because an avatar is 1:1 with a user, not a list:
`AVATAR_ALLOWED_CONTENT_TYPES` (`image/jpeg`/`png`/`webp`, a separate
allow-list from documents' PDF/Word one), a **fixed** per-user object key
(`users/{user_id}/avatar`, no random suffix) so a re-upload just
overwrites the same object — no separate "delete the old one" step ever
needed — and a new `settings.MAX_AVATAR_SIZE_MB` (2, vs. documents' 10).
`generate_download_url` gained an optional `expires_in` param (existing
document call sites unaffected): avatars presign for `AVATAR_URL_EXPIRY_SECONDS`
(1 hour, vs. documents' 5 minutes) since they back a persistent `<img>`
tag rather than a one-shot download link, and are far lower-sensitivity
than a resume. `GET/PATCH/POST/DELETE /users/me*`'s responses all swap
the stored object key for a presigned URL via a shared `_serialize_user()`
helper before returning `UserRead`.

## In-app notification feed ("bell icon" backend)

A distinct concept from `UserSettings` above: that table holds delivery
*preferences*, this is the actual feed of notification *events* a user
sees. Web has a bell icon consuming this (`NotificationBell.vue` — see
WEBAPP_SUMMARY.md's "Account settings & notifications"); mobile doesn't
yet.

### `app/models/notification.py` — `Notification`

`user_id` (FK, cascade delete), `type` (`NotificationType` enum — just
`INTERVIEW_REMINDER` today, the only producer; add more values as real
producers appear, not speculatively), `title`/`body` (plain strings,
pre-rendered at write time — same approach the email/push builders in
`tasks/reminders.py` already use), optional `application_id`/
`interview_id` (nullable deep-link targets for the eventual bell UI —
independent FKs rather than one polymorphic "entity_id", since only
these two exist so far), `read_at` (nullable — `NULL` = unread).
Composite index on `(user_id, read_at)`: both the unread-count query and
the list view's `status=unread`/`status=read` filter filter on exactly
this pair.

The only producer is `app/tasks/reminders.py::send_due_reminders`'s
`IN_APP` branch (see above) — this module itself never creates rows, only
reads/marks them read.

### `/notifications` endpoints (`app/api/v1/endpoints/notifications.py`)

Top-level, user-owned, read-mostly — same shape as `documents.py`:
`GET /notifications` (paginated, `status=all|unread|read` filter —
originally a plain `unread_only: bool`, widened once the web bell
popover needed a Read tab too, with no way to express "read-only"
otherwise; additive query-shape change, nothing else called this
endpoint yet — see CHANGELOG.md), newest first,
`GET /notifications/unread-count` (a cheap, dedicated count query for a
bell badge to poll), `POST /notifications/{id}/read` (ownership-checked,
idempotent), `POST /notifications/read-all` (bulk `UPDATE`, not a loop of
loaded instances — same reasoning `users.py::delete_device_token` uses
for its bulk `DELETE`).

### Delivery mechanism: polling, not real-time push

Deliberately **not** WebSockets/SSE. The eventual bell UI is expected to
poll `GET /notifications/unread-count` on an interval plus on page
load/focus — matching an existing precedent in the web frontend
(`stores/resumeAnalyses.ts`/`atsScores.ts` already poll for async AI-tool
status). Also bounded by reality: `send_due_reminders` itself only runs
every 10 minutes, so a `Notification` row is never created more often
than that regardless of delivery mechanism — real-time push would add
first-of-its-kind infrastructure to this codebase (a Celery-worker→web-
process pub/sub bridge over Redis) to shave latency off a signal that's
already on a 10-minute cadence. Purely a frontend decision either way;
nothing here changes because of it.

### Two decisions worth remembering if this file gets extended

- **`InterviewReminder.channel` uses `server_default`, not `default`.**
  Originally written with a Python-side `default=`, corrected once it
  became clear the whole point of this column is that Phase B (and any
  future direct-SQL/backfill/other-ORM-session write) needs "email is
  the fallback" to be a property of the table itself, not of
  `sync_interview_reminders` remembering to set it — matches
  `Interview.result`'s existing precedent in this same file family, not
  `Application.status`'s Python-side default.

## AI features (Resume Parser + ATS Score)

Backend-only so far (no web/mobile UI yet — see TODO.md's "AI Features"
section and `docs/AI_FEATURES.md`). The first two of five planned AI
features, chosen as the smallest dependency-first slice: Job Match,
Cover Letter, and Interview Coach all consume a parsed resume the same
way ATS Score does, so this pass proves that pattern once rather than
building all five in parallel. LLM provider is Google Gemini, via the
`google-genai` SDK — the first outbound AI-provider call in this
codebase.

### Data model — `ResumeAnalysis` and `AtsScore`

Both are **top-level, user-owned resources** (`app/models/resume_analysis.py`,
`app/models/ats_score.py`), like `Application` and (now) `Document`/
`Contact` — not nested under `/applications/{id}/` the way `Interview`
is, so ownership is a direct `user_id` FK equality check rather than a
join through `Application` → `User`. Deliberate divergence from the
nested-resource convention `Interview`/`ApplicationDocument`/
`ApplicationContact` use in this file: these resources aren't reached
via an application-scoped URL, so anchoring ownership directly to
`user_id` is actually more consistent with `Application`'s own pattern,
not less.

Both are async by design (create → `pending` row → Celery task fills it
in → poll `GET .../{id}`) — the first *per-request-dispatched* Celery
tasks in this codebase (`send_due_reminders` is beat-scheduled, not
triggered by an API call). `ResumeAnalysis.status`/`AtsScore.status`
share one new Postgres enum, `ai_job_status`
(`pending`/`processing`/`completed`/`failed`) — reused across the two
tables the same `create_type=False`-on-`postgresql.ENUM` way
`application_status_history` reuses `application_status` (see that
section above). Same gotcha bit again while writing this migration:
Alembic's autogenerate rendered `ats_scores.status` as a plain
`postgresql.ENUM(...)` with `create_type=False` silently dropped, which
would have re-run `CREATE TYPE ai_job_status` and failed with
`DuplicateObject` — fixed by hand in
`alembic/versions/06abe39a184c_resume_analyses_and_ats_scores.py`, same
manual-nudge treatment as that earlier migration. That migration's
`downgrade()` also explicitly drops the enum type (`DROP TABLE` doesn't
do this in Postgres) so a downgrade → upgrade cycle doesn't collide with
a leftover type — confirmed by actually running that cycle, not just
inspecting the file.

`ResumeAnalysis` stores both `raw_text` (the full text extracted from
the resume file) and `parsed_data` (the structured `ParsedResume`
summary) — ATS Score matches against `raw_text`, not the structured
summary, since `ParsedResume`'s fixed schema can drop nuance (exact
phrasing, certifications, a projects section) a real ATS keyword match
would care about. `ResumeAnalysis.completed_at` is set only when
`status` transitions to `COMPLETED` (`app/tasks/ai.py::parse_resume_task`)
— stays `NULL` on a failed run, distinct from `created_at` since parsing
is async and the two can be seconds or minutes apart.

### `analysis_name`, `scored_at`, and server-side `document_file_name` joins (added after initial launch)

Three small follow-up additions, all still within this same AI Features pass:

- **`ResumeAnalysis.analysis_name`** (nullable `String(255)`) — auto-generated
  by `app/tasks/ai.py::_generate_analysis_name()` in the same commit as the
  `COMPLETED` transition: a slugified source file name + the completion
  timestamp (`YYYYMMDD_HHMMSS`) + a 6-char random hex suffix, e.g.
  `resume_20260817_143205_a1b2c3`. The random suffix exists so two analyses
  of the *same* file completing in the same second still get distinct names —
  deliberately **not** DB-uniqueness-enforced, since the field is also
  user-editable afterward (`PATCH /ai/resume-analyses/{id}`,
  `ResumeAnalysisUpdate` — the only editable field) and a unique constraint
  would fight that. Stays `NULL` on a failed run, same lifecycle as
  `completed_at`.
- **`AtsScore.scored_at`** — identical shape/reasoning to
  `ResumeAnalysis.completed_at`, set by `score_ats_task` in the same commit
  as its own `COMPLETED` transition.
- **`document_file_name` computed properties** (`ResumeAnalysis.document_file_name`;
  `AtsScore.document_file_name`, one hop further via `resume_analysis.document`;
  `AtsScore.analysis_name`, one hop via `resume_analysis.analysis_name`) —
  plain Python `@property`s, not DB columns, serialized into
  `ResumeAnalysisRead`/`AtsScoreRead` via Pydantic's `from_attributes=True`
  (which happily resolves a property through `getattr`, same as any other
  attribute). These exist specifically to remove a frontend-only join that
  used to live in `ResumeAnalysesView.vue`/`AtsScoresView.vue` (fetch up to
  100 documents/analyses client-side, build a lookup map) — see
  WEBAPP_SUMMARY.md's "AI Tools" section. That join silently mislabeled
  anything past the 100-item cap; joining server-side removes both the cap
  and the extra round trips. `AtsScore.analysis_name` raises `RuntimeError`
  rather than returning `None` if the underlying
  `resume_analysis.analysis_name` is somehow `NULL` — should be genuinely
  impossible, since `create_ats_score` requires
  `resume_analysis.status == COMPLETED`, which is set in the same commit as
  `analysis_name`. List/get endpoints eager-load the relevant relationship
  chain with `joinedload(...)` (a many-to-one join, so no row-multiplication
  risk the way `joinedload` on a one-to-many collection would carry) —
  without it, serializing a 100-row list would issue one extra lazy-load
  query per row per property.
- **`GET /ai/resume-analyses` gained `status`/`search` query params** —
  `status` (aliased internally to `status_filter` to avoid shadowing the
  `fastapi.status` module already imported in this file, same fix
  `applications.py::list_applications` already uses) filters by exact
  `AIJobStatus`; `search` does an `ilike` match against `analysis_name`.
  Added specifically to replace `NewAtsScoreDialog.vue`'s resume picker,
  which used to fetch the single most recent page (`page_size=100`, the
  backend's max) and filter to `status="completed"` client-side — a user
  with more than 100 completed analyses could never find the rest. The
  picker is now a live-searched `AutoComplete` hitting these two params
  directly (`status=completed&search=...`).

### Job description sourcing — pasted description or pasted URL, no `Application` link

**Superseded design, worth knowing the history of.** This feature
originally sourced the job description from the *linked Application's*
`job_url` (`AtsScoreCreate.application_id`) when nothing was pasted
directly. That was dropped entirely, not fixed — see "A note on
Document / ApplicationDocument" above for the full reasoning, but the
short version: nothing ever cross-checked that `application_id` against
the resume's actual application (reachable via
`resume_analysis.document`), so a caller could score a resume against a
different application's posting than the one it was really for — and
even a correctly-derived link wouldn't have caught a pasted
description/URL that just doesn't match the real job, since that content
is always caller-supplied and unverifiable either way. `AtsScore`
stopped pretending to enforce a check that was never actually
enforceable.

`POST /ai/ats-scores` now takes `resume_analysis_id` plus either
`job_description` or `job_url` directly in the payload — no
`application_id` anywhere on this resource. If `job_description` is
pasted, it's used as-is (`job_description_source="pasted"`) and always
wins if both are sent, and `job_url` is discarded rather than also being
persisted alongside a description that's already replacing it. If only
`job_url` is sent, `job_description_source="url"` is recorded
immediately at creation time (the URL itself is known up front now,
unlike the old design where it was only known once the application row
was dereferenced) and `AtsScore.job_description` starts `NULL`;
`app/tasks/ai.py::score_ats_task` resolves it at run time via
`app/services/ai/job_description_fetcher.py` and backfills
`job_description` (leaving `job_description_source` as `"url"`). A
fetch/extraction failure (dead link, JS-rendered page with no
server-side text, or a site that blocks non-browser requests — all
common for boards like LinkedIn/Indeed, expect this to be the *common*
path for some sites, not a rare edge case) marks the row `status=failed`
with an `error_message` asking the caller to resubmit with
`job_description` pasted directly — reuses the existing
failed/`error_message` convention rather than inventing a new API shape
for this fallback signal. The create endpoint rejects `422` up front if
neither `job_description` nor `job_url` is present, so a doomed-to-fail
task is never dispatched.

### SSRF: fetching `job_url` server-side

`job_description_fetcher.py` is the first place this backend fetches a
user-supplied URL from server-side code — every other outbound call (R2,
Resend, FCM, now Gemini) hits a fixed, trusted endpoint. Without
safeguards, a malicious `job_url` (a cloud metadata endpoint, an internal
Docker service name, etc.) could turn this into a probe against internal
infrastructure the Celery worker container can reach. Mitigations, all
in that one module:

- scheme allowlist (`http`/`https` only)
- the hostname's resolved IP(s) must all be public — rejects
  private/loopback/link-local/multicast/reserved ranges, re-checked on
  **every redirect hop**, not just the original URL, since a public URL
  can still redirect to an internal one (`follow_redirects=False`, a
  manually-capped 3-hop loop)
- a 10s timeout and a capped, chunked response read (2MB) — same
  "don't trust the server, don't buffer an unbounded body" reasoning as
  `r2.py`'s `upload_document` chunked size-limit check

**Known, accepted gap**: this isn't a full defense against DNS-rebinding
— the IP checked by `_is_safe_url()` isn't pinned for the actual
connection `httpx` makes moments later. Closing that fully would mean
connecting to a pre-resolved IP directly with the `Host` header set
separately, a meaningfully bigger change than this pass's threat model
(an authenticated user fetching their own saved `job_url`, not an
adversarial third party) calls for. Worth revisiting if `job_url` fetch
scope ever expands beyond "the user's own tracked applications."

HTML → text extraction uses `trafilatura` (boilerplate-stripping content
extraction — far more reliable here than a naive full-page text dump,
which would hand Gemini a page's nav/footer/ads instead of the posting
itself).

### `app/services/ai/` — Gemini client

Same "isolate the network client behind one module, lazy-init on first
use" shape as `r2.py`/`email.py`/`push.py` — importing `client.py` must
not crash startup just because `GEMINI_API_KEY` isn't set yet.
`call_structured()` is the one shared helper both `resume_parser.py` and
`ats_scorer.py` call: uses Gemini's structured-output mode
(`response_schema=<a Pydantic model>`), which guarantees a JSON response
matching the schema — far more reliable than asking for JSON in prose.

**Gemini gotcha worth knowing before touching `app/schemas/ai.py`**:
Gemini's API rejects a `response_schema` containing default values
outright (`"Default value is not supported in the response schema for
the Gemini API"` — confirmed against `googleapis/python-genai#699`).
Every field on `ParsedResume`/`AtsScoreResult`/`WorkExperienceItem`/
`EducationItem` is therefore `Field(...)` (required, no Python-side
default) even where the type itself is nullable (`str | None`) —
"optional" here means "the key must be present, value may be null,"
never "the key may be omitted." `test_ai_schemas.py`'s
`TestNoDefaultsOnGeminiSchemas` guards this directly, since a regression
here wouldn't fail loudly until an actual Gemini call at runtime.

**`google-genai` is pinned to `2.8.0`, not the latest release**
(`requirements.txt`): `google-genai>=2.9.0` requires `pydantic>=2.12.5`,
which would force bumping this app's core `pydantic==2.9.2` pin — every
schema in the entire API, not just this feature, and a meaningfully
riskier change than adding a new dependency. `2.8.0` is the newest
release still compatible with `pydantic>=2.9.0` (confirmed against
PyPI's published per-version dependency metadata). Revisit only
alongside a deliberate, separately-tested pydantic upgrade. Relatedly,
`httpx` was bumped from `0.27.2` to `0.28.1` (`google-genai` requires
`>=0.28.1`) — confirmed safe, since this codebase's `httpx` usage is
plain `httpx.post()`/`httpx.stream()` calls with no use of the arguments
that changed between those versions.

### Resume text extraction — PDF and DOCX only

`resume_parser.py::extract_text()` dispatches on file extension: `.pdf`
via `pypdf`, `.docx` via `python-docx`. Legacy binary `.doc` (still one
of `r2.py`'s `ALLOWED_CONTENT_TYPES`, since Word uploads in general are
accepted) is a **deliberate, documented gap** — `python-docx` only reads
the OOXML `.docx` format, and pulling in a heavier legacy-`.doc`
extraction dependency (`textract`/`antiword`/LibreOffice conversion) for
a shrinking share of uploads isn't worth it for this pass. Raises
`UnsupportedResumeFormatError`, which the task turns into
`status=failed` with a "please re-upload as PDF or DOCX" message.

### Type-checker gotchas hit while writing this (Pylance/Pyright)

Two worth knowing before touching `app/tasks/ai.py` or `app/api/v1/endpoints/ai.py`:

- **Celery ships no `py.typed` marker**, so without stubs Pyright infers
  a bare `FunctionType` for anything decorated with `@celery_app.task(...)`
  — every `.delay(...)` call site (both in `ai.py`'s endpoints) then
  reports `Cannot access attribute "delay" for class "FunctionType"`
  (`reportFunctionMemberAccess`). Fixed by adding the third-party
  `celery-types` PEP 561 stub package (installs as `celery-stubs`) to
  `requirements-dev.txt` — dev/type-checking only, not needed at
  runtime. Confirmed both directions: the error reproduces with
  `celery-types` uninstalled and disappears with it installed
  (`python -m pyright app/api/v1/endpoints/ai.py`).
- **`Session.get()` returns `Optional[T]`** — `db.get(Document, ...)` in
  `parse_resume_task` and `db.get(ResumeAnalysis, ...)` in
  `score_ats_task` are both guarded with an explicit `if ... is None:
  raise RuntimeError(...)` rather than assuming the row exists. This
  can't actually happen given the FK/`ondelete="CASCADE"` relationships
  (a deleted `Document`/`ResumeAnalysis` cascades to the row that
  references it), but the guard both satisfies the type checker
  correctly (not just silences it) and fails clearly, inside the same
  `except Exception` → `status=failed` handling every other failure
  already goes through, rather than crashing with a confusing
  `AttributeError` if that invariant is ever violated some other way.
- Similarly, `app/services/ai/client.py`'s `call_structured()` fallback
  path (`response.text` when `response.parsed` is unset) checks for
  `None` before calling `schema.model_validate_json(...)` — Gemini SDK's
  own stubs type `response.text` as `str | None`, and passing `None`
  through would have been a real (if rare) runtime `TypeError`, not just
  a type-checker complaint.

### Rate limiting — free tier only, shared budget

`POST /ai/resume-analyses` and `POST /ai/ats-scores` share one daily
budget per user (`AI_FREE_TIER_DAILY_LIMIT`, default 10), enforced by
`app/services/rate_limit.py` — the first direct `redis` client usage in
this codebase (Redis previously only served as Celery's broker/backend).
Free-tier-only for now: `User.role` has no premium concept yet (see
"Not part of this pass" below and the `ai-rate-limiting-tiered-by-premium`
memory note) — every user gets the same limit today.

- **Atomic fixed-window counter**: `INCR` a key
  (`ai_rate_limit:{user_id}:{YYYY-MM-DD}`, UTC date) and compare against
  the limit; `EXPIRE` it (~25h) the first time it's created so it
  self-cleans. `INCR` is a single atomic Redis command, so no race
  between concurrent requests. Accepted imperfection of a fixed window:
  a burst up to ~2x the limit is possible right at UTC midnight — fine
  for a cost-control guard, not a security-critical limiter.
- **One shared counter, not one per endpoint** — both routes call
  Gemini, so `ai_usage_key()` is keyed by user only, not user+endpoint.
- **The check runs before any row is created for the request**, in
  `_enforce_ai_rate_limit()` (`app/api/v1/endpoints/ai.py`) — called
  right after all the existing validation (ownership, `file_type`,
  resume-completed, job-description-source) and the resume-analyses
  dedup-reuse check, but *before* `db.add()`/`.delay()`. This means: a
  rejected request never leaves an orphaned `pending` row behind (it's
  rejected before one is ever created), a request that fails validation
  never consumes budget (never reaches the check), and the dedup-reuse
  path (an existing in-flight `ResumeAnalysis` for the same document)
  never consumes budget either (no new Gemini call is happening) — only
  a request that actually results in a fresh `.delay()` dispatch counts.
  This is a deliberate departure from the simpler "wrap `get_current_user`
  in one more `Depends()`" pattern `require_admin` uses
  (`app/api/deps.py`) — that pattern is easier to read but would charge
  quota for requests that error out before ever touching Gemini.
- **`429 Too Many Requests`** (new status code for this codebase — every
  other `ai.py` rejection is 503/404/422/409) with a `Retry-After`
  header set from the Redis key's remaining TTL.
- **Extension point for a future premium tier**: `check_and_increment()`
  takes a plain `limit: int` — it has no concept of "free" or "premium".
  The *only* place that resolves "what's this user's limit" is
  `_enforce_ai_rate_limit()`'s one call to
  `settings.AI_FREE_TIER_DAILY_LIMIT`; a premium tier would only need to
  change that one line to branch on `current_user.role` (or a future
  plan field), not the rate-limit service itself.
- **Testing**: uses the real Redis instance already running in
  `docker-compose.yml` (`tests/test_rate_limit.py`,
  `TestAiRateLimiting` in `test_ai_endpoints.py`), not a mocking library
  like `fakeredis` — same "use the real dependency you already
  provision" philosophy as this suite's real-Postgres DB tests. Test
  isolation falls out of `make_user()`'s fresh random UUID per test
  (keys are namespaced by `user_id`), not an explicit rollback the way
  Postgres SAVEPOINTs give the DB tests — Redis test keys genuinely
  persist until their TTL expires, which is harmless at this volume.

### Testing: a new pattern for testing a per-request Celery task

`test_ai_tasks.py` calls `parse_resume_task`/`score_ats_task` directly as
plain functions (Celery tasks are callable without a broker) — the same
"no existing precedent" gap `send_due_reminders` still has (see Testing
in TODO.md), solved here for the first time. The hard part: `SessionLocal()`
normally opens a brand-new connection to `settings.DATABASE_URL`, which
would miss whatever the test's `db_session` fixture already inserted
(different connection, different transaction) and wouldn't roll back at
teardown. Fixed by monkeypatching `app.tasks.ai.SessionLocal` to a
`sessionmaker` bound to the *same* connection `db_session` uses, with
SQLAlchemy 2.0's `join_transaction_mode="create_savepoint"` — so the
task's own `db.commit()` calls become SAVEPOINT release/restart rather
than committing (or breaking) `db_session`'s outer transaction. Same end
result `conftest.py`'s `after_transaction_end` listener achieves for
`db_session` itself, just via SQLAlchemy's built-in mechanism for a
second, independent `Session` on the same connection. Worth reusing this
exact pattern (`patch_ai_tasks_session` fixture) for any future
per-request-dispatched task, including eventually testing
`send_due_reminders`.

### Not part of this pass

- **Tiered (free/premium) rate limiting** — the flat free-tier limit
  described above is implemented; a premium tier with a higher limit is
  a deliberately deferred product decision, not yet scoped as
  implementation work, since it needs a premium role and a payment/
  upgrade flow that don't exist yet. See TODO.md's "AI Features" section
  and the `ai-rate-limiting-tiered-by-premium` memory note.
- Job Match, Cover Letter Generator, Interview Coach — the other three
  TODO.md "AI Features" items, all deferred until this pass's pattern
  (parse once, reuse everywhere) is proven.
- Web/mobile UI for either feature — `docs/AI_FEATURES.md` and
  `MOBILE_SUMMARY.md`'s "Navigation shell" section both already flagged
  an AI-tools UI as designed-later; this pass is that design, at the API
  level only.

## Background job execution: BackgroundTasks/cron path added alongside Celery

Deployment-driven follow-up to both sections above. Render (the chosen
backend host) has no free tier for an always-on background worker, so
production no longer runs Celery worker/beat by default:

- `app/tasks/ai.py` and `app/tasks/reminders.py` were renamed to
  `ai_celery.py` / `reminders_celery.py` (and their tests likewise) -
  unchanged otherwise, still fully wired through `docker-compose.yml`'s
  `celery-worker`/`celery-beat` services for local dev, and kept as a
  reference/upgrade path rather than deleted.
- Two new modules, `app/tasks/ai_inline.py` and
  `app/tasks/reminders_inline.py`, duplicate that same logic as plain
  functions with no Celery decorator - deliberately duplicated rather
  than factored into a shared helper, so the Celery versions stay
  self-contained and untouched.
- `app/api/v1/endpoints/ai.py`'s two POST routes now dispatch via
  FastAPI's `BackgroundTasks.add_task(...)` against the `_inline`
  functions instead of `.delay()`.
- `send_due_reminders` (the `_inline` version) has no scheduler of its
  own anymore; a new endpoint, `app/api/v1/endpoints/internal.py`'s
  `POST /internal/reminders/run`, calls it on demand instead. Auth is a
  shared secret (`INTERNAL_CRON_SECRET`, compared with
  `secrets.compare_digest` the same way `verify_csrf` does) via an
  `X-Internal-Cron-Secret` header, not `get_current_user` - the caller
  is a scheduler, not a logged-in user.
- **Scheduler: cron-job.org, not GitHub Actions** - the original plan
  was `.github/workflows/reminders-cron.yml`, a GitHub Actions cron
  workflow hitting that endpoint every 10 minutes. In production,
  GitHub's scheduled-workflow triggers turned out to be unreliable well
  beyond the documented "best-effort, can run a few minutes late" -
  real run history showed multi-hour gaps with the trigger not firing
  at all, not just landing late. Replaced with cron-job.org (a
  purpose-built free scheduler) hitting the same endpoint, which is
  meaningfully more punctual in practice. The GitHub Actions workflow
  is kept in the repo, disabled (Actions tab toggle, not removed) as a
  free zero-cost fallback that can be re-enabled if cron-job.org itself
  ever needs a backup; `workflow_dispatch` still works for manual
  testing regardless of the schedule trigger's on/off state.

Trade-offs accepted for the $0-extra-infra path: no retry if the
in-process background task crashes mid-run (a Render redeploy mid-task
leaves a row on `PROCESSING` forever, same exposure Celery has for an
outright process kill, just a more routine trigger here), no separate
worker concurrency (a burst of AI requests queues up behind
Starlette's shared threadpool rather than scaling via Celery worker
concurrency), and GitHub's scheduled workflows are best-effort (can run
several minutes late, auto-disable after 60 days of repo inactivity) -
acceptable because `InterviewReminder.sent_at IS NULL` idempotency
makes a late or skipped tick harmless, just delayed.

Upgrade path back to Celery, if background work ever needs real worker
concurrency or crash-safe retry: redeploy `celery-worker`/`celery-beat`
as paid Render Background Workers (docker-compose.yml's services show
the exact commands) and point the two call sites above back at
`app.tasks.ai_celery` / re-add the beat schedule instead.

### Scaling / load balancing — not configured, not needed yet

Came up when picking Render/Vercel/Supabase as the deployment
platforms. Recorded here rather than only in a deployment doc since
it's about this app's own statelessness, not just infra choices:

- **Vercel and Cloudflare R2** load-balance themselves via their own
  global CDN/edge networks - nothing this codebase needs to do.
- **Render** runs the API as one instance. Its own router/proxy always
  fronts that instance (never raw-exposed to the internet), but there's
  no horizontal scaling (multiple instances splitting traffic) turned
  on - that's a Render dashboard toggle on paid plans, not a code
  change, precisely because nothing added so far breaks under multiple
  instances: `get_current_user`'s JWT auth carries no server-side
  session state, `app/services/rate_limit.py`'s AI rate limiter already
  lives in Redis rather than in-process memory, and the
  `BackgroundTasks` jobs added just above write straight to Postgres
  rather than holding anything in shared memory between requests. Flip
  that toggle whenever real traffic justifies it - no rework needed
  first.
- **Supabase** is a single primary Postgres instance - read replicas or
  other DB-level load balancing would be premature at this project's
  traffic level. The Supavisor connection pooler `DATABASE_URL` points
  at (its session-mode pooler, chosen since Supabase defaults new
  projects to IPv6-only direct connections that Render can't reach) is
  connection pooling, a different concern from horizontal DB scaling.

## Email backend: Gmail API added alongside SMTP/Resend

Deployment-driven, same family of change as "Background job execution"
above - discovered once reminder emails were actually tried against a
live Render deployment:

- Render blocks outbound traffic to SMTP ports (25/465/587) entirely on
  free web services (a policy change effective September 2025) - the
  existing `app/services/email.py` SMTP backend can't even open a
  connection there (`OSError: [Errno 101] Network is unreachable`).
  Upgrading to a paid Render instance would unblock the ports, but this
  project also has no domain to authenticate a provider like
  Resend/SendGrid with, and since Feb 2024 (Gmail/Yahoo) / May 2025
  (Microsoft) the major inbox providers require proper domain
  authentication for reliable delivery anyway - a workaround using some
  other provider's "single sender, no domain" mode would likely land in
  spam regardless.
- Fix: `app/services/email.py` renamed to `email_smtp.py` (unchanged
  otherwise, kept as the local-dev/MailHog and Celery-reference-path
  backend - same "rename, don't delete" precedent as the Celery task
  modules). New `app/services/email_gmail_api.py` sends through the
  Gmail API over HTTPS instead - not subject to Render's SMTP-port
  block, and still carries Google's own SPF/DKIM/DMARC authentication
  automatically since it's genuinely sent through Google's servers, not
  a workaround with weaker deliverability. `app/tasks/reminders_inline.py`
  (the production reminders pipeline) imports `send_email` from the new
  module; `app/tasks/reminders_celery.py` is untouched and still uses
  `email_smtp.py` against MailHog.
- Auth: OAuth 2.0, a single long-lived refresh token for one specific
  Gmail account (`GMAIL_API_SENDER_EMAIL`), minted once locally via
  `scripts/gmail_oauth_setup.py` (opens a browser for the one-time
  consent flow) rather than anything interactive happening at runtime -
  `google-auth`'s `Credentials` turns the stored refresh token into
  short-lived access tokens automatically on every send. Scope is
  send-only (`gmail.send`), not full mailbox access.

## Auth cookie fixes found during the same deployment pass

Two bugs that only reproduced against a real cross-origin (Vercel +
Render) production deployment, not local dev - both fixed on `master`
directly rather than a feature branch, since they're corrections to
existing behavior rather than new work:

- **CSRF double-submit was completely broken in production** - the
  `csrf_token` cookie was `httponly=False` specifically so frontend JS
  could read it via `document.cookie` and echo it back as
  `X-CSRF-Token`, which only works when frontend and backend share an
  origin. Deployed separately, a different-origin frontend's own JS can
  never read a cookie belonging to a different origin, so every
  `/auth/refresh` and `/auth/logout` call 403'd. Fixed by returning
  `csrf_token` in the `/login`/`/refresh` JSON response body instead
  (`TokenResponse.csrf_token`) - something CORS already permits the
  frontend to read regardless of origin - and dropping the CSRF check
  from `/auth/refresh` entirely, since that endpoint has to work with
  zero prior in-memory state (a fresh page load) and can't ever satisfy
  a "you already have a token from an earlier response" requirement;
  see that endpoint's own docstring for why dropping it there is safe.
  `/auth/logout` keeps the check, now satisfiable. Also hardened
  `csrf_token` to `httponly=True`, since nothing reads it via JS anymore.
- **Logout didn't actually clear the session cookie in production** -
  `clear_auth_cookies()` called Starlette's `Response.delete_cookie()`
  without passing `secure`/`samesite`, which default to `False`/`"lax"`
  - silently different from what `set_auth_cookies()` actually set
  (`secure=settings.COOKIE_SECURE`, `samesite=settings.COOKIE_SAMESITE`,
  `Secure; SameSite=None` in production). A deletion Set-Cookie with
  mismatched attributes from the cookie it's trying to overwrite is a
  known source of "logout doesn't really log out" bugs. Local dev never
  caught this because `.env.local`'s `COOKIE_SECURE=False`/
  `COOKIE_SAMESITE=lax` happen to match `delete_cookie()`'s defaults -
  only production's different settings exposed the mismatch. Symptom:
  click logout, land on `/login`, refresh immediately after, and get
  logged right back in. Fixed by passing the same settings explicitly;
  regression test in `tests/test_auth_endpoints.py` reproduces it
  against production-shaped cookie settings via an `https://testserver`
  `TestClient` (a `Secure` cookie won't even get stored by a plain
  `http://` test client, which is correct browser behavior, but means
  the bug needs an https base URL to reproduce at all).

Also fixed in the same pass: `alembic/env.py` didn't escape `%` before
handing `DATABASE_URL` to `config.set_main_option()`, which stores it
through Python's `configparser` - `configparser` treats `%` as its own
interpolation character (unrelated to URL percent-encoding), so a
percent-encoded special character in the DB password (e.g. `%21` for
`!`, exactly what Supabase's own docs recommend) tripped it with
`invalid interpolation syntax` before any migration could run. Fixed by
doubling `%` before the `set_main_option()` call; only affects the
`alembic` CLI; `app/db/session.py`'s own `create_engine()` call never
goes through `configparser`, so a running deployment was never affected
by this one. `webapp/vercel.json` also had to be added - Vue Router's
history-mode client-side routes 404'd on Vercel on a hard refresh with
no SPA rewrite rule configured.

## Not yet implemented (next up per TODO.md)

- Analytics reporting endpoints (CSV/PDF export) — the dashboard-metrics
  endpoints themselves are done (see above); exporting them isn't
- Presigned direct-to-R2 uploads (current uploads are server-proxied —
  fine for resume-sized files, revisit if upload volume/size grows)
- RBAC beyond a `role` column (no admin endpoints protected yet)
- Password-reset support in the mobile client (backend endpoints already
  exist and are unaffected by the mobile-client changes above; no mobile
  UI calls them yet — see MOBILE_SUMMARY.md)
- Password-reset-by-email UI (web or mobile) — a separate, still-open
  gap from the account-settings/notifications web UI, which has since
  shipped (see WEBAPP_SUMMARY.md's "Account settings & notifications").
- Multi-lead-time reminders (more than one reminder per interview, e.g.
  24h *and* 1h before) — still deferred per TODO.md's original plan; a
  single lead time is now per-user-configurable (`UserSettings.reminder_lead_hours`),
  just not yet per-interview-multiple.
- Celery-beat-on-multiple-nodes duplicate-send protection — not needed
  at current scale (single beat instance); would need a single
  scheduler or a Redis lock if ever run horizontally scaled

## Development workflow

CI runs automatically on push/PR to `main` (see `.github/workflows/backend-ci.yml`):
lint (`ruff check`), format check (`ruff format --check`), and tests
with coverage — the `test` job runs both a `postgres:16-alpine` and a
`redis:7-alpine` service container, since `pytest` includes real-Postgres
integration tests (starting with `GET /contacts`) and, as of the AI
rate-limiting work, real-Redis tests too (`test_rate_limit.py`,
`TestAiRateLimiting` in `test_ai_endpoints.py` — see "Rate limiting"
above for why those use real Redis instead of a mock). `REDIS_URL` is
set explicitly in the job's `env:` to match, alongside
`TEST_DATABASE_URL`, even though it happens to equal the config
default — same explicit-in-CI convention as the Postgres var.

To catch the same issues locally _before_ pushing:

```bash
pip install pre-commit
pre-commit install        # one-time, from the repo root
```

From then on, `ruff check --fix` and `ruff format` run automatically on
every `git commit` touching `backend/`. To run everything manually without
committing, you'll first need a throwaway test database (once, not per
run) — point `TEST_DATABASE_URL` at it via `.env.local` if you're not
using the default `lwkapply_test` name:

```bash
docker compose exec <db-service> psql -U postgres -c "CREATE DATABASE lwkapply_test;"
```

```bash
cd backend
ruff check .
ruff format .
pytest --cov=app --cov-report=term-missing
```

## Local development

### Option A — Docker Compose (recommended)

```bash
cp backend/.env.example backend/.env
docker compose up --build
```

API will be live at http://localhost:8000, interactive docs at
http://localhost:8000/docs.

Then, in another terminal, run migrations:

```bash
docker compose exec api alembic upgrade head
```

### Option B — Local Python env

```bash
cd backend
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # then edit DATABASE_URL to point at your local Postgres
alembic upgrade head
uvicorn app.main:app --reload
```

## Regenerating migrations

Models are the source of truth. After changing any model, regenerate rather
than hand-writing:

```bash
alembic revision --autogenerate -m "describe the change"
alembic upgrade head
```

Always eyeball the generated file before running it — particularly enum
type changes, which Alembic sometimes needs a nudge on.

## Project structure

```
backend/
  app/
    api/
      deps.py                     # auth/DB dependency injection
      v1/
        router.py                 # registers all endpoint routers
        endpoints/
          auth.py
          applications.py
          interviews.py            # nested under /applications/{id}/interviews;
                                    # also GET /interviews (directory_router),
                                    # registered separately at the top level
          documents.py             # top-level /documents - upload, list/
                                    # search/filter, get, patch, delete,
                                    # download (no application_id anywhere)
          application_documents.py # /applications/{application_id}/documents -
                                    # attach/list/detach an existing document
                                    # against one application (many-to-many)
          contacts.py              # top-level /contacts - create, list/
                                    # search, get, patch, delete
                                    # (no application_id anywhere)
          application_contacts.py  # /applications/{application_id}/contacts -
                                    # attach/list/detach an existing contact
                                    # against one application (many-to-many)
          analytics.py              # GET /analytics/summary, /funnel,
                                    # /activity, /interviews - real-time,
                                    # no precomputation/cache
          users.py                 # /users/me; also /users/me/device-tokens
                                    # (POST register/upsert, DELETE deregister)
          ai.py                    # POST/GET /ai/resume-analyses,
                                    # POST/GET /ai/ats-scores - both async
                                    # (202 + BackgroundTasks dispatch,
                                    # poll GET .../{id})
          internal.py              # POST /internal/reminders/run - shared-
                                    # secret-authenticated, triggers
                                    # send_due_reminders on demand (the
                                    # cron replacement, see below)
    core/                          # config, security (JWT, password hashing)
      celery_app.py                # Celery app instance + beat schedule
                                    # (send_due_reminders, every 10 min) +
                                    # include=[..., "app.tasks.ai_celery"] -
                                    # still fully functional for local dev/
                                    # study (docker-compose.yml), just not
                                    # what production dispatches through
                                    # (see "Background job execution" above)
    db/                            # engine/session, declarative base
    models/                        # SQLAlchemy ORM models
                                    # (InterviewReminder, DeviceToken - reminders;
                                    # ApplicationStatusHistory - audit log,
                                    # not yet read by analytics;
                                    # ApplicationDocument/ApplicationContact -
                                    # many-to-many joins between Application
                                    # and Document/Contact;
                                    # ResumeAnalysis, AtsScore, and now also
                                    # Document/Contact - top-level/direct-
                                    # user_id ownership, unlike Interview)
    schemas/                       # Pydantic request/response models
                                    # (ai.py also doubles as Gemini's
                                    # response_schema source - see AI
                                    # features section above)
    services/
      r2.py                        # Cloudflare R2 upload/download/delete for
                                    # documents (download_document() added
                                    # for Resume Parser's server-side read)
      email_smtp.py                # Resend / SMTP+MailHog - used by the Celery
                                    # reference pipeline (reminders_celery.py)
                                    # and local dev; Render blocks the SMTP
                                    # ports this needs, so production doesn't
                                    # use it - see email_gmail_api.py
      email_gmail_api.py           # Gmail API over HTTPS - what
                                    # reminders_inline.py (production) actually
                                    # sends reminder emails through
      push.py                      # Firebase Admin SDK (FCM) - reminders, Phase B
      reminders.py                 # sync_interview_reminders() - interview CRUD
                                    # keeps interview_reminders rows in sync
      application_history.py       # record_status_change() - Application CRUD
                                    # keeps application_status_history rows in sync
      ai/
        client.py                  # Gemini client - lazy-init, call_structured()
        resume_parser.py           # extract_text() (PDF/DOCX only), parse_resume()
        ats_scorer.py               # score_resume_against_job()
        job_description_fetcher.py  # fetch_job_description() - SSRF-guarded
                                     # job_url fetch + trafilatura extraction
    tasks/
      reminders_celery.py          # Celery task: send_due_reminders
      ai_celery.py                 # Celery tasks: parse_resume_task,
                                    # score_ats_task - first per-request-
                                    # dispatched tasks in this codebase
      reminders_inline.py          # same send_due_reminders logic as a
                                    # plain function, called by internal.py
                                    # instead of a beat schedule
      ai_inline.py                 # same parse/score logic as plain
                                    # functions, dispatched via
                                    # BackgroundTasks instead of .delay()
    utils/
      timezone.py                  # shared IANA tz-name validation
    main.py                        # FastAPI app + router registration
  alembic/
    versions/
      0001_initial_schema.py       # autogenerated from models
      ..._interview_reminders_and_user_timezone.py
      ..._device_tokens.py
      ..._resume_analyses_and_ats_scores.py  # ai_job_status enum,
                                              # hand-fixed create_type=False
                                              # on the second table's column
      ..._documents_add_user_id.py           # decoupling Document from
      ..._application_documents_table.py     # Application - six small,
      ..._documents_drop_application_id.py   # single-purpose, chained
      ..._resume_analyses_add_completed_at.py # migrations rather than
      ..._ats_scores_add_job_url.py          # one big one - see "A note
      ..._ats_scores_drop_application_id.py  # on Document / ApplicationDocument"
      ..._applications_add_application_name.py # optional label field,
                                                 # see the Applications bullet above
  requirements.txt
  Dockerfile
```

## Security notes for reviewers

- Passwords hashed with bcrypt directly, never stored/logged in plaintext.
- JWTs are typed (`access` / `refresh` / `password_reset`) so a stolen
  refresh token can't be replayed as an access token, etc.
- `password-reset/request` always returns the same response regardless of
  whether the email exists, to prevent user enumeration.
- All application and interview queries filter by the authenticated user
  (via a join to `applications.user_id` where the resource isn't owned
  directly) at the DB layer, not just hidden in the response, to prevent
  IDOR. Document and Contact both filter directly on their own `user_id`
  (like `ResumeAnalysis`/`AtsScore`); the `ApplicationDocument`/
  `ApplicationContact` attach/detach links check ownership on both sides.
- Document uploads are validated by `Content-Type` (PDF/Word only) and
  streamed in chunks against `MAX_UPLOAD_SIZE_MB`, rather than trusting a
  client-supplied `Content-Length` header.
- Document downloads are always short-lived presigned R2 URLs (5 min
  expiry) — the API never returns a permanent/public file URL.
- `SECRET_KEY`, DB credentials, and Cloudflare R2 credentials are read
  from environment variables only — never commit a real `.env` file
  (it's git-ignored).
