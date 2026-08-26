# Changelog

## v0.19.0 (in progress)

### Changed

- **Reminder emails switched to the Gmail API** — deployment-driven:
  Render blocks outbound traffic to SMTP ports (25/465/587) on free web
  services, so the existing SMTP backend couldn't connect at all
  (`OSError: [Errno 101] Network is unreachable`), and a paid domain-
  authenticated provider like Resend/SendGrid wasn't an option either —
  this project has no domain, and Gmail/Yahoo (Feb 2024) / Microsoft
  (May 2025) now require domain authentication for reliable delivery
  regardless. Full detail in `backend/BACKEND_SUMMARY.md`'s "Email
  backend: Gmail API added alongside SMTP/Resend" section; summary
  here:
  - `app/services/email.py` renamed to `email_smtp.py`, unchanged
    otherwise — kept as the local-dev (MailHog) / Celery-reference-path
    backend, same "rename, don't delete" precedent as the Celery task
    modules.
  - New `app/services/email_gmail_api.py` sends over HTTPS via the
    Gmail API instead of raw SMTP, so Render's port block doesn't
    apply — and still carries Google's own SPF/DKIM/DMARC
    authentication automatically, since it's genuinely sent through
    Google's servers. `app/tasks/reminders_inline.py` (the production
    pipeline) uses it; `app/tasks/reminders_celery.py` is untouched.
  - Auth is OAuth 2.0 with one long-lived, send-only-scoped
    (`gmail.send`) refresh token for a single Gmail account, minted
    once locally via the new `scripts/gmail_oauth_setup.py` rather
    than anything interactive at runtime.
  - `Reply-To`/`List-Unsubscribe` headers added after a real send
    landed in spam — legitimate, standard signals, though the real
    fix for inbox placement is sender/recipient reputation building up
    over real sends and the recipient marking a message "Not spam",
    not something headers alone solve.

### Fixed

- **CSRF double-submit was completely broken in production.** The
  `csrf_token` cookie required frontend JS to read it via
  `document.cookie` and echo it back as `X-CSRF-Token`, which only
  works when frontend and backend share an origin — deployed
  separately (Vercel, Render), a different-origin frontend can never
  read a cookie belonging to a different origin, so every
  `/auth/refresh` and `/auth/logout` call 403'd. Fixed by returning
  `csrf_token` in the `/login`/`/refresh` response body instead
  (something CORS already permits reading regardless of origin), and
  dropping the CSRF check from `/auth/refresh` entirely — that
  endpoint has to work on a fresh page load with zero prior state, so
  it can never satisfy a "you already have a token from an earlier
  response" requirement; see that endpoint's docstring for why
  dropping it there is safe. `/auth/logout` keeps the check.
- **Logout didn't actually clear the session cookie in production** —
  `clear_auth_cookies()` called `Response.delete_cookie()` without
  passing `secure`/`samesite`, which silently default to `False`/
  `"lax"`, different from what the cookie was actually set with
  (`Secure; SameSite=None` in production). Symptom: click logout, land
  on `/login`, refresh immediately after, get logged right back in.
  Local dev never caught this because `.env.local`'s cookie settings
  happen to match `delete_cookie()`'s defaults.
- **`alembic upgrade head` failed against a percent-encoded DB
  password** (e.g. Supabase's own recommended encoding for special
  characters) with `invalid interpolation syntax` — `alembic/env.py`
  wasn't escaping `%` before handing `DATABASE_URL` to
  `config.set_main_option()`, which stores it through Python's
  `configparser`, and `configparser` treats `%` as its own
  interpolation character. Only affected the `alembic` CLI, never a
  running deployment.
- **Refreshing a client-side route 404'd on Vercel** — no
  `webapp/vercel.json` SPA rewrite existed, so a hard reload on any
  non-root Vue Router path hit Vercel's static host directly instead
  of `index.html`.
- `tests/test_auth_endpoints.py` itself was flaky across environments
  — most of it silently depended on `.env.local`'s local-only cookie
  settings to work at all via a plain `http://testserver` test client,
  which is absent (and therefore behaves differently) in CI. Fixed
  with an explicit, production-shaped `https_client` fixture used
  throughout the file.

## v0.18.0

### Changed

- **Background job execution: BackgroundTasks/cron path added alongside
  Celery** — deployment-driven: Render (the chosen backend host) has no
  free tier for an always-on background worker, so production no
  longer depends on Celery running. Full detail in
  `backend/BACKEND_SUMMARY.md`'s "Background job execution" section;
  summary here:
  - `app/tasks/ai.py`/`app/tasks/reminders.py` renamed to
    `ai_celery.py`/`reminders_celery.py` (and their tests) — unchanged
    otherwise, kept as a reference/upgrade path and still fully wired
    through `docker-compose.yml`'s `celery-worker`/`celery-beat`
    services for local dev.
  - Two new modules, `app/tasks/ai_inline.py` and
    `app/tasks/reminders_inline.py`, duplicate that same pipeline logic
    as plain functions with no Celery decorator — deliberately
    duplicated rather than factored into a shared helper, so the Celery
    versions stay self-contained and untouched.
  - `app/api/v1/endpoints/ai.py`'s two POST routes now dispatch via
    FastAPI's `BackgroundTasks.add_task(...)` against the `_inline`
    functions instead of `.delay()`.
  - New `POST /internal/reminders/run` (`app/api/v1/endpoints/internal.py`),
    authenticated by a shared secret (`INTERNAL_CRON_SECRET`, checked
    with `secrets.compare_digest` the same way `verify_csrf` does) via
    an `X-Internal-Cron-Secret` header rather than `get_current_user`,
    replaces celery-beat's own schedule. `.github/workflows/reminders-cron.yml`
    is the default scheduler — a GitHub Actions cron workflow hitting
    that endpoint every 10 minutes, matching celery-beat's original
    cadence exactly.
  - Trade-offs accepted for the $0-extra-infra path, and the upgrade
    path back to Celery if background work ever needs real worker
    concurrency or crash-safe retry, are both spelled out in
    `BACKEND_SUMMARY.md`.

## v0.17.0

### Changed

- **Contacts decoupled from a single Application** — the same rework
  Documents got in v0.11.0/v0.12.0, applied to `Contact` this time, and
  shipped across backend/web/mobile together in one pass rather than
  staggered. Full detail in `backend/BACKEND_SUMMARY.md`'s "A note on
  Contact / ApplicationContact", `webapp/WEBAPP_SUMMARY.md`'s "Contacts"
  section, and `mobile/MOBILE_SUMMARY.md`'s "Contacts, Interviews, and
  Documents"/"Cross-application directory screens" sections; summary
  here:
  - **The trigger was product, not a data-integrity gap** (unlike
    Document's `AtsScore` trigger): deleting an application used to
    cascade-delete every contact attached to it, with no way to keep a
    recruiter or hiring manager around after the application was
    deleted, or reuse the same contact across a second application.
  - **`Contact` became a top-level, user-owned resource** (`user_id`
    direct FK, like `Document`), reachable at `/contacts` — no longer
    nested under `/applications/{id}/contacts`, no longer owned by
    exactly one application. Reusable across zero, one, or several
    applications via a new many-to-many join, `ApplicationContact`
    (`POST`/`GET`/`DELETE /applications/{application_id}/contacts`
    attaches/lists/detaches). Deleting an application no longer deletes
    its contacts — only the join rows; deleting a contact still
    cascades its `ApplicationContact` links. Migration split into three
    small, chained files, same backfill-then-drop sequencing Document's
    used
  - **Web**: `stores/contacts.ts` became the top-level contact
    directory store (list/search/create/update/delete); a new
    `stores/applicationContacts.ts` handles one application's
    attached-contacts list/attach/detach. `stores/contactDirectory.ts`
    retired. `ContactFormDialog.vue` is reused for both create and edit,
    no longer application-scoped; new `ContactAttachDialog.vue` mirrors
    `DocumentAttachDialog.vue`. `ContactDirectoryView.vue` is no longer
    read-only — it's now the primary place to add/edit/delete contacts
  - **Mobile**: same split — `ContactDirectoryApi` gained full
    `/contacts` CRUD, new `ApplicationContactsApi` handles
    `list`/`attach`/`detach` against `/applications/{id}/contacts`.
    `contacts_panel.dart` reworked from create/delete to **attach/detach**
    ("Attach existing" via new `contact_attach_sheet.dart`, "Add new" via
    create-then-attach), and its nested list moved from a plain local
    `State` to a new paginated `contacts_list_controller.dart`, since the
    backend now paginates this endpoint too. `contact_directory_screen.dart`
    (the bottom-nav Contacts tab) is no longer read-only — it's now the
    primary place to manage the whole directory. The old
    `contacts_api.dart`/`contact_with_application.dart` were deleted

### Fixed

- Deleting a document's confirm dialog only warned that it would be
  removed from every application it's attached to — it also permanently
  cascades-deletes any `ResumeAnalysis`/`AtsScore` rows scored against
  it (`resume_analyses.document_id`/`ats_scores.resume_analysis_id` are
  both `ondelete="CASCADE"`), which the copy didn't mention. Fixed on
  both web and mobile.

## v0.16.0

### Added

- **Account settings, mobile** — mobile counterpart to v0.14.0/
  v0.15.0's web `AccountSettingsView.vue`, and the first pass to touch
  `Settings` beyond its original logout-only scope. `ProfileScreen` —
  avatar upload/remove (`file_picker`), first/last name, and an
  explicit "Auto-detect timezone" toggle + searchable
  `TimezonePickerSheet` (every IANA zone labeled with its live UTC
  offset, via `package:timezone` — already a transitive dependency
  through `flutter_local_notifications`, promoted to direct here).
  `ChangePasswordScreen`, `NotificationPreferencesScreen` (master +
  per-channel toggles, custom reminder lead time), and a
  password-reconfirmed `DeleteAccountDialog` round out the screen.
  Profile/avatar changes route through new `AuthController` methods
  (`updateProfile`/`uploadAvatar`/`removeAvatar`/`deleteAccount`) so
  `currentUserProvider` updates in place, mirroring
  `webapp/src/stores/auth.ts`. `User` gains `timezone`/
  `timezoneIsManual` (mirrors `UserRead`, previously fetched but never
  exposed on the mobile client). Full detail in
  `mobile/MOBILE_SUMMARY.md`'s "Settings screen".
- **In-app notification feed, mobile** — new ground on mobile (only
  push notifications existed before): `NotificationBellButton` (unread
  badge in `AppBar.actions`, same placement convention as
  `SettingsIconButton`) and `NotificationsScreen` (a full pushed
  screen, not a popover — full-width Unread/Read `SegmentedButton` +
  infinite scroll). `NotificationsController` polls
  `GET /notifications/unread-count` every 30s — deliberately not
  `.autoDispose`, started/stopped from `AuthController` on the same
  login/restore/logout lifecycle `PushService`'s device-token
  registration already follows, so the badge keeps polling on every
  authenticated screen rather than only while the feed is open. Full
  detail in `mobile/MOBILE_SUMMARY.md`'s "Notifications feed".

## v0.15.0

### Added

- **Notification bell: Unread/Read tabs + infinite scroll** — the web
  bell popover (v0.14.0) only ever showed a flat "most recent" list;
  this pass adds real paging behind two tabs. `stores/notifications.ts`
  now tracks a single active status tab with its own page/total,
  scrolling near the bottom of the popover's list appends the next page.
  Needed a backend change: `GET /notifications` only had
  `unread_only: bool`, with no way to ask for read-only — replaced with
  `status: Literal["all", "unread", "read"] = "all"` (additive query
  shape; nothing else called this endpoint yet, mobile hasn't
  implemented notifications).
- **Timezone control in Account Settings** — `UserRead` now returns
  `timezone`/`timezone_is_manual` (both existed on `User` already, just
  never returned to a client). Web's Profile section gets a searchable,
  clearable timezone `Select`; clearing it sends an explicit
  `timezone: null`, matching `PATCH /users/me`'s existing "go back to
  auto-detect" semantics. Only sent when actually changed from the saved
  value — resending the initial value on every name-only save would
  otherwise silently re-lock an auto-detected timezone as manual.

## v0.14.0

### Added

- **Account settings + notifications, web UI** — v0.13.0 shipped every
  backend endpoint this needed but no web UI; this pass builds it. Full
  detail in WEBAPP_SUMMARY.md's "Account settings & notifications"
  section; summary here:
  - **`/settings` route** (`AccountSettingsView.vue`), split into
    independent section components — `ProfileSettingsCard.vue` (avatar
    upload/remove, first/last name; email read-only), `PasswordSettingsCard.vue`
    (current/new/confirm, a `zod` `.refine()` cross-field
    match check), `NotificationSettingsCard.vue` (master + per-channel
    email/push toggles, a custom reminder-lead-time control that falls
    back to the server default when unset), and `DeleteAccountDialog.vue`
    (danger zone, re-confirms the password before the irreversible
    `DELETE /users/me` — matches the backend's own re-auth requirement)
  - **Header notification bell** (`NotificationBell.vue`) — unread-count
    badge, a popover listing the most recent notifications, mark-one-read
    and mark-all-read. `stores/notifications.ts` polls
    `GET /notifications/unread-count` every 30s (delivery is polling, not
    real-time push, per the backend's own design) — started/stopped from
    `AppLayout.vue`'s mount/unmount so one poll loop covers every
    authenticated page
- **Sidebar nav overhaul** (`AppLayout.vue`) — sticky while page content
  scrolls; a new account menu at the bottom (avatar, name, "· Free" —
  hardcoded, no plan/tier field on `User` yet) opening a popup with
  "Account settings" and a red "Log out". Replaces the old standalone
  header "Log out" button, the "Welcome back" greeting, and the
  sidebar's own "Settings" link — each action now has exactly one place
  to find it.

### Fixed

- **Avatar photo never actually rendered, anywhere it was used** —
  PrimeVue's `Avatar` renders `label > icon > image`, in that priority
  order; both usages (`ProfileSettingsCard.vue`, `AppLayout.vue`'s
  account menu) hardcoded `icon="pi pi-user"` unconditionally, so the
  icon branch always won and the `image` branch (a real `avatar_url`)
  never rendered regardless. `icon` is now only bound when there's
  neither an image nor initials to fall back on.

## v0.13.0

### Added

- **Account settings + notification preferences backend, web UI deferred
  to a later pass** — this pass builds every endpoint a future settings
  page and bell-icon UI will need, but ships no web UI itself (see
  TODO.md's new Frontend "Account Settings" section). Full detail in
  BACKEND_SUMMARY.md's "Account settings & notification preferences" and
  "In-app notification feed"; summary here:
  - **Profile/account** (`app/api/v1/endpoints/users.py`): `PATCH /users/me`
    (name, timezone — gains a new `timezone_is_manual` flag so an
    explicit choice here stops being silently overwritten by the
    existing login/refresh auto-detect), `POST /users/me/password`
    (requires the current password even though the request is already
    bearer-authenticated), `POST`/`DELETE /users/me/avatar` (new fixed
    per-user R2 object key, `users/{user_id}/avatar` — a re-upload just
    overwrites it, no separate cleanup step; presigned for 1 hour, not
    documents' 5 minutes, since this backs a persistent `<img>` tag),
    `DELETE /users/me` (password-confirmed; cleans up every owned
    document's + the avatar's R2 objects before the row itself is
    deleted — the DB cascade only handles Postgres rows).
  - **`UserSettings`, a new dedicated per-user preferences table**
    (`app/models/user_settings.py`) — deliberately not columns bolted
    onto `users`, which is read on every authenticated request; a
    migration-per-setting cost accepted in exchange for keeping
    identity/auth and preferences as separate concerns, matching this
    codebase's existing `Document`/`ApplicationDocument` split.
    `reminder_lead_hours` (nullable, falls back to the existing global
    `settings.REMINDER_LEAD_HOURS`), `notifications_enabled` (master
    switch), `email_notifications_enabled`, `push_notifications_enabled`.
    Every user always has exactly one row (created at registration,
    backfilled for existing accounts). `GET`/`PATCH /users/me/settings`.
  - **In-app notification feed** ("the bell icon" backend) — new
    `Notification` model/table and `/notifications` endpoints (list with
    `unread_only`, a dedicated `unread-count`, mark-one-read,
    mark-all-read), fed by a new third `IN_APP` value on the existing
    `ReminderChannel` enum. Delivery is confirmed as **polling**
    (`GET /notifications/unread-count` on an interval, matching the AI
    Tools status-polling precedent already in the web store), not
    real-time push — this codebase has no WebSocket/SSE infrastructure,
    and the underlying event only updates every 10 minutes anyway (the
    beat task's own schedule), so real-time delivery would add
    first-of-its-kind infra to shave latency off a signal that's already
    capped.
  - **Interview reminders are now per-user configurable, not one global
    hardcoded value** — `sync_interview_reminders`'s `remind_at` math now
    reads `user.settings.reminder_lead_hours` when set, falling back to
    the previous global default otherwise; every existing account's
    behavior is unchanged until it opts into an override. Notification
    preferences (the master switch, plus email/push's individual
    toggles) are enforced at *send* time in `send_due_reminders`, not
    schedule time, per this module's own established precedent for
    push/device-token state — so flipping a preference takes effect
    immediately for interviews already scheduled.

### Fixed

Bugs caught and design calls corrected during this pass, before landing
on the version described above:

- **`DELETE /users/me` crashed with a `NotNullViolation`** when the
  account owned any documents — the first version iterated a
  `User.documents` ORM relationship (added for the R2-cleanup loop)
  without a delete cascade; SQLAlchemy's default behavior on a parent
  delete is to null out a child's foreign key rather than leave it
  alone, and `documents.user_id` is `NOT NULL`. `passive_deletes=True`
  (SQLAlchemy's usual fix for this) turned out not to help either, since
  it only skips managing an *unloaded* collection — this endpoint has to
  load it to read the file keys for R2 cleanup in the first place. Fixed
  by querying `Document` directly instead of via any relationship on
  `User`, sidestepping ORM cascade management entirely; the database's
  own `ondelete="CASCADE"` on `Document.user_id` still handles the
  Postgres-row side once the delete actually happens.
- **`UserSettings.in_app_notifications_enabled` was added, then removed**
  after review — unlike email/push, which reach the user *outside* this
  app (an inbox, a device buzz/badge), the in-app feed is purely
  pull-based (a list you only see if you open the bell), so there's no
  external interruption to independently opt out of. It's on whenever
  the master `notifications_enabled` switch is, matching how
  GitHub/Slack's own notification centers work (no separate opt-out from
  theirs either, only from email/push). Dropped in a new migration
  rather than editing the one that introduced it.

## v0.12.0

### Added

- **Mobile caught up to the Document-decoupling + AI Tools polish rework**
  (v0.11.0's "Documents decoupled..." and "AI Tools follow-up..." entries
  below) — backend and web had already moved; this closes the gap on the
  mobile client. Full detail in MOBILE_SUMMARY.md's "AI Tools feature"
  and "Contacts, Interviews, and Documents" sections; summary here:
  - **`application_name`** added to `Application`/`ApplicationDraft`,
    shown in `applications_list_screen.dart`'s cards, editable on
    `application_form_screen.dart`'s Details tab, and surfaced in each
    directory screen's `ApplicationSummary` (Contacts'/Interviews') and
    `application_picker.dart`'s picker results.
  - **Documents decoupled from a single Application.** `Document` lost
    `applicationId` entirely; `documents_panel.dart` reworked from
    upload/delete to **attach/detach** (`DocumentDirectoryApi` gained
    full `/documents` CRUD, new `ApplicationDocumentsApi` handles
    `list`/`attach`/`detach` against `/applications/{id}/documents`) —
    "Attach existing" via a new `document_attach_sheet.dart` search
    picker, "Upload new" via upload-then-attach (two calls, either
    exception propagates). "Remove from this application" only detaches;
    the document and its other attachments are untouched. The old
    `documents_api.dart`/`document_with_application.dart` (broken
    against the current backend contract) were deleted.
    `document_directory_screen.dart` (the bottom-nav Documents tab) is
    no longer read-only — it's now the primary place to manage the whole
    library (upload FAB, per-row overflow menu: download/view AI
    analysis/edit type/delete).
  - **AI Tools caught up to `analysis_name`/`scored_at`/server-side name
    joins**: `ResumeAnalysis`/`AtsScore` domain models gained the new
    fields; `resume_analyses_tab.dart`/`ats_scores_tab.dart` dropped
    their client-side document/application label joins entirely. New
    `resume_analysis_picker.dart` (search-based, replacing a full-preload
    bottom sheet in `new_ats_score_sheet.dart`) and
    `analysis_name_edit_sheet.dart` (rename, one edit surface — the list
    row — matching web's own decision not to duplicate it onto the
    detail screen).
  - **"Latest" framing**: `resume_analysis_detail_screen.dart` gained an
    `isLatest` param (`?isLatest=true`) — a "Latest" chip plus
    Analyzed/Scored timestamps, and an automatic existing-score lookup,
    set only when reached via the new shared
    `view_resume_analysis_action.dart` helper (used by both
    `DocumentsPanel`'s "View Analysis" and the new
    `DocumentDirectoryScreen`'s "View AI analysis" row action — the two
    are identical now that `AtsScore` has no application link at all).
  - **Search-on-focus**: all four remote-search pickers
    (`resume_document_picker.dart`, `application_picker.dart`,
    `resume_analysis_picker.dart`, `document_attach_sheet.dart`) now
    fire their debounced search on focus, not just on keystroke, so
    tapping into an empty field shows results immediately.
  - **Score ↔ analysis cross-links with real touch targets**:
    `resume_analysis_detail_screen.dart`'s existing "View score" row and
    a new mirror-image "View resume analysis" row on
    `ats_score_detail_screen.dart` (`Card`/`ListTile`, chevron trailing)
    replace what was briefly a tiny underlined text link on
    `AtsScoresTab`'s card — too small a touch target to reliably tap.
    The new row is gated by a `showAnalysisLink` param, true only when
    reached directly from the ATS Scores list/"New Score" flow (not when
    reached via the resume-analysis screen, which would make the link
    circular).
  - **`_DocumentCard` layout fix** (`documents_panel.dart` and
    `document_directory_screen.dart`): file name and "Uploaded
    {date, time}" now each get a full-width line instead of being
    squeezed by a `ListTile`'s trailing row of 3-4 `IconButton`s — those
    actions collapsed into a single overflow `PopupMenuButton`.
  - Web also gained a matching entry point: `AtsScoresView.vue`'s
    "Analysis used" column is now clickable, reusing
    `ResumeAnalysisDetailDialog.vue` to show the analysis behind a score
    without leaving the ATS Scores list.

## v0.11.0

### Added

- **AI Features (Phase 7): Resume Parser + ATS Score, backend only** —
  the first two of TODO.md's five planned AI features, and this
  codebase's first outbound LLM-provider integration (Google Gemini, via
  `google-genai`). Full detail in BACKEND_SUMMARY.md's "AI features"
  section; summary here:
  - **Two new top-level, user-owned resources** — `ResumeAnalysis`
    (`POST`/`GET /ai/resume-analyses`) and `AtsScore`
    (`POST`/`GET /ai/ats-scores`) — deliberately not nested under
    `/applications/{id}/` like Interview/Contact/Document, so ownership
    is a direct `user_id` FK rather than a join chain
  - **Async by design**: the first *per-request-dispatched* Celery tasks
    in this codebase (`send_due_reminders` is beat-scheduled, not
    request-triggered) — `POST` returns `202` with a `pending` row,
    `GET .../{id}` for polling
  - **Resume Parser**: extracts structured data (contact info, skills,
    work experience, education) from an uploaded resume `Document` via
    Gemini's structured-output mode. PDF and DOCX only this pass —
    legacy `.doc` is a documented gap, not silently broken
  - **ATS Score**: prefers the linked application's `job_url` over
    asking the user to paste anything — fetches and extracts the job
    posting server-side (`trafilatura`), SSRF-guarded (scheme allowlist,
    public-IP-only resolution re-checked on every redirect hop, size/time
    caps — see docs/SECURITY.md). Falls back to (and an explicit paste
    always wins over) a pasted `job_description` when the URL is blank
    or can't be scraped, which is common for JS-heavy/bot-blocking job
    boards, not a rare edge case
  - **Gemini structured-output gotcha**: the API rejects a
    `response_schema` with default field values, so every field on the
    four Gemini-facing schemas is `Field(...)` (required, nullable type
    instead of an omittable one) — see
    `googleapis/python-genai#699` and BACKEND_SUMMARY.md
  - **`google-genai` pinned to `2.8.0`, not latest** — `>=2.9.0` requires
    `pydantic>=2.12.5`, which would force bumping this app's core
    `pydantic==2.9.2` pin app-wide; `2.8.0` is the newest release still
    compatible. `httpx` bumped `0.27.2` → `0.28.1` for `google-genai`'s
    own requirement (confirmed safe — no affected call sites)
  - **New test pattern**: `test_ai_tasks.py` is the first test coverage
    for a Celery task that opens its own `SessionLocal()` — solved via
    SQLAlchemy 2.0's `join_transaction_mode="create_savepoint"` on a
    second session bound to the test's own connection
  - **New dev dependency `celery-types`** (PEP 561 stubs, dev-only) —
    Celery ships no `py.typed` marker, so Pyright/Pylance inferred a bare
    `FunctionType` for `@celery_app.task(...)`-decorated functions,
    reporting `.delay()` as an unknown attribute at both call sites in
    `ai.py`'s endpoints. Also added two explicit `None` guards in
    `app/tasks/ai.py` (`Session.get()` returns `Optional[T]`) and one in
    `app/services/ai/client.py` (Gemini's own stubs type `response.text`
    as `str | None`) — see BACKEND_SUMMARY.md's "Type-checker gotchas"
  - **`lxml_html_clean` pinned directly** — `trafilatura` → `justext`
    imports `lxml.html.clean`, which lxml split into a separate package;
    `justext`'s `lxml[html_clean]` extras marker doesn't reliably
    re-resolve onto an `lxml` a local environment already has installed
    bare, so it's now its own explicit line in `requirements.txt` rather
    than relying on the transitive extra
- **AI feature rate limiting, free tier** — a shared daily budget per
  user (`AI_FREE_TIER_DAILY_LIMIT`, default 10) across
  `POST /ai/resume-analyses` and `POST /ai/ats-scores`, since both draw
  on the same Gemini cost. Full detail in BACKEND_SUMMARY.md's "Rate
  limiting" section:
  - **First direct `redis` client usage in this codebase**
    (`app/services/rate_limit.py`) — Redis previously only served as
    Celery's broker/backend. Atomic `INCR` + `EXPIRE` fixed-window
    counter, keyed `ai_rate_limit:{user_id}:{date}` (UTC calendar day)
  - **Only counts an actual new Gemini dispatch** — the check runs right
    before a row is created for the request, after every existing
    validation step and the resume-analyses dedup-reuse check, so a
    request that fails validation or just reuses an in-flight analysis
    never consumes budget, and a rejected request never leaves an
    orphaned `pending` row behind
  - **`429 Too Many Requests`** with a `Retry-After` header — a new
    status code for this codebase (every other `ai.py` rejection is
    503/404/422/409)
  - **Free-tier-only, by design**: `User.role` has no premium concept
    yet, so every user gets the same limit today; the counting logic
    itself takes a plain `limit: int` with zero knowledge of tiers — one
    call site (`app/api/v1/endpoints/ai.py`) is the single place a
    future premium tier would plug in. Tiering itself (a premium role +
    a payment/upgrade flow) is a deliberately deferred product decision,
    not yet scoped as work — see TODO.md's "AI Features" section
  - **Tests use the real Redis instance** already in
    `docker-compose.yml`, not a mocking library — same philosophy as
    this suite's real-Postgres DB tests; isolation comes from
    `make_user()`'s fresh random UUID per test, not an explicit rollback
- **AI Tools web UI: Resume Parser + ATS Score** — the backend for both
  already existed; nothing consumed it on any client until now. Full
  detail in webapp/WEBAPP_SUMMARY.md's "AI Tools" section:
  - One "AI Tools" nav item over two routes (`/resume-analyses`,
    `/ats-scores`), joined by a shared tab bar copying `ViewTabs.vue`'s
    List/Board toggle shape exactly, not a new pattern. Two new stores
    (`stores/resumeAnalyses.ts`/`stores/atsScores.ts`), one per resource,
    matching every other feature's convention
  - **First async/polling UI in this frontend** — both `POST` endpoints
    return `202` with a `pending` row; each store polls `GET .../{id}`
    every 3s (40-attempt/~2min cap) until `completed`/`failed`
  - **New reusable components** (`components/ai/`): `ResumeDocumentPicker.vue`/
    `ApplicationPicker.vue` (first use of PrimeVue `AutoComplete` in this
    codebase, debounced search), `ParsedResumeDisplay.vue`/
    `AtsScoreDisplay.vue`, `AiToolsTabs.vue`
  - **New isolated store search methods** (`documentDirectory.searchResumeDocuments()`,
    `applications.searchApplications()`, plus a few on the two new AI
    stores) — reusing the existing directory stores' mutating fetch
    actions for live search would have clobbered the Documents/
    Applications List views' own state, since both are reachable in the
    same session without a reload
  - **`ResumeAnalysisModal.vue`**: a new per-row action on
    `DocumentsPanel.vue` (resume-type documents only) — view/start an
    analysis and score it against the current application directly from
    an application's Documents panel, no tab-switching or hunting
    required. Cross-linked the other direction too: a completed
    analysis's "Score against a job" button pre-fills `AtsScoresView.vue`'s
    create dialog via a `resume_analysis_id` query param
  - **Bug caught during manual verification, fixed same pass**:
    `ResumeAnalysisModal.vue`'s inline "Analyze now"/"Score now" buttons
    had no error display at all — a `503`/`429` was correctly caught by
    the store but produced zero user feedback. Fixed by rendering the
    store's `createError` in both states
- **AI Tools mobile UI: Resume Parser + ATS Score** — backend and web UI
  already existed; this is the mobile client for both. Full detail in
  MOBILE_SUMMARY.md's "AI Tools feature" section; summary here:
  - **One pushed screen with a `TabBar`, not two routes** —
    `AiToolsScreen` (`/ai-tools`, reached from a new Home-tab card), since
    mobile has no route-based tab-toggle precedent the way web's
    Applications List/Board split gave it. `FloatingActionButton` swaps
    between "New Analysis"/"New Score" based on the active tab
  - **First `Timer.periodic` usage in `mobile/lib/`**: `data/polling_timer.dart`,
    a plain (non-Riverpod) wrapper (3s interval, 40-attempt/~2min cap,
    matching the web store's constants), owned by two new `.family`-scoped
    detail controllers that are **fetch-and-poll only** — every create
    action (both FABs, "Try again", "Score again"/paste-retry) calls the
    API directly from the owning screen and navigates to a fresh detail
    route, rather than one controller instance repointing at a different
    id mid-flight. A deliberate narrowing from web's monolithic Pinia
    stores, which also own `create()`
  - **New remote-search pickers** (`resume_document_picker.dart`/
    `application_picker.dart`): debounced `TextField`s calling
    `DocumentDirectoryApi`/`ApplicationsApi` directly — needed **no new
    isolated search method**, unlike web's stores, since these API
    classes are already stateless and can't clobber the real list
    screens' state
  - **`ResumeAnalysisDetailScreen`'s existing-score lookup**: only wired
    up when reached via `DocumentsPanel`'s "View Analysis" (which threads
    its `applicationId` through as a query param) — calls
    `AtsScoresApi.latestForApplication` and shows the existing score
    instead of always offering a blank "Score against a job" button
  - **Bug caught after this shipped, fixed same pass**:
    `DocumentsPanel`'s "View Analysis" action originally called
    `ResumeAnalysesApi.create()` automatically whenever no analysis
    existed yet for a resume — silently spending one of the user's ten
    daily free-tier calls on a single tap, with no confirmation. Fixed to
    match web's `ResumeAnalysisModal.vue` contract: show a confirm dialog
    ("No analysis yet — analyze now?") and only call `create()` if the
    user agrees. A `pending`/`processing`/`failed` analysis is still
    treated as existing (navigates straight through, no new call), since
    only the true no-row-at-all case needed the guard
  - **No new tests**, matching web's/every other mobile feature's
    existing precedent

### Changed

- **Documents decoupled from a single Application; `AtsScore` drops its
  `application_id` link entirely** — a correctness rework of the AI
  Tools feature just added above, done within this same unreleased
  version rather than shipped and then fixed. Full detail in
  BACKEND_SUMMARY.md's "A note on Document / ApplicationDocument";
  summary here:
  - **The trigger was `AtsScore`, not `Document`**: it carried its own
    `application_id` alongside `resume_analysis_id`, and nothing ever
    cross-checked that the two actually agreed — a caller could score a
    resume against a different application's job posting than the one it
    was really attached to, with no error, no warning. Deriving
    `application_id` server-side instead of trusting the client doesn't
    close the gap either: `job_description`/`job_url` are always
    caller-supplied free text, so even a perfectly-derived link can't
    verify they're the *right* job. `AtsScore.application_id` was
    dropped outright rather than patched
  - **`Document` became a top-level, user-owned resource** (`user_id`
    direct FK, like `ResumeAnalysis`/`AtsScore`), reachable at
    `/documents` — no longer nested under `/applications/{id}/documents`,
    no longer owned by exactly one application. Reusable across zero,
    one, or several applications via a new many-to-many join,
    `ApplicationDocument` (`POST`/`GET`/`DELETE
    /applications/{application_id}/documents` attaches/lists/detaches).
    Deleting an application no longer deletes its documents — only the
    join rows; deleting a document still cascades its `ApplicationDocument`
    links and its `ResumeAnalysis`/`AtsScore` rows
  - **`POST /ai/ats-scores` now takes `job_url` directly in the payload**
    alongside `job_description` — no `application_id` anywhere on this
    resource any more. `job_description_source` (`pasted`/`url`) is
    recorded immediately at creation time instead of resolved later
    against an application row
  - **`ResumeAnalysis` gains `completed_at`**, set only when `status`
    transitions to `completed` — distinct from `created_at` since
    parsing is async
  - **Migration split into six small, single-purpose, chained files**
    rather than one large migration, ordered so each drop only happens
    once every migration that still needs to read the dropped column has
    already run its backfill
  - **`app/services/r2.py`'s object key format changed** —
    `users/{user_id}/applications/{application_id}/...` became
    `users/{user_id}/documents/...`, since upload no longer happens in
    the context of one application
  - **Web**: matching rework across the whole AI Tools + Documents
    surface. Full detail in WEBAPP_SUMMARY.md; summary here:
    - `stores/documents.ts` became the top-level document library store
      (list/search/upload/edit/download/delete); a new
      `stores/applicationDocuments.ts` handles one application's
      attached-documents list/attach/detach — deliberately two stores,
      not one, mirroring the backend split. `stores/documentDirectory.ts`
      retired
    - Three new reusable dialog components under `components/documents/`
      (`DocumentUploadDialog.vue`, `DocumentEditDialog.vue`,
      `DocumentAttachDialog.vue`), shared between `DocumentsPanel.vue`
      (application-scoped) and `DocumentDirectoryView.vue` (the library)
    - `AtsScoresView.vue`'s create dialog gained a third job-description
      source option — paste a job URL directly, independent of any
      tracked application — alongside the existing tracked-application
      and paste-a-description options
    - `ResumeAnalysisModal.vue` can now re-score even when a completed
      score already exists (a "Score again" toggle), since the latest
      score for a resume is no longer necessarily a score against *this*
      application's job
- **`application_name` added to `Application`** — an optional,
  user-chosen label distinguishing applications that share the same
  company/position (e.g. a re-apply after rejection). Included in
  `GET /applications`' search, and in the Contacts/Interviews directory
  endpoints' embedded `ApplicationSummary`. On web, it replaced the
  static page heading on `ApplicationFormView.vue` — the `<h1>` is now
  the editable field itself (styled to read as a heading, with a pencil
  icon + tooltip signaling it's editable), rather than a separate form
  field; falls back to `company` when blank. Also surfaced as a column in
  `ApplicationListView.vue`, `ContactDirectoryView.vue`, and
  `InterviewDirectoryView.vue`, and in `ApplicationPicker.vue`'s
  suggestions (alongside `applied_date`)
- **Webapp UI consolidation pass**, mostly mechanical but spanning many
  files — full detail in WEBAPP_SUMMARY.md:
  - New `components/common/TruncatedText.vue` (single-line ellipsis +
    `title` tooltip + explicit `max-width`, since a bare Tailwind
    `truncate` class does nothing inside an auto-layout `DataTable` cell)
    applied across every list/directory table's free-text columns
  - New `lib/tooltip.ts` (`v-tooltip` preset, PrimeVue's `Tooltip`
    directive registered globally in `main.ts`) replacing the native
    `title` attribute on icon-only action buttons — native `title` has a
    fixed, unstyleable ~1s OS-level show delay
  - New `lib/row-click.ts` (`useApplicationRowClick()`) — click-anywhere-
    in-the-row-to-navigate for `ApplicationListView.vue`,
    `ContactDirectoryView.vue`, and `InterviewDirectoryView.vue`, skipping
    clicks on an already-interactive element (a link, a button) in the
    row
  - `lib/date-utils.ts` gained shared `formatDate`/`formatDateTime`
    helpers, replacing eight separately-constructed
    `Intl.DateTimeFormat` instances across pickers/dialogs/views
  - `ResumeAnalysesView.vue`/`AtsScoresView.vue`'s inline create/detail
    dialogs extracted into their own components
    (`NewResumeAnalysisDialog.vue`/`ResumeAnalysisDetailDialog.vue`,
    `NewAtsScoreDialog.vue`/`AtsScoreDetailDialog.vue`), and
    `ContactsPanel.vue`/`InterviewsPanel.vue`'s add/edit dialogs into
    `components/contacts/ContactFormDialog.vue`/
    `components/interviews/InterviewFormDialog.vue`
  - **Bug caught and fixed during the dialog-extraction pass**:
    `ContactFormDialog.vue`/`InterviewFormDialog.vue` initially reset
    their form on a watcher keyed off the `contact`/`interview` prop —
    correct on first open, but PrimeVue's `Dialog` unmounts its slot
    content while hidden, so the underlying vee-validate `useField()`s
    reset on every close/reopen regardless, and a same-record reopen
    doesn't even change the prop (same object reference), so the reset
    watcher never re-fired at all. Fixed by keying the reset watcher off
    `visible` instead — fires on every open, and (Vue's default
    pre-flush watch timing) runs before the Dialog's content actually
    remounts
- **AI Tools follow-up: `analysis_name` (auto-generated, user-editable),
  `scored_at`, and server-side `document_file_name`/`analysis_name`
  joins** — refinements to the AI Features/AI Tools work added earlier in
  this same version. Full detail in BACKEND_SUMMARY.md's "`analysis_name`,
  `scored_at`, and server-side `document_file_name` joins" section and
  WEBAPP_SUMMARY.md's "AI Tools" section; summary here:
  - **New `ResumeAnalysis.analysis_name`** — auto-generated (slugified
    source file name + completion timestamp + a random suffix) the moment
    parsing completes, e.g. `resume_20260817_143205_a1b2c3`. Deliberately
    not DB-uniqueness-enforced, since it's also user-editable afterward
    via a new `PATCH /ai/resume-analyses/{id}` (`ResumeAnalysisUpdate`,
    the only editable field). **New `AtsScore.scored_at`** — same
    shape/lifecycle as `ResumeAnalysis.completed_at`.
  - **`document_file_name`/`analysis_name` computed properties, joined
    server-side** (`ResumeAnalysis`/`AtsScore` models, eager-loaded via
    `joinedload` in `ai.py`'s endpoints) — removes a frontend-only join
    `ResumeAnalysesView.vue`/`AtsScoresView.vue` used to build row labels
    (fetch up to 100 documents/analyses client-side, look up by id) that
    silently mislabeled anything past that 100-item cap.
  - **`GET /ai/resume-analyses` gained `status`/`search` query params**
    (`search` matches `analysis_name`) — replaces `NewAtsScoreDialog.vue`'s
    Resume picker's own 100-item preload-and-filter with a live,
    server-searched `AutoComplete`, matching `ApplicationPicker.vue`'s
    existing debounced-search pattern.
  - **New rename UI**: a pencil button on each row of
    `ResumeAnalysesView.vue` opens `EditAnalysisNameDialog.vue` (same
    single-field shape as `DocumentEditDialog.vue`). `AtsScoresView.vue`
    gained an "Analysis used" column showing the same field.
  - **New `components/ai/DocumentAnalysisModal.vue`** — the Document
    Library's own "View AI analysis" row action
    (`DocumentDirectoryView.vue`), alongside `DocumentsPanel.vue`'s
    identically-named one. Same shape as `ResumeAnalysisModal.vue`, but
    with no single application's `job_url` to default-score against —
    scoring always goes through the same 3-option
    application/URL/paste picker `NewAtsScoreDialog.vue` uses, inlined
    directly.
  - **`ResumeAnalysisModal.vue`** gained "Latest" tags and
    Analyzed/Scored timestamps on both its analysis and score sections,
    plus an "Analysis name: …" line.

## v0.10.0

### Added

- **Analytics (Phase 5), shipped across all three surfaces** — backend
  endpoints, web dashboard, and mobile screen, in that order. Full detail
  in BACKEND_SUMMARY.md's "A note on the analytics endpoints",
  WEBAPP_SUMMARY.md's "Analytics" section, and MOBILE_SUMMARY.md's
  "Analytics feature"; summary here:
  - **Backend**: four real-time, read-only endpoints —
    `GET /analytics/summary`, `/funnel`, `/activity`, `/interviews` — no
    precomputation or caching, deliberately, given current per-user data
    volumes. `response_rate` and `pass_rate` are documented proxies, not
    tracked metrics, stated directly in their schema field descriptions
    so they surface in `/docs`
  - **`application_status_history`**: new append-only audit table,
    written alongside every Application create/update, but **not** read
    by `GET /analytics/funnel` — that endpoint reads current
    `Application.status` as a snapshot instead. Deliberate: a true
    conversion funnel needs to distinguish a real status change from an
    accidental same-session toggle (e.g. a mis-dragged Kanban card), and
    that filtering logic doesn't exist yet — the table faithfully
    records every transition, accidental or not, and intentionally
    doesn't deduplicate at write time (see
    `test_flip_and_revert_records_both_transitions_undeduplicated`)
  - **Web**: `AnalyticsDashboardView.vue` (route `/analytics`) — summary
    cards, then three `chart.js` charts (first chart usage on web):
    pipeline (horizontal bar, a deliberate teal-intensity gradient
    encoding progression through the funnel), interview outcomes
    (donut), activity (bar, 3/6/12-month toggle). One Pinia store
    (`stores/analytics.ts`) covers all four endpoints, each section
    fetching/erroring independently via `Promise.allSettled`
  - **Mobile**: `features/analytics/` — same four-section structure,
    `fl_chart` (new dependency, first chart usage on mobile). Chart
    colors deliberately reuse existing app color conventions
    (`ApplicationStatusStyle`, `InterviewDirectoryScreen`'s result-chip
    colors) rather than a new chart-specific palette — the opposite
    choice from web, and intentionally so; see MOBILE_SUMMARY.md for why
    each platform's choice was the right one for that platform
- **Mobile navigation restructure** — bottom nav shrank from 4 tabs to 2
  (Applications + a new card-grid "Home" hub), to make room for Analytics
  and a future AI-tools section without further crowding the tab bar.
  Full reasoning in MOBILE_SUMMARY.md's "Navigation shell":
  - **Applications** kept its own dedicated tab (highest-frequency
    screen in the app); **Home** (`features/home/`, new) is a plain
    card-grid launcher to Interviews/Contacts/Documents/Analytics, each
    card pushing the existing route
  - Interviews/Contacts/Documents moved from bottom-nav shell branches to
    plain top-level pushed routes in `router.dart` — same pattern the
    Applications create/edit forms already used
  - **Settings screen** (`features/settings/`, new, `/settings` route) —
    currently just hosts the logout action, moved off Applications'
    AppBar. Every top-level screen reaches it via a new shared
    `SettingsIconButton` widget rather than a duplicated inline
    `IconButton`
- **Backend migrated to SQLAlchemy 2.0 query style** across all ten files
  that used the legacy `db.query()` API (`deps.py`, every endpoint file,
  `services/reminders.py`, `tasks/reminders.py`) — `select()` +
  `db.execute()` throughout, done as one deliberate consistency pass
  rather than left half-migrated. See BACKEND*SUMMARY.md's "A note on the
  SQLAlchemy 2.0 query-style migration" for the handful of
  non-mechanical translations (paginated counts, the one bulk-delete
  call, dropped `and*()` usage)

### Fixed

- Reusing an existing Postgres enum type for a new table's column
  (`application_status_history.from_status`/`to_status`, reusing
  `application_status`) failed with `DuplicateObject: type
"application_status" already exists` even with `create_type=False`
  set — root cause was using generic `sqlalchemy.Enum` instead of
  `sqlalchemy.dialects.postgresql.ENUM`; only the latter reliably honors
  `create_type`. Fixed in both the model and the migration
- `db.scalar(select(func.count())...)` is typed `int | None` even though
  `COUNT(*)` never actually returns `NULL` — every pagination `total`
  and the analytics summary counts now append `or 0` to satisfy both the
  type checker and defend against a scenario that shouldn't occur at
  runtime
- `dict(rows)` on a list of SQLAlchemy `Row` objects works at runtime but
  trips a Pyright/Pylance overload-resolution false positive — switched
  to dict comprehensions in the analytics endpoints
- `fl_chart`'s `BarTouchData(enabled: false)` isn't `const`-constructible
  in the resolved package version, even though `FlGridData`/`AxisTitles`
  are — `const` removed from that one call site only, not the whole file

## v0.9.0

### Added

- **Interview reminder system, Phase A (email) and Phase B (push)** —
  the full plan from TODO.md's "Reminder system" entry, both phases
  shipped together rather than staged. Full detail in
  BACKEND_SUMMARY.md's "Interview reminder system" and
  MOBILE_SUMMARY.md's "Push notifications"/"Timezone reporting"; summary
  here:
  - **Data model**: `InterviewReminder` (`interview_id`, `remind_at`,
    `sent_at` nullable — the idempotency guard, `channel`) and
    `DeviceToken` (`user_id`, `platform`, `token` — unique, not
    unique-per-user, so re-logging into the same device under a
    different account reassigns rather than orphans, `last_seen_at`).
    `User` gains `timezone` (nullable IANA string, UTC fallback)
  - **`app/services/reminders.py`**: `sync_interview_reminders()`,
    called from the interview create/update endpoints, keeps one
    pending row per `(interview, channel)` in sync with
    `scheduled_at`/`result` — cancelled or already-past-lead-time
    interviews get no pending row; a `PUSH` row is created
    unconditionally, even before the user has any registered device, so
    this function stays fully decoupled from device-token state
  - **`app/tasks/reminders.py`** (`send_due_reminders`, Celery beat,
    every 10 min): dispatches each due row by `channel`. Email via the
    new `app/services/email.py` (Resend in prod via direct HTTP call,
    not the SDK; MailHog locally via stdlib `smtplib` — new
    `docker-compose.yml` service, SMTP on 1025 / UI on 8025). Push via
    the new `app/services/push.py` (Firebase Admin SDK, lazily
    initialized so import doesn't crash startup before Firebase is
    configured) — fans out to every device a user has, prunes tokens
    FCM reports invalid, and treats zero devices as "nothing to send,
    nothing to retry." Each reminder commits independently so one bad
    send can't leave others in the same run un-stamped
  - **Timezone reporting**: `app/utils/timezone.py`'s
    `is_valid_timezone()` backs `UserCreate.timezone`,
    `LoginRequest.timezone`, `RefreshRequest.timezone` — silently
    ignored if missing/invalid, skipped if unchanged. Web
    (`Intl.DateTimeFormat`) and mobile (`flutter_timezone`) both report
    on register/login/refresh; web's `/auth/refresh` call now sends an
    optional body for this (previously sent none at all) — `refresh_token`
    itself remains mobile-only
  - **Device-token endpoints**: `POST`/`DELETE /users/me/device-tokens`
    (`app/api/v1/endpoints/users.py`) — register upserts by `token`,
    delete is a no-op-not-a-404 so logout can't visibly fail over it
  - **Mobile push** (`mobile/lib/features/notifications/`): permission
    request (covers Android 13+'s runtime `POST_NOTIFICATIONS`, not just
    iOS), token registration + `onTokenRefresh` re-registration, called
    from `AuthController` after **every** login/register/silent-restore
    (not just fresh login, so existing users get registered on their
    next app open with no backfill needed) and deregistered before
    logout clears the session. Tap-to-deep-link into
    `/applications/{id}/edit` unified across all three ways a tap can
    reach the app (foreground, backgrounded, terminated). New
    `flutter_local_notifications` dependency for foreground display —
    FCM/the OS only auto-show a notification while backgrounded/
    terminated, not foregrounded; this wasn't in the original plan and
    was added once the gap became apparent
  - **Android-first, iOS deferred** on the Apple Developer Program cost
    — exactly per the original plan, unchanged
  - **Not included in this pass**: multi-lead-time UI, per-user quiet
    hours, Celery-beat-on-multiple-nodes duplicate-send protection (all
    explicitly out of scope per the original plan), and test coverage
    for any of the new backend reminder/device-token code or the new
    mobile push/session-provider code (see TODO.md's Testing section)

### Fixed

Bugs caught and fixed during this pass, before landing on the working
version described above:

- `InterviewReminder.channel` was initially written with a Python-side
  `default=`, not `server_default=` — corrected to match
  `Interview.result`'s existing precedent in the same file family, since
  this column needs to be correct for any row ever inserted outside
  `sync_interview_reminders`' one ordinary path, not just rows the ORM
  happens to build through it
- The reminders migration's hand-written `downgrade()` initially
  included an explicit `DROP TYPE` for the `reminder_channel` enum —
  removed to match every prior migration's own precedent (none of them
  do this either, going back to `37f704e60528_first_migration.py`),
  even though it looks like the "more correct" cleanup in isolation.
  Flagged, not fixed: this means a full downgrade-then-upgrade cycle on
  _any_ enum-backed migration in this repo's history would hit "type
  already exists" on Postgres — a pre-existing, repo-wide gap, not
  something to special-case fix in one migration
- `users.py`'s device-token upsert assigned a raw `Literal['android',
'ios']` string directly to the `DevicePlatform`-typed model column —
  passed static type-checking failures even though it would have worked
  fine at runtime (the enum inherits from `str`). Fixed with an explicit
  `DevicePlatform(payload.platform)` conversion
- `flutter_timezone`'s `getLocalTimezone()` returns a `TimezoneInfo`
  object as of the version pinned here, not a bare `String` as some
  older package versions did — `core/utils/timezone.dart` now pulls the
  IANA name off `.identifier`
- **Dart top-level type-inference cycle** between `apiClientProvider`,
  `pushServiceProvider`, and `authControllerProvider`: even with
  explicit generic type arguments on each provider's _constructor_,
  Dart's analyzer still walked a textual reference cycle across their
  callback closures (regardless of whether a reference is inside a
  deferred callback) and refused to infer a type for any of them. Fixed
  by giving each _variable declaration_ an explicit left-hand-side type
  (`final Provider<Dio> apiClientProvider = Provider<Dio>((ref) {
... })`), not just the constructor call — a compile-time-only issue,
  distinct from the genuine runtime cycle below
- **Genuine runtime `CircularDependencyError`** between
  `apiClientProvider` and `authControllerProvider`: `authControllerProvider`
  transitively depends on `apiClientProvider` (via `pushServiceProvider`,
  needed for push-token registration), so `apiClientProvider`'s Dio
  interceptors reading `authControllerProvider` back for the bearer
  token / to force a logout — even lazily, inside callbacks that only
  ever ran well after every provider had finished building — closed a
  real cycle in Riverpod's dependency graph, thrown the first time a
  request actually exercised it (right after login, fetching the
  Applications list). Fixed by introducing two dependency-free leaf
  providers (`features/auth/presentation/session_providers.dart`:
  `accessTokenProvider`, `currentUserProvider`) that `apiClientProvider`
  reads/writes directly and `AuthController` writes on every state
  transition, plus a one-way `ref.listen` in `AuthController`'s
  constructor so externally-driven changes (a silent refresh, a forced
  logout) still reach `AuthController.state` for anything watching it
  for UI/routing
- **Push notification tap-to-deep-link from a terminated app** failed
  with `GoException: no routes for location` even though the target
  route (`/applications/:id/edit`) was correct — `PushService.initialize()`
  runs from `main()` before `runApp()` renders a first frame, so pushing
  a route immediately for the `getInitialMessage()` (terminated-app) tap
  case tried to navigate before the router's delegate was attached to a
  live `Navigator`. Fixed by deferring that one case via
  `WidgetsBinding.instance.addPostFrameCallback` — the other two tap
  paths (backgrounded, foreground) don't need this, since by the time
  either can fire the app is already fully running

## v0.8.0

### Added

- **Cross-application directory screens on mobile**
  (`mobile/lib/features/{contacts,interviews,documents}/`), closing the
  "Cross-application directory screens" TODO item and replacing all
  three `ComingSoonScreen` bottom-nav tabs. Mirrors
  `ContactDirectoryView.vue`/`InterviewDirectoryView.vue`/
  `DocumentDirectoryView.vue` — read-only, paginated, aggregate across
  every application the user owns, and point back to the owning
  application (via the existing `application-edit` route) for anything
  beyond viewing:
  - **`ContactDirectoryScreen`**: debounced text search (name or
    company), infinite scroll. Tappable email/LinkedIn per row via
    `url_launcher`, same as the nested `ContactsPanel`.
  - **`InterviewDirectoryScreen`**: `result` filter via a bottom sheet
    (no text search — `Interview` has no name-like field, matching the
    backend). Cards reuse `interview_formatting.dart`'s `formatDateTime`
    and duplicate `InterviewsPanel`'s `_ResultChip` color logic
    pixel-for-pixel.
  - **`DocumentDirectoryScreen`**: the one directory combining two
    filters at once — debounced search (file name or company) _and_ a
    `file_type` filter sheet, each clearing independently, plus a
    combined "Clear filters" affordance mirroring
    `DocumentDirectoryView.vue`'s `clearFilters()`. No download
    shortcut from the row, deliberately matching the web view's
    read-only contract. Cards reuse `application_formatting.dart`'s
    `formatDate` and duplicate `DocumentsPanel`'s `_TypeChip` color
    logic.
  - Each feature follows the same new-file shape: a `domain/
*_with_application.dart` composing the existing per-application model
    (`Contact`/`Interview`/`Document`) with its own `ApplicationSummary`
    (deliberately duplicated per feature rather than shared — mirrors
    the backend's own precedent of each directory schema owning its
    copy); a `data/*_directory_api.dart` calling the flat `GET
/contacts`/`/interviews`/`/documents` endpoint and reusing the nested
    feature's existing exception type (`ContactsException`/
    `InterviewsException`/`DocumentsException`); a `presentation/
*_directory_state.dart` + `*_directory_controller.dart` pair following
    `InterviewsListController`'s fetch/append infinite-scroll split, but
    as plain (non-`.family`) providers, since each is one global,
    cross-application list rather than something scoped per
    application; and a `*_directory_screen.dart` built from
    `ApplicationsListScreen`'s search/filter/scroll/empty-state
    conventions.
  - `app/router.dart`: all three bottom-nav branches
    (`/contacts`/`/interviews`/`/documents`) now build the real screen
    instead of `ComingSoonScreen`.

### Not included in this pass

- Widget/unit tests for the three new directory screens — same
  project-wide gap the nested Contacts/Interviews/Documents panels and
  Applications' own screens already have (see Testing in TODO.md)
- A download shortcut on `DocumentDirectoryScreen`'s rows — matches
  `DocumentDirectoryView.vue`'s read-only contract as-is; would need a
  per-row loading-state affordance like `DocumentsPanel`'s
  `_downloadingId` if added later
- `shared/widgets/coming_soon_screen.dart` is now unreferenced by
  `router.dart` (all three tabs that used it are real screens) — left
  in place rather than deleted, in case a future feature wants the same
  placeholder

## v0.7.0

### Added

- **Contacts, Interviews, and Documents on mobile** (`mobile/lib/features/{contacts,interviews,documents}/`),
  closing most of the "Interviews / Contacts / Documents feature screens"
  TODO item — each follows the existing `data`/`domain`/`presentation`
  split from `features/applications/`/`features/auth/`:
  - **`ApplicationFormScreen` restructured** (`features/applications/
presentation/application_form_screen.dart`) into a 4-tab layout —
    Details / Contacts / Interviews / Documents — mirroring
    `ApplicationFormView.vue` + its three panels on web. Tabs (a
    `TabController` driving an `AppBar`-bottom `TabBar` +
    `TabBarView`) only appear when editing an existing application;
    a brand-new one still shows just the plain Details form, same
    `!isNew && applicationId` gating the web panels use — there's
    nowhere to nest a contact/interview/document under an application
    that doesn't have an id yet. "Save Changes" only shows on the
    Details tab; the other three manage their own actions
  - **Contacts** (`features/contacts/`): unpaginated, matching the
    nested `GET /applications/{id}/contacts` backend route — plain
    local widget state, no Riverpod controller, add/edit via a modal
    bottom sheet (`ContactFormSheet`), delete via a confirm dialog.
    Email/LinkedIn are tappable (`url_launcher`)
  - **Interviews** (`features/interviews/`): paginated backend, so this
    uses the same infinite-scroll `StateNotifier` shape as
    `ApplicationsListController`, `.family`-scoped per `applicationId`
    (`InterviewsListController`). Scheduling uses the same
    `FormBuilderField<DateTime?>` + `showDatePicker` pattern
    `appliedDate` already used, extended with `showTimePicker` for the
    time component (`scheduled_at` is a full timezone-aware instant,
    not date-only) — no new date-picker package pulled in for one
    field. Create/update trigger a full `refresh()` rather than a
    local splice, since editing `scheduled_at` can change the item's
    sort position — same reasoning `stores/interviews.ts` documents on
    web; delete removes locally (no reorder ambiguity there)
  - **Documents** (`features/documents/`): also paginated
    infinite-scroll, but unlike Interviews, mutations patch local state
    directly (`prepend`/`replaceById`/`removeById`) rather than
    refetching — the list orders by `created_at DESC` and only
    `file_type` is ever editable post-upload, so neither a new upload
    nor an edit can actually change an item's position, unlike
    Interviews' `scheduled_at`. Upload is the one Create call in the
    app that sends `multipart/form-data` (`dio`'s `FormData` +
    `MultipartFile`) instead of a JSON body, matching the backend's
    `file: UploadFile = File(...)` + `file_type: DocumentType =
Form(...)` contract; file selection uses the new `file_picker`
    dependency (PDF/Word filtered client-side, same as the web upload
    dialog's `accept`, though the backend is still the real enforcement
    point). Download fetches a fresh presigned R2 URL per tap and opens
    it externally via `url_launcher` rather than downloading in-app —
    no storage permissions or save-location UI needed for a first pass
  - New dependencies: `file_picker` (document upload), `url_launcher`
    (opening a downloaded document's presigned URL, and — retrofitted
    once available — Contacts' email/LinkedIn tap targets)
- Interviews/Documents/Contacts endpoints reuse enum-with-`apiValue`/
  `label`/`fromApiValue` conventions already established by
  `ApplicationStatus` (`features/applications/domain/application.dart`)
  for `InterviewType`/`InterviewResult`/`DocumentType`. One naming
  wrinkle worth remembering: the backend's `"final"` interview-type
  value can't be a Dart enum member name (`final` is reserved), so it's
  named `InterviewType.finalRound` — `apiValue`/`fromApiValue` still
  map it to/from the real `"final"` string

### Changed

- **DateTime formatting switched from hand-rolled to `intl`**
  (`features/applications/presentation/application_formatting.dart`'s
  `formatDate`, `features/interviews/presentation/
interview_formatting.dart`'s new `formatDateTime`): both now call
  `DateFormat` (`'MMM d, y'` and `'MMM d, y · h:mm a'` respectively)
  instead of a manually-maintained month-name table and manual 12-hour
  conversion. New dependency: `intl` — added via `flutter pub add intl`
  rather than a hand-picked version pin, so pub resolves one compatible
  with whatever `flutter_localizations` version `flutter_form_builder`'s
  localization delegates already pulled in (they're versioned together
  upstream); hand-pinning risked a resolver conflict

### Not included in this pass

- Widget/unit tests for the three new features — Applications' own list/
  form screens don't have them yet either (see Testing in TODO.md), so
  this isn't a new gap, just an uncovered one growing by three features
- Cross-application Interviews/Contacts/Documents directory screens on
  mobile (the bottom-nav tabs of the same names) — still
  `ComingSoonScreen`. What shipped this pass is the _nested_,
  per-application CRUD only, mirroring `ContactsPanel.vue`/
  `InterviewsPanel.vue`/`DocumentsPanel.vue`, not
  `ContactDirectoryView.vue`/etc.
- Interview reminder system — still backend-and-frontend unimplemented
  everywhere, mobile included (see TODO.md)
- In-app document download/offline storage — downloads open externally
  only, per the "Changed" note above

## v0.6.0

### Added

- **Mobile app scaffold** (`mobile/`), the start of Phase 6 (Mobile
  Application): Flutter + Riverpod + go_router + Dio, per the
  architecture doc's planned stack. Feature-based `lib/` folder
  structure (`app/`, `core/`, `features/`, `shared/`) mirroring the
  backend's API/Service/Repository layering; `analysis_options.yaml`
  roughly matching the strictness of the backend's `ruff`/webapp's
  `eslint` configs; `.github/workflows/mobile-ci.yml` (format check →
  analyze → test → debug APK build, `mobile/**`-scoped, Android-only for
  now — an iOS build step needs a `macos-latest` runner, deferred on
  cost/speed grounds until iOS testing is actually underway);
  `flutter_dotenv`-based env config (`.env.development`/
  `.env.production`, gitignored, `.env.example` committed as the
  template — non-secret by design, since these are bundled as app
  assets and technically extractable from a built app). One smoke test
  (`test/app_smoke_test.dart`). Full detail in the new
  `mobile/MOBILE_SUMMARY.md` (see below)
- **Mobile authentication** (`mobile/lib/features/auth/`): login and
  registration screens, silent session-restore on app start, and the
  full token lifecycle:
  - **Token storage strategy** (the one real architecture decision this
    phase needed): access token in memory only
    (`AuthController`'s Riverpod state), refresh token in
    `flutter_secure_storage` (Keychain/Keystore-encrypted) — the
    standard native-mobile pattern, chosen over persisting a cookie jar
    that would have reused the webapp's cookie-based refresh flow
    as-is. See `MOBILE_SUMMARY.md`'s token-storage note for the full
    trade-off writeup (cookie-jar persistence isn't hardware-encrypted;
    CSRF double-submit, which that approach would still need, defends
    against a browser-specific attack mobile was never exposed to)
  - `token_storage.dart` (secure-storage wrapper), `auth_api.dart` (raw
    Dio calls on their own bare Dio instance, deliberately separate from
    the shared client — see "Two Dio instances" below),
    `auth_repository.dart` (single source of truth for reading/writing
    the refresh token; `tryRestoreSession()` fails safe to
    "unauthenticated" on _any_ error, not just an explicit auth
    failure, so a storage-read error can't leave the app stuck at
    `AuthStatus.unknown` forever)
  - `auth_controller.dart` (Riverpod `StateNotifier<AuthState>`),
    `login_screen.dart` / `register_screen.dart` — both built on
    `flutter_form_builder` + `form_builder_validators` rather than bare
    `Form`/`TextFormField`, same reasoning as the webapp's vee-validate
    adoption (composable validators, no hand-rolled per-field
    `validate()` functions); this is the pattern every future mobile
    form should follow. Both forms validate on submit only
    (no `autovalidateMode`), which sidesteps the stale cross-field
    validation problem that made the webapp drop PrimeVue Forms
    (CHANGELOG v0.5.0) without needing an explicit re-validation
    trigger. Password rules mirror `backend/app/schemas/user.py` exactly
    (8-128 characters, plus a client-side copy of the bcrypt 72-byte
    check)
  - `core/network/api_client.dart`'s shared Dio instance gains
    bearer-token injection and a queued refresh-on-401 interceptor
    (concurrent 401s share one in-flight refresh rather than each
    triggering their own), mirroring `webapp/src/lib/api.ts`.
    Deliberately excludes `/auth/*` routes from the retry logic — the
    same infinite-refresh-loop trap the webapp hit and fixed in
    CHANGELOG v0.4.0
  - `app/router.dart` gains auth-aware redirects mirroring the webapp's
    `authGuard`: `/login` and `/register` are guest-only routes, no
    redirect happens while `AuthStatus.unknown` (startup restore in
    flight), and Riverpod state changes are bridged into go_router's
    `Listenable`-based refresh mechanism so login/logout immediately
    re-runs the redirect logic
- **Bottom navigation shell** (`app/app_shell.dart` + `router.dart`'s
  `StatefulShellRoute.indexedStack`): 4 tabs — Applications (default),
  Interviews, Contacts, Documents — chosen over the webapp's side menu;
  see `app_shell.dart`'s doc comment for the reasoning.
  Interviews/Contacts/Documents render `ComingSoonScreen`
  (`shared/widgets/coming_soon_screen.dart`) behind their tabs. Old
  placeholder home screen at `/` is gone; `ApplicationsListScreen` at
  `/applications` is now `initialLocation`
- **Applications feature** (`lib/features/applications/`), the first
  real feature screens, mirroring `webapp/src/views/applications/
ApplicationListView.vue` / `ApplicationFormView.vue` and following the
  same `data`/`domain`/`presentation` split as `features/auth/`: list
  (search, status filter, infinite scroll, pull-to-refresh) and a shared
  create/edit form with delete. Reasoning for each mobile-specific
  choice (infinite scroll vs. the webapp's `Paginator`, the salary
  min≤max cross-field check, why `appliedDate` avoids
  `FormBuilderDateTimePicker`, why a save refreshes the list instead of
  patching in place, a fix to the API error parser for FastAPI's
  list-shaped 422s) is documented in each file directly rather than
  repeated here — see the files under `presentation/` and
  `data/applications_api.dart`
- **`mobile/MOBILE_SUMMARY.md`** — new summary doc, same role as
  `BACKEND_SUMMARY.md`/`WEBAPP_SUMMARY.md`: what's implemented, what
  isn't yet, project structure, known gotchas, dev workflow

### Changed (backend — mobile-client support)

- `TokenResponse` (`app/schemas/auth.py`) gains an optional
  `refresh_token` field, populated **only** when a request carries an
  `X-Client-Platform: mobile` header (new
  `app/api/deps.py::is_mobile_client()`). Web's response body is
  completely unaffected — it keeps getting its refresh token
  exclusively via the existing httpOnly cookie. Populating this field
  unconditionally for every client would let an XSS payload on the web
  app read the refresh token straight out of the fetch response,
  defeating the entire reason that cookie is httpOnly
- New `RefreshRequest` schema (`app/schemas/auth.py`): mobile has no
  cookie to read a refresh token from (per the token-storage decision
  above), so `/auth/refresh` now also accepts one explicitly in the
  request body for mobile callers; web's refresh flow sends no body at
  all and is unaffected (the new `payload` param is `Optional`)
- `/auth/refresh` and `/auth/logout` moved from `Depends(verify_csrf)`
  to a new `Depends(verify_csrf_unless_mobile)`
  (`app/api/deps.py`) — CSRF double-submit defends against a _browser_
  riding a cookie it holds cross-site; the mobile client never holds
  that cookie meaningfully, so the check simply doesn't apply to it.
  `verify_csrf` itself is untouched; the new function just wraps it
  with an early return for mobile requests. Web's CSRF enforcement is
  unchanged
- `/auth/register` deliberately **left unchanged** — still returns
  `UserRead` only, no auto-login, no tokens. The mobile client's
  `register()` instead chains an explicit `login()` call afterward,
  rather than the endpoint's contract changing for one client type
- See `BACKEND_SUMMARY.md`'s new "A note on mobile-client auth support"
  for the full writeup

### Fixed

Bugs caught and fixed during this pass, before landing on the working
version described above:

- `AuthRepository.tryRestoreSession()` only wrapped the refresh-call
  failure case in error handling, not the initial secure-storage read —
  a storage-read error (e.g. in a widget test with no real
  Keychain/Keystore behind the platform channel, or in principle a real
  device storage fault) could leave `AuthController` stuck at
  `AuthStatus.unknown` indefinitely instead of falling back to the
  login screen. Broadened to catch any error there
- `mobile-ci.yml` failed `flutter analyze` on missing
  `.env.development`/`.env.production` assets — both are gitignored, so
  a clean CI checkout has nothing for `pubspec.yaml`'s asset
  declarations to point at. Added an explicit step generating them from
  `.env.example` before analyze/build, mirroring the local setup step

## v0.5.0

### Added

- **Cross-application Documents directory** (backend + frontend), the
  third and final directory in the Contacts/Interviews/Documents set:
  - `GET /documents` (`app/api/v1/endpoints/documents.py ::
directory_router`, registered at the top-level `/documents` prefix in
    `router.py`, alongside the existing nested
    `/applications/{id}/documents` CRUD in the same file): a flat,
    read-only, paginated listing of every document across every
    application the authenticated user owns. Same
    `Document.application_id` → `Application.user_id` join used for
    ownership on the nested CRUD route, with `contains_eager` on
    `Document.application` so the parent application's
    company/position/status come back in one query, not N+1 — same
    pattern as the Contacts/Interviews directories
  - New schemas (`app/schemas/document.py`): `ApplicationSummary`,
    `DocumentWithApplicationRead`, `DocumentWithApplicationListResponse`
    — duplicated rather than shared with `contact.py`/`interview.py`'s
    equivalents, matching those files' own precedent
  - One deliberate divergence from both prior directories: Document has
    both a name-like field (`file_name`, like Contacts' `search`) _and_
    an enum field (`file_type`, like Interviews' `result`), so this
    route supports both filters at once (`?search=` and `?file_type=`,
    combining with AND) rather than picking one. Ordering is
    `created_at` descending, matching the nested
    `GET /applications/{id}/documents` route and Contacts' directory
    (not Interviews', which orders by `scheduled_at`)
  - `backend/tests/test_documents_directory.py`: full integration suite
    against a real Postgres instance, mirroring
    `test_interviews_directory.py`'s shape — auth (including the
    refresh-token-as-access-token check), aggregation, the
    `contains_eager` correctness check, the ownership/IDOR check
    (including that neither `search` nor `file_type` can be used to leak
    another user's documents), search, file-type filtering, the two
    filters combined, and pagination. `file_url` is also asserted absent
    from this response, same contract as the nested `DocumentRead`
  - Frontend: `DocumentDirectoryView.vue` (route `/documents`, the
    "Documents" nav item — no longer disabled) + Pinia
    `documentDirectory` store (`src/stores/documentDirectory.ts`), same
    `DataTable`/`Paginator` skeleton as the other two directories, but
    combining Contacts' debounced `IconField`/`InputText` search with
    Interviews' PrimeVue `Select` filter, since the backend supports
    both at once here. New `DocumentApplicationSummary` /
    `DocumentWithApplication` / `DocumentWithApplicationListResponse` /
    `DocumentDirectoryParams` types (`src/types/document.ts`) and
    `documentTypeFilterOptions()` (`src/lib/document-ui.ts`), mirroring
    the other two directories' equivalents
  - Deliberately a separate store from `stores/documents.ts`, not an
    extension of it — same reasoning as `contactDirectory.ts`/
    `interviewDirectory.ts` vs. their per-application counterparts:
    different shape (read-only, cross-application), different endpoint,
    different lifecycle
  - Not included in this pass: component/store tests for the new
    view/store (no directory view has these yet — see TODO.md's Testing
    section) and schema-unit-test coverage of the new
    `DocumentWithApplicationRead`/etc. shapes (only integration tests
    were added, same gap the Interviews directory shipped with — see
    `test_document_schema.py`'s note, if/when added)
  - Caught during review: the directory's `created_at`-descending
    ordering test initially relied on wall-clock separation between two
    inserts to produce different timestamps, which is flaky under this
    test suite's SAVEPOINT-per-test isolation (every insert in a test
    shares one real outer transaction, so Postgres's `now()` — and
    `created_at`'s `server_default=func.now()` — can resolve to the
    _same_ instant for both rows). Fixed by setting `created_at`
    explicitly on both rows, the same fix already applied to
    `test_applications_endpoints.py`'s ordering test — worth remembering
    for any future test asserting on `created_at`/`updated_at` ordering
- **Cross-application Interviews directory** (backend + frontend),
  mirroring the `GET /contacts` / `ContactDirectoryView.vue` pattern from
  v0.4.0:
  - `GET /interviews` (`app/api/v1/endpoints/interviews.py ::
directory_router`, registered at the top-level `/interviews` prefix
    in `router.py`): a flat, read-only, paginated listing of every
    interview across every application the authenticated user owns.
    Same `Interview.application_id` → `Application.user_id` join used
    for ownership on the nested CRUD routes, with `contains_eager` on
    `Interview.application` so the parent application's
    company/position/status come back in one query, not N+1
  - New schemas (`app/schemas/interview.py`): `ApplicationSummary`,
    `InterviewWithApplicationRead`, `InterviewWithApplicationListResponse`
    — duplicated rather than shared with `contact.py`'s equivalents,
    matching that file's own precedent of each directory response owning
    its own row shape
  - One deliberate divergence from the Contacts directory: no text
    `search` param, since `Interview` has no name-like field to match
    against. The equivalent filter is `result` (`pending` / `passed` /
    `failed` / `cancelled`) — a query param, `?result=passed`, filtered
    the same way the nested endpoints filter by ownership. Ordering is
    `scheduled_at` ascending (matching the nested
    `GET /applications/{id}/interviews` route) rather than Contacts'
    `created_at` descending
  - `backend/tests/test_interviews_directory.py`: full integration suite
    against a real Postgres instance, mirroring
    `test_contacts_directory.py`'s shape — auth (including the
    refresh-token-as-access-token check), aggregation, the
    `contains_eager` correctness check (an interview must be paired with
    its own application, not the last one seen in the join), the
    ownership/IDOR check (critical here too, since there's no
    `application_id` path param), a check that the `result` filter can't
    be used to leak another user's interviews, and pagination. Adds one
    test Contacts didn't need: `scheduled_at` ordering
  - Frontend: `InterviewDirectoryView.vue` (route `/interviews`, the
    "Interviews" nav item — no longer disabled) + Pinia
    `interviewDirectory` store (`src/stores/interviewDirectory.ts`),
    same `DataTable`/`Paginator` skeleton as `ContactDirectoryView.vue`
    but with a PrimeVue `Select` result-filter in place of a text search
    box. New `InterviewApplicationSummary` / `InterviewWithApplication` /
    `InterviewWithApplicationListResponse` / `InterviewDirectoryParams`
    types (`src/types/interview.ts`) and `interviewResultFilterOptions()`
    (`src/lib/interview-ui.ts`), mirroring the Contacts directory's
    equivalents
  - Deliberately a separate store from `stores/interviews.ts`, not an
    extension of it — same reasoning as `contactDirectory.ts` vs.
    `contacts.ts`: different shape (read-only, cross-application),
    different endpoint, different lifecycle
  - Not included in this pass: component/store tests for the new
    view/store (see TODO.md's Testing section — Contacts' directory UI
    doesn't have them yet either), and updating
    `Document.file_type`-style schema unit tests to cover the new
    directory response shapes (only integration tests were added,
    unlike Contacts' schema-test coverage from v0.4.0)

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

- Analytics reporting endpoints (CSV/PDF export) — dashboard
  metrics/charts shipped in v0.10.0, export did not
- Test coverage for the analytics endpoints and the
  `application_status_history` write path (backend), and for the new
  Analytics/Home/Settings screens (web and mobile) — none of this pass's
  new code has tests yet
- The webapp's home page (`/`, `DashboardView.vue`) is still an empty
  placeholder — see WEBAPP_SUMMARY.md's "Known gap"
- Celery tasks: email (interview reminders, v0.9.0) and resume
  parsing/ATS scoring (v0.10.0, this release) are now live; Job Match,
  Cover Letter Generator, and Interview Coach's AI processing tasks
  remain unwritten
- RBAC beyond a `role` column
- Test coverage for the reminder system (backend and mobile) — see
  TODO.md's Testing section
- Combined account/settings screen (password reset, timezone override,
  notification preferences) — see MOBILE_SUMMARY.md
- Application edit form: adopt PrimeVue Forms + a validation library,
  including dirty-state tracking for the "Save changes" button (see
  v0.4.0's Known Issues)
- Webapp component/store tests for Applications UI, and the Contacts/
  Interviews/Documents UI added in v0.4.0
