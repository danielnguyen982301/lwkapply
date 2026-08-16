# LwkApply - Job Tracker — Mobile Client

Flutter + Riverpod + go_router + Dio, implementing Phase 6 (Mobile
Application): project scaffold, auth, and the Applications feature
(list/create/edit/delete). Contacts, Interviews, and Documents are
implemented twice over, same as on web: nested inside
`ApplicationFormScreen`'s own 4-tab layout (Details / Contacts /
Interviews / Documents) for per-application CRUD — see "Contacts,
Interviews, and Documents" below — and as read-only cross-application
directory screens (mirroring `ContactDirectoryView.vue`/
`InterviewDirectoryView.vue`/`DocumentDirectoryView.vue` on web) — see
"Cross-application directory screens" below. The app also registers for
and displays push notifications for interview reminders (Android only —
see "Push notifications" below) and reports the device's timezone to the
backend (see "Timezone reporting" below).

The bottom nav shrank from 4 tabs to 2 (Applications + a card-grid
"Home" hub) to make room for Analytics and AI Tools without crowding
the tab bar further — see "Navigation shell" below for the full
reasoning. Settings now exists as its own screen (currently just
hosting the logout action, moved off Applications' AppBar) — see
"Settings screen" below. Analytics is implemented — see "Analytics
feature" below.

**As of this pass**: AI Tools (Resume Parser + ATS Score) is
implemented — the backend and web UI already existed; this is the
mobile client for both. See "AI Tools feature" below.

Package name: `lwkapply_mobile`.

## What's implemented

### Project scaffold

- **Build tooling**: standard `flutter create` project (Android + iOS
  host projects under `android/`/`ios/`), feature-based `lib/` structure
  (see Project structure below) mirroring the backend's
  API/Service/Repository layering
- **State management**: Riverpod (`flutter_riverpod`); no code
  generation in use yet (`riverpod_generator`/`build_runner` are in
  `pubspec.yaml` for future use, but nothing currently depends on them)
- **Routing**: `go_router`, auth-aware (see Authentication below)
- **Networking**: Dio, one shared instance (`apiClientProvider`) for
  authenticated feature requests, plus a separate bare Dio instance
  inside the auth feature purely for auth calls (see "Two Dio instances"
  note below)
- **Environment config**: `flutter_dotenv`, `.env.development`/
  `.env.production` (gitignored, git history should never contain real
  values) loaded from `.env.example`'s template — currently only holds
  `API_BASE_URL`, non-secret by design since these files are bundled as
  app assets and are technically extractable from a built app
- **Lint config**: `analysis_options.yaml` on top of `flutter_lints`,
  roughly matching the strictness of the backend's `ruff` / webapp's
  `eslint` setups (`strict-casts`, `strict-inference`, `strict-raw-types`,
  `require_trailing_commas`, etc.)
- **CI** (`.github/workflows/mobile-ci.yml`): format check → analyze →
  test → debug APK build, triggered only on `mobile/**` changes.
  Android-only build for now — a `flutter build ios` step needs a
  `macos-latest` runner (Linux runners can't build iOS at all), which
  costs meaningfully more Actions-minutes than Linux; deferred until iOS
  testing is actually underway, not a permanent decision
- One smoke test (`test/app_smoke_test.dart`): boots the app with a fake
  `TokenStorage` override (see Testing notes below) and asserts the
  login screen renders

### Authentication (`lib/features/auth/`)

Full login + registration flow, plus silent session restore on app
start. No password-reset screen yet.

- **Token storage strategy** (the one real architecture decision here):
  access token lives in memory only (inside `AuthController`'s Riverpod
  state), refresh token lives in `flutter_secure_storage`
  (Keychain-backed on iOS, Keystore-backed encryption on Android). This
  is the standard native-mobile pattern and was chosen over persisting
  a cookie jar (`dio_cookie_manager` + `persist_cookie_jar`, which would
  have reused the webapp's cookie-based refresh flow untouched) because:
  - cookie-jar persistence is just app-sandboxed file storage, not
    hardware-encrypted, weaker at rest than secure storage
  - CSRF double-submit (which the cookie approach would still need)
    exists specifically to stop a _browser_ auto-riding a cookie
    cross-site — a native app was never exposed to that in the first
    place, so carrying the complexity would buy nothing
  - See BACKEND_SUMMARY.md's "mobile-client auth support" note for the
    backend-side half of this decision (the `X-Client-Platform: mobile`
    header, and why CSRF is skipped for mobile specifically because of
    this).
- **`lib/features/auth/domain/`**
  - `user.dart` — mirrors the backend's actual `UserRead` schema
    exactly: `id`, `email`, `firstName`, `lastName`, `isActive`,
    `avatarUrl`. Deliberately **no `role` field** — `UserRead` never
    exposes it (role only exists on the ORM model, used server-side for
    `require_admin`); an earlier draft of this file assumed a `role`
    field existed and threw a null-cast error in production until
    corrected against the real schema
  - `auth_state.dart` — `AuthStatus` (`unknown` / `authenticating` /
    `authenticated` / `unauthenticated`) and `AuthState`
- **`lib/features/auth/data/`**
  - `token_storage.dart` — thin wrapper around `flutter_secure_storage`,
    only ever touches the refresh token
  - `auth_api.dart` — raw Dio calls (`login`, `register`, `refresh`,
    `logout`, `fetchMe`), deliberately on its **own bare Dio instance**
    separate from `apiClientProvider` (see "Two Dio instances" below).
    Sends `X-Client-Platform: mobile` on login/register/refresh so the
    backend can brand the response accordingly. `register()` does
    **not** treat `/auth/register`'s response as tokens — that endpoint
    only returns `UserRead` — it chains an explicit `login()` call
    afterward instead
  - `auth_repository.dart` — combines the two above into
    `login`/`register`/`logout`/`tryRestoreSession`/`refreshAccessToken`.
    Both `AuthController` and the API client's 401-interceptor call
    through this one class, so there's exactly one place that
    reads/writes the refresh token. `tryRestoreSession()` catches _any_
    exception (not just an explicit auth failure) and fails safe to "no
    session" — a storage-read error on a real device should drop the
    user at the login screen, not hang the app forever at
    `AuthStatus.unknown`
- **`lib/features/auth/presentation/`**
  - `auth_controller.dart` — Riverpod `StateNotifier<AuthState>`,
    silently attempts session restore on creation
  - `login_screen.dart` / `register_screen.dart` — both built on
    `flutter_form_builder` + `form_builder_validators`, chosen over bare
    `Form`/`TextFormField` for the same reason the webapp adopted
    vee-validate: composable validators, no per-field hand-rolled
    `validate()` functions. **Use this same pattern for every future
    form** — don't mix bare `TextFormField` and `FormBuilderTextField` in
    the same app (see `features/applications/presentation/
application_form_screen.dart` for how cross-field validation ended
    up working out fine in form_builder, no `reactive_forms` needed)
- **`lib/core/network/api_client.dart`** — the shared Dio instance used
  by every _other_ feature. Bearer-token injection + queued
  refresh-on-401, mirroring `webapp/src/lib/api.ts`. Excludes `/auth/*`
  from retry logic (CHANGELOG v0.4.0's fix). `features/applications/
data/applications_api.dart` is the first non-auth consumer
- **`lib/app/router.dart`** — auth-aware redirects mirroring the
  webapp's `authGuard`. Now also defines the bottom-nav shell route and
  the Applications form routes — see below

### Navigation shell

`lib/app/app_shell.dart` + `router.dart`'s `StatefulShellRoute
.indexedStack`: bottom `NavigationBar`, now just **2 tabs** — Applications
(default) and Home.

**This shrank from the original 4 tabs, per a dedicated planning
discussion** (not written down elsewhere but summarized in
`app_shell.dart`'s own doc comment): a bottom nav realistically caps out
around 4–5 destinations before it gets crowded and hard to tap
accurately, and Analytics plus a future AI-tools section both needed
somewhere to live. Two options were considered — nesting a second-level
tab bar inside a "Home" tab (rejected: recreates the same crowding
problem one level deeper, and adds a tap to reach Applications
specifically) versus a flat card-grid launcher (chosen: normal push
navigation, no nested navigation system, and scales to more future
destinations without ever needing a 3rd/4th/5th tab again).

- **Applications kept its own dedicated tab.** It's the single
  highest-frequency screen in the app — the primary daily workflow, not
  a "check occasionally" screen like the other three — so it stays one
  tap away rather than being folded into Home like everything else.
- **Home** (`lib/features/home/presentation/home_screen.dart`, new) is a
  plain `StatelessWidget` card-grid launcher with no fetched state of its
  own: Interviews, Contacts, Documents, and (as of this pass) Analytics,
  each pushing its existing route (`context.push('/interviews')` etc.)
  and covering the bottom nav, same as tapping into an application's
  edit form already did. An AI-tools card is a planned future addition,
  explicitly marked with a comment showing exactly where it slots in,
  not part of this pass.
- **Interviews/Contacts/Documents moved from shell branches to plain
  top-level pushed routes** in `router.dart` (same pattern the
  Applications create/edit forms already used) — they're no longer part
  of the `StatefulShellRoute`'s `IndexedStack` at all, since they're
  reached from Home's cards now, not tapped directly as tabs. Each still
  gets a back button for free from go_router's default
  `automaticallyImplyLeading`, purely from no longer being a shell root —
  no code change was needed in the screens themselves for that part.
- **Settings** (see "Settings screen" below) also lives behind an icon on
  individual screens' AppBars now, not a tab — logout moved there from
  Applications' AppBar in this same pass.

A bottom tab bar (rather than a webapp-style side menu) remains the right
call for mobile: every top-level destination stays reachable in at most
two taps, which matters for a tool meant to be checked daily.
`ComingSoonScreen` (`lib/shared/widgets/coming_soon_screen.dart`) remains
unreferenced by the router, left in place for any future placeholder
need.

### Settings screen

`lib/features/settings/presentation/settings_screen.dart` (new,
`/settings` route) — currently minimal on purpose: just the logout
action, moved here from Applications' AppBar because Settings didn't
have anywhere to live until this pass gave it a real entry point. Every
top-level screen that needs a way into Settings uses the same shared
`SettingsIconButton` widget
(`lib/features/settings/presentation/settings_icon_button.dart`) in its
`AppBar.actions`, rather than each screen duplicating an inline
`IconButton`.

**Why not hoist this into `AppShell` instead of repeating it per
screen**: `AppShell` only wraps `navigationShell` — i.e. whatever the
active _tab branch_ (Applications or Home) is currently rendering.
Interviews/Contacts/Documents/Settings are all plain pushed routes
sitting entirely _outside_ the shell's widget tree (that's the point of
a pushed screen — it covers the shell, bottom nav included), so
`AppShell` has no way to reach them even in principle. Hoisting the icon
into `AppShell` would only deduplicate it for 2 of the 5 screens that
need it. `SettingsIconButton` is the practical middle ground: still one
line per screen, but the icon/tooltip/target route lives in exactly one
place instead of five.

**Not part of this pass** (still true per BACKEND_SUMMARY.md's parallel
note): password reset, timezone override, and notification preferences —
already noted elsewhere as a planned combined account/settings screen.
This screen exists so logout has a proper home now; it grows into that
fuller screen later rather than needing a second relocation.

### Analytics feature (`lib/features/analytics/`)

Mobile counterpart to `webapp/src/views/analytics/
AnalyticsDashboardView.vue`, reached from the Analytics card on the Home
tab. Same `data`/`domain`/`presentation` split as every other feature,
and the same four independently-loading sections as the web dashboard
(Overview, Pipeline, Interview Outcomes, Activity) — see
`AnalyticsController`'s doc comment for why each of the four
`GET /analytics/*` calls fetches (and errors) on its own rather than as
one combined request.

- **New dependency: `fl_chart`** (not `syncfusion_flutter_charts`) — MIT
  licensed with no commercial-tier ceiling, chosen back when Analytics
  was first being planned. First chart usage on mobile, same milestone
  `chart.js` was on web.
- **Chart colors deliberately reuse existing app conventions, not a new
  chart-specific palette** — a genuine divergence from web's approach,
  and worth understanding why: web built a custom teal-gradient for its
  funnel because it had named design tokens (`tailwind.config.js`) but no
  existing per-status color mapping to begin with. Mobile is the
  opposite — `ApplicationStatusStyle`'s `foregroundColor(context)`
  extension already colors a given status identically everywhere it
  appears (Applications list, every directory screen's status chip), so
  introducing a second, chart-only palette here would make this screen
  the one place in the app where a status's color doesn't match its
  color everywhere else. The funnel chart's bars use
  `ApplicationStatusStyle` directly; interview-outcome colors duplicate
  `InterviewDirectoryScreen`'s private `_ResultChip` scheme-color logic
  (same reasoning as every other private-widget-color duplication in
  this codebase — nothing public to import from a private class).
- **`fl_chart` version caution**: written against the stable, long-lived
  parts of the API (`BarChartData`, `PieChartSectionData`, etc.),
  avoiding version-fragile widgets like `SideTitleWidget` (its
  constructor signature changed across releases). Hit one real
  const-constructor version mismatch during this pass —
  `BarTouchData(enabled: false)` isn't `const`-constructible in the
  resolved package version even though `FlGridData`/`AxisTitles` are; if
  `flutter analyze` flags a similar error on a different `fl_chart` class
  later, check that specific class's constructor before assuming the
  whole package needs its `const` usages stripped — most of them were
  fine as-is.
- Same three UI caveats from web carried over verbatim, not just in code
  comments but in the screen's actual copy: the funnel is a snapshot, not
  a lifetime funnel (see BACKEND_SUMMARY.md's
  `application_status_history` note); response rate is a documented
  proxy; pass rate excludes pending/cancelled.
- `AnalyticsScreen`'s doc comment explains all of the above in place,
  rather than requiring a reader to cross-reference this file.

### AI Tools feature (`lib/features/ai/`)

Mobile client for the Resume Parser + ATS Score backend
(`POST`/`GET /ai/resume-analyses`, `POST`/`GET /ai/ats-scores`) —
backend and web UI already existed (see `BACKEND_SUMMARY.md`'s "AI
features" and `WEBAPP_SUMMARY.md`'s "AI Tools" sections); this is a
translation into this app's own idioms, not a literal port of the web
components. Same `data`/`domain`/`presentation` split as every other
feature, but two genuinely new pieces of infrastructure this codebase
didn't have before: polling and a remote-search picker.

- **One screen with a `TabBar`, not two routes joined by a shared tab
  widget.** Web's "AI Tools" nav item pairs two routes
  (`/resume-analyses`/`/ats-scores`) via `ViewTabs.vue`'s List/Board
  toggle pattern, because that pattern already existed there
  (Applications). Mobile has no route-based tab-toggle precedent
  anywhere, so `AiToolsScreen` (reached from a new "AI Tools" card on
  the Home tab, `/ai-tools`) uses Flutter's own `TabBar`/`TabBarView`
  instead — one pushed screen, two tabs (`ResumeAnalysesTab`/
  `AtsScoresTab`), a `FloatingActionButton` that swaps between "New
  Analysis"/"New Score" based on the active tab.
- **`data/polling_timer.dart`**: a plain (non-Riverpod) `PollingTimer`
  wrapping `Timer.periodic` (3s interval, 40-attempt/~2min cap, matching
  `webapp/src/stores/resumeAnalyses.ts`'s constants for consistency
  across clients), with `start({onTick, onTimeout})`/`stop()`. Both
  detail controllers below own one as a private field. First
  `Timer.periodic` usage anywhere in `mobile/lib/`.
- **Detail controllers are fetch-and-poll only** —
  `resume_analysis_detail_controller.dart`/`ats_score_detail_controller.dart`,
  `.family`-scoped by id (mirroring `InterviewsListController`'s
  per-application family-scoping, here scoped by resource id instead).
  Deliberately narrower than web's monolithic Pinia stores, which also
  own `create()`: every "create" action (the two FABs' bottom sheets,
  "Try again" on a failed analysis, "Score again"/paste-retry on a
  failed score) calls the relevant `*Api.create()` directly from the
  screen that owns the button, then navigates to a fresh
  `/resume-analyses/:id` or `/ats-scores/:id` route for the new row,
  rather than asking one controller instance to "repoint" at a
  different id mid-flight. `autoDispose` stops each controller's
  `PollingTimer` automatically when its detail screen is popped — this
  app's equivalent of web's `onUnmounted`-calls-`stopPolling()`
  convention.
- **`resume_document_picker.dart`/`application_picker.dart`**: no prior
  art anywhere in this app (or on web, where the equivalent was also
  new) for a "remote search picker" — a plain debounced (350ms,
  matching the existing constant) `TextField` + results list below it,
  not Flutter's built-in `Autocomplete<T>` (its async `optionsBuilder`
  integration was fiddlier to get predictably right than a small
  purpose-built widget). Both call their target API class
  (`DocumentDirectoryApi`/`ApplicationsApi`) directly rather than
  through `DocumentDirectoryController`/`ApplicationsListController` —
  and unlike web, this needed **no new isolated search method**: those
  API classes are already stateless, so calling `.list(search: ...)`
  directly from a picker can never disturb the real Documents/
  Applications list screens' own state the way reusing a Pinia store's
  paginated fetch action would have. A genuine architectural difference
  worth remembering, not an oversight.
- **`new_ats_score_sheet.dart`**: a `SegmentedButton` toggles between
  "Tracked application" (`ApplicationPicker`) and "Paste a job
  description" (a plain multiline `TextField`, 50–20000 char hint,
  server is the real validator) — mirrors web's automatic-job_url-first/
  paste-as-fallback contract, just surfaced as an upfront choice instead
  of a retry path. Also accepts an optional `initialAnalysis` (used by
  `ResumeAnalysisDetailScreen`'s "Score against a job" button), which
  skips the resume-picker step entirely.
- **The completed-resume-analysis picker inside `new_ats_score_sheet.dart`
  and the label lookups in `resume_analyses_tab.dart`/`ats_scores_tab.dart`**
  all solve the same problem: `ResumeAnalysisRead`/`AtsScoreRead` carry
  no human-readable file name, so each fetches the user's resume
  documents (and, for scores, applications) once via the existing
  directory/list APIs and joins client-side — same fix, applied
  independently at each call site rather than factored into shared
  infrastructure, since each needed a slightly different shape (a
  bottom-sheet list vs. a plain `Map` lookup).
- **`ResumeAnalysisDetailScreen`'s existing-score lookup**: only wired
  up when reached via `DocumentsPanel`'s "View Analysis" row action,
  which threads its `applicationId` through as a `?applicationId=`
  query param (the one entry point into this screen that actually has
  an application in context — `AiToolsScreen`'s tab/create flow has
  none, since a resume analysis isn't owned by any single application).
  When present, the screen calls `AtsScoresApi.latestForApplication`
  and shows the existing score (with a "Score again" fallback) instead
  of always offering a blank "Score against a job" button as if nothing
  had ever been scored.
- **`DocumentsPanel`'s "View Analysis" row action** (resume documents
  only) fetches the latest `ResumeAnalysis` for that document
  (`latestForDocument`, a page-size-1 trick) and pushes
  `ResumeAnalysisDetailScreen` — reusing the exact same screen/
  controller `AiToolsScreen`'s tab uses, so there's no second
  implementation of the polling/display logic. If no analysis exists
  yet, it does **not** silently call `create()` — that hits a
  rate-limited AI call, so it shows a confirm dialog ("No analysis yet
  — analyze now?") first, mirroring web's `ResumeAnalysisModal.vue`'s
  explicit "Analyze now" button. This was a bug caught after the first
  pass shipped (see CHANGELOG.md v0.11.0): the initial version called
  `create()` automatically whenever `latestForDocument` returned
  nothing, which meant one tap on a never-analyzed resume silently
  spent one of the user's ten daily free-tier calls with no
  confirmation. Note this only guards the *no-row-at-all* case — a
  `pending`/`processing`/`failed` analysis is still non-null and
  navigates straight through without a new `create()` call, same as
  intended.
- **Result display**: `parsed_resume_card.dart`/`ats_score_result_card.dart`
  mirror `ParsedResumeDisplay.vue`/`AtsScoreDisplay.vue` field-for-field
  (skills/keywords as `Chip`s, work experience/education lists, the
  scrollable "job description used" box). Plain widgets, not `Card`s,
  embedded directly in each detail screen's scroll body.
- **Pushed screens, not a dialog or bottom sheet**, for both detail
  views and "View Analysis" — web used a `Dialog` (desktop has the
  vertical room); this app's own convention reserves bottom sheets/
  `AlertDialog` for short forms and confirmations, and a scrollable
  parsed-resume-plus-score result is closer to Analytics/Documents-
  directory content, which are full pushed screens here.
- **No new tests** — same "not part of this pass" precedent every other
  mobile feature and the web AI Tools work already established (see
  Testing below).

### Applications feature (`lib/features/applications/`)

First real feature screens, same `data`/`domain`/`presentation` split
as `auth/`. Mirrors `webapp/src/views/applications/
ApplicationListView.vue` / `ApplicationFormView.vue`. Full reasoning
(why infinite scroll over a `Paginator`, the salary cross-field
validation approach, why `appliedDate` avoids `FormBuilderDateTimePicker`,
the list/form sync strategy, the FastAPI error-shape fix) is in each
file's doc comments — worth reading there rather than duplicating here:

- `domain/application.dart`, `application_draft.dart`
- `data/applications_api.dart`
- `presentation/applications_list_state.dart`,
  `applications_list_controller.dart`, `applications_list_screen.dart`
- `presentation/application_form_screen.dart`, `application_form_result.dart`
- `presentation/application_status_style.dart`, `application_formatting.dart`

One thing worth flagging at this level rather than a single file's: the
list is ordered by `updated_at DESC` server-side
(`backend/app/api/v1/endpoints/applications.py`), so a save refreshes
the list instead of patching the edited item in place (its position may
have changed) — same trap the webapp's Interviews/Documents panels hit
in v0.5.0. A delete removes the item locally instead, since that has no
ordering ambiguity.

### Contacts, Interviews, and Documents (`lib/features/{contacts,interviews,documents}/`)

Nested, per-application CRUD for all three, added to
`ApplicationFormScreen` as a 4-tab layout (Details / Contacts /
Interviews / Documents) rather than as separate screens — see
`ApplicationFormScreen`'s own class doc comment. Tabs only appear when
editing an existing application (`!isNew && applicationId`, same
gating `ContactsPanel.vue`/`InterviewsPanel.vue`/`DocumentsPanel.vue`
use on web); a brand-new application still shows just the plain
Details form. Each feature follows the same `data`/`domain`/
`presentation` split as `auth/`/`applications/`, but the three differ
from each other and from Applications in ways worth knowing before
touching any of them:

- **Contacts** — the nested backend list
  (`GET /applications/{id}/contacts`) is deliberately unpaginated (see
  BACKEND_SUMMARY.md), so `ContactsPanel` keeps plain local `State`
  (a `List<Contact>` + a loading/error enum) rather than a Riverpod
  controller — there's nothing else on screen that needs to observe
  it, same reasoning `ApplicationFormScreen` gives for keeping its own
  submit state local. Add/edit is a modal bottom sheet
  (`ContactFormSheet`); delete goes through a confirm `AlertDialog`.
  Email and LinkedIn URL are tappable via `url_launcher`
  (`mailto:`/`https:`) once a value is present.
- **Interviews** — the nested list IS paginated, so this reuses
  `ApplicationsListController`'s infinite-scroll `StateNotifier` shape
  instead, `.family`-scoped per `applicationId`
  (`InterviewsListController`, `interviews_list_state.dart`). Create
  and update both trigger a full `refresh()` (reload from page 1)
  rather than patching the changed item into `items` in place —
  `scheduled_at` determines sort order server-side, so a client-side
  guess at where a new/edited interview belongs could land in the
  wrong spot, the same trap `stores/interviews.ts` and the Applications
  list already document. Delete removes locally with no refetch (no
  reordering risk there). Scheduling a date & time reuses
  `appliedDate`'s `FormBuilderField<DateTime?>` + `showDatePicker`
  pattern (`application_form_screen.dart`), with a second
  `showTimePicker` call chained on for the time component — no new
  date-picker package pulled in for this one field.
  `interview_formatting.dart` formats the result for display.
- **Documents** — also paginated infinite-scroll, but _unlike_
  Interviews, `DocumentsListController` patches state locally for every
  mutation (`prepend` on upload, `replaceById` on a file-type edit,
  `removeById` on delete) — the nested list orders by
  `created_at DESC` and only `file_type` is ever editable after upload,
  so neither action can actually change an item's sort position the
  way editing an interview's `scheduled_at` can; a full refresh would
  just be a slower way to reach the same state. Upload
  (`DocumentUploadSheet`) is the one Create call anywhere in this app
  that sends `multipart/form-data` instead of a JSON body — the
  backend takes `file: UploadFile = File(...)` +
  `file_type: DocumentType = Form(...)`, so `DocumentsApi.upload` builds
  a `dio` `FormData` with a `MultipartFile` rather than calling
  `draft.toJson()` the way every other resource's Create does. File
  selection uses the new `file_picker` dependency, filtered to
  PDF/Word client-side (same as the web upload dialog's `accept`
  attribute — the backend's `Content-Type` check is still the real
  enforcement point, not this filter). Download
  (`DocumentsApi.download`) fetches a fresh short-lived presigned R2
  URL per tap and hands it to `url_launcher` to open externally
  (browser/PDF viewer) — no in-app download-to-storage yet, see "Not
  yet implemented" below.

**Enum conventions**: `InterviewType`, `InterviewResult`, and
`DocumentType` all follow `ApplicationStatus`'s existing
`apiValue`/`label`/`fromApiValue` pattern
(`features/applications/domain/application.dart`) rather than
introducing a new convention. One naming wrinkle: the backend's
`"final"` interview type can't be a Dart enum member (`final` is a
reserved keyword), so it's `InterviewType.finalRound` on the Dart side
— `apiValue`/`fromApiValue` still map it to/from the real `"final"`
string, so nothing about the wire format changes.

**New dependencies this pass**: `file_picker` (document upload),
`url_launcher` (opening a document's presigned URL, and — once
available — Contacts' email/LinkedIn tap targets), `intl` (see next
section).

### Cross-application directory screens (`lib/features/{contacts,interviews,documents}/`)

The bottom-nav Interviews/Contacts/Documents tabs (previously
`ComingSoonScreen`), mirroring
`ContactDirectoryView.vue`/`InterviewDirectoryView.vue`/
`DocumentDirectoryView.vue` — a different thing from the nested,
per-application panels above, and read-only for the same reason those
web views are: uploads/edits/deletes still only happen from within the
owning application, reached via `context.push('/applications/{id}/edit')`
on any row (the existing `application-edit` route).

Each of the three follows one consistent shape, added alongside (not
replacing) each feature's existing nested files:

- **`domain/*_with_application.dart`** — composes the existing
  per-application model (`Contact`/`Interview`/`Document`) with a new
  `ApplicationSummary` (id/company/position/status), rather than
  duplicating its fields. Each feature declares its own
  `ApplicationSummary`, not a shared one — mirrors the backend's own
  precedent of each directory schema owning its copy (see
  BACKEND_SUMMARY.md); a future screen needing two directories' types
  at once would need a prefixed import.
- **`data/*_directory_api.dart`** — calls the flat `GET
/contacts`/`/interviews`/`/documents` endpoint and reuses the nested
  feature's existing exception type (`ContactsException`/
  `InterviewsException`/`DocumentsException`) rather than declaring a
  new one.
- **`presentation/*_directory_state.dart` + `*_directory_controller.dart`**
  — the same fetch/append infinite-scroll split
  `InterviewsListController` established, but as a plain (non-`.family`)
  `StateNotifierProvider`, since each is one global, cross-application
  list rather than something scoped per application. Read-only: no
  mutation methods, unlike `DocumentsListController`'s
  `prepend`/`replaceById`/`removeById`.
- **`presentation/*_directory_screen.dart`** — built from
  `ApplicationsListScreen`'s scroll/empty-state/footer conventions, with
  a filter UI that differs per resource since the backend's own filter
  support differs:
  - **Contacts** — debounced text search only (name or company).
    Tappable email/LinkedIn per row via `url_launcher`, same as
    `ContactsPanel`.
  - **Interviews** — a `result` filter via a bottom sheet (lifted from
    `ApplicationsListScreen`'s status-filter sheet shape); no text
    search, since `Interview` has no name-like field. Cards reuse
    `interview_formatting.dart`'s `formatDateTime` and duplicate
    `InterviewsPanel`'s private `_ResultChip` color logic.
  - **Documents** — the one directory with two filters at once: the
    Contacts-style debounced search (file name or company) _and_ the
    Interviews-style `file_type` filter sheet, clearing independently,
    plus a combined "Clear filters" action mirroring
    `DocumentDirectoryView.vue`'s `clearFilters()`. No download
    shortcut on the row — deliberately matches the web view's
    read-only contract as-is. Cards reuse
    `application_formatting.dart`'s `formatDate` and duplicate
    `DocumentsPanel`'s private `_TypeChip` color logic.

  Every screen also renders an `_StatusChip` for the embedded
  application status, styled via `ApplicationStatus`'s own
  `backgroundColor(context)`/`foregroundColor(context)` extension —
  duplicated per file (each is private), same reasoning as the
  result/type chips above.

`app/router.dart`'s three bottom-nav branches now build these screens
directly instead of `ComingSoonScreen`.

### DateTime formatting uses `intl`

`application_formatting.dart`'s `formatDate` and
`interview_formatting.dart`'s `formatDateTime` both call `intl`'s
`DateFormat` (`'MMM d, y'` and `'MMM d, y · h:mm a'`) rather than a
hand-rolled month-name table and manual 12-hour conversion — the
latter was a reasonable zero-dependency starting point (see
`application_formatting.dart`'s original doc comment) but not worth
maintaining by hand once a second, time-aware format was needed for
Interviews. Add `intl` via `flutter pub add intl`, not a hand-picked
version pin — pub then resolves a version compatible with whatever
`flutter_localizations` version `flutter_form_builder`'s localization
delegates already pulled in (the two are versioned together upstream),
which hand-pinning risks conflicting with.
`interview_formatting.dart`'s `formatDateTime` still expects an
already-`.toLocal()`-converted `DateTime` — `scheduled_at` is stored
and sent as a UTC instant (see `InterviewDraft`'s doc comment), so
callers convert once at the display boundary rather than this function
guessing at intent.

### Two Dio instances, on purpose

`auth_api.dart` uses its own bare `Dio()` (base URL only, no
interceptors), completely separate from `apiClientProvider`
(`core/network/api_client.dart`). This isn't an oversight: the shared
client's `onError` interceptor calls back into `AuthRepository` to
perform a silent refresh on a 401. If auth calls themselves went through
that same client, a failed login/refresh could recursively trigger the
interceptor's own refresh logic. Keep this split when adding any new
auth-related network call.

### `accessTokenProvider`/`currentUserProvider` — why the session lives outside `AuthController`

`apiClientProvider`'s interceptors read/write two small, dependency-free
`StateProvider`s (`features/auth/presentation/session_providers.dart`)
directly, not `authControllerProvider`. This isn't a style preference —
`authControllerProvider`'s build watches `pushServiceProvider` (for
`registerCurrentDevice()`/`deregisterCurrentDevice()`), which itself
watches `apiClientProvider` (for `DeviceTokensApi`'s Dio instance). That
makes `authControllerProvider` transitively depend on `apiClientProvider`
in Riverpod's dependency graph. The original code had
`apiClientProvider`'s interceptors read `authControllerProvider` back
for the bearer token and call its `forceLogout()`/
`updateAfterSilentRefresh()` on 401 — even though those reads only ever
fire lazily, at actual request time, well after every provider involved
had finished building, the _graph_ still had a structural cycle
(`apiClientProvider -> authControllerProvider -> pushServiceProvider ->
apiClientProvider`), and Riverpod correctly threw `CircularDependencyError`
the first time a real request triggered it (post-login, fetching the
Applications list).

The fix: `accessTokenProvider`/`currentUserProvider` are pure leaves —
they depend on nothing, so nothing that reads them can ever close a
loop. `AuthController` is still the source of truth for login/register/
logout and writes both leaves on every transition
(`_setAuthenticated`/`_setUnauthenticated`); `apiClientProvider` reads
and writes them directly for token-injection, silent-refresh, and
forced-logout, never touching `AuthController`. To keep
`AuthController.state` (what routing/UI actually watch) in sync with
changes made the _other_ direction — a silent refresh or forced logout
triggered from inside the interceptor — `AuthController`'s constructor
`ref.listen`s `accessTokenProvider` and reflects external changes into
its own `state`. **Don't reintroduce a read of `authControllerProvider`
anywhere in `api_client.dart`** — see that file's own doc comment for
the same warning.

### Push notifications (Phase B, Android only)

Implements the "Phase B (push)" half of TODO.md's reminder-system plan.
iOS is not implemented at all here, not just untested — it's gated on
the paid Apple Developer Program membership the plan calls for, same as
that plan states.

- **`lib/features/notifications/data/`**:
  - `device_tokens_api.dart` — thin wrapper over
    `POST`/`DELETE /users/me/device-tokens`, using the shared
    authenticated `apiClientProvider` Dio (unlike `auth_api.dart`, both
    calls require an already-authenticated user, so there's no reason
    for a separate bare Dio instance here)
  - `push_service.dart` — `PushService`, the orchestration layer: - `firebaseMessagingBackgroundHandler` — a required top-level
    (`@pragma('vm:entry-point')`) function; the plugin runs it in a
    separate background isolate for messages received while
    terminated/backgrounded, so it can't close over any app state.
    Deliberately minimal (just logs) — FCM/the OS already display the
    notification automatically in that case; this is only a hook for
    background _data_ processing, which reminders don't need - `registerCurrentDevice()` — requests notification permission
    (covers Android 13+'s runtime `POST_NOTIFICATIONS` permission,
    not just iOS's prompt), fetches the FCM token, registers it, and
    subscribes to `onTokenRefresh` so a token rotation (reinstall, OS
    cache clear) re-registers automatically. Called from
    `AuthController` after **every** successful login, register, _and_
    silent session restore on cold start — not just a fresh login, so
    an existing user with a persisted session gets registered the
    first time they open the app after this feature ships, with no
    backfill or forced re-login needed. Best-effort throughout: every
    failure is caught and logged, never rethrown, since none of this
    should be able to fail a login - `deregisterCurrentDevice()` — called from `AuthController.logout()`
    **before** `_repository.logout()` clears the session, since the
    DELETE call needs a still-valid Bearer token - `initialize(GoRouter router)` — called once from `main.dart`,
    after Firebase init and before `runApp()`. Sets up the local
    notification channel/plugin, the foreground message listener, and
    tap-to-deep-link for all three ways a tap can reach the app:
    foreground (via `LocalNotifications`' tap callback), backgrounded
    (`onMessageOpenedApp`), and terminated (`getInitialMessage`) — all
    three converge on one `_handleTapData`, which reads
    `data['type'] == 'interview_reminder'` and
    `data['application_id']` (keys set by the backend's `_build_push`,
    see BACKEND*SUMMARY.md) and pushes `/applications/{id}/edit` - The `getInitialMessage()` (terminated-app) tap path is
    deliberately deferred via `WidgetsBinding.instance
.addPostFrameCallback` rather than pushed immediately: `initialize()`
    runs from `main()` \_before* `runApp()` has rendered a first frame,
    so the router's delegate isn't attached to a live `Navigator` yet.
    Pushing that early failed with a spurious `GoException: no routes
      for location` — a lifecycle-timing problem, not an actual
    route-matching one. The other two tap paths don't need this: by
    the time either can fire, the app is already fully running
  - `local_notifications.dart` — `LocalNotifications`, wrapping
    `flutter_local_notifications`. Its only job: FCM/the OS
    automatically show a notification while backgrounded/terminated,
    but **not** while the app is foregrounded — this fills that one
    gap. Deliberately knows nothing about FCM/`RemoteMessage`;
    `PushService` converts a message into `(title, body, data)` before
    calling `show()`, keeping this a pure display concern. Creates the
    `interview_reminders` Android notification channel on init; a
    tapped notification's payload is JSON-encoded `data`, decoded back
    by `PushService`
- **`lib/features/auth/presentation/auth_controller.dart`**: calls
  `registerCurrentDevice()`/`deregisterCurrentDevice()` at the points
  described above
- **`lib/main.dart`**: `Firebase.initializeApp()` and
  `FirebaseMessaging.onBackgroundMessage(...)` registration happen
  unconditionally before `runApp()`; an explicit `ProviderContainer` is
  built (rather than letting `ProviderScope` create one implicitly) so
  `PushService.initialize()` can reach the _same_ `routerProvider`
  instance the widget tree will later use, via
  `UncontrolledProviderScope(container: container, ...)` — Riverpod
  caches providers per container, so reading `routerProvider` early and
  watching it later in the widget tree resolve to the identical
  `GoRouter`
- **New dependencies**: `firebase_core`, `firebase_messaging`,
  `flutter_local_notifications`
- **Android native setup**: `google-services.json` (from the Firebase
  console) placed at `android/app/`, plus the Google Services Gradle
  plugin applied in both `android/build.gradle.kts` (`apply false` +
  version) and `android/app/build.gradle.kts` — already done for this
  project's Firebase project (`lwkapply-push-notif`). `minSdk` must be
  ≥23 for `firebase-messaging`; this project inherits
  `flutter.minSdkVersion` rather than hardcoding it, so verify that
  resolves to ≥23 on whatever Flutter SDK version is in use
- **Firebase Admin credentials** (backend side, not this app) come from
  a _separate_ service-account JSON generated in the Firebase console
  (Project settings → Service accounts) — a different file from
  `google-services.json`, which only configures this Android client. See
  BACKEND_SUMMARY.md's push section for how the backend consumes it

### Timezone reporting

`lib/core/utils/timezone.dart`'s `getDeviceTimezone()` wraps
`flutter_timezone`'s `FlutterTimezone.getLocalTimezone()` (which returns
a `TimezoneInfo` object, not a bare `String`, as of the version pinned
in `pubspec.yaml` — pull the IANA name off `.identifier`; older package
versions returned a `String` directly, worth checking if this ever
fails to compile against a different pinned version). Returns `null` on
any failure rather than throwing — an unreported timezone should never
block login/register, mirroring the web equivalent
(`webapp/src/lib/timezone.ts`'s `getBrowserTimezone()`).

Wired into `AuthRepository.login()`/`register()`/`_refreshWith()` (the
last one covers both `tryRestoreSession()` on cold start and the
401-interceptor's silent refresh with one change), which pass it through
to `AuthApi`'s matching methods as an optional `timezone` parameter,
sent in the request body when present. Server-side validation
(`app/utils/timezone.py`) is the actual source of truth for "is this a
real IANA name" — this client-side helper just best-effort reports
whatever the device gives back.

## Not yet implemented

- Password reset UI, timezone override, and notification preferences on
  the new Settings screen (backend endpoints already exist per
  BACKEND_SUMMARY.md; Settings currently only hosts logout — see
  "Settings screen" above)
  screen has it, these two don't yet (see "Settings screen" above)
- In-app document download / offline document storage — downloads
  currently open the presigned URL externally via `url_launcher` only,
  no on-device copy kept
- Swipe-to-delete on the Applications list row (delete only lives on
  the Edit screen for now)
- iOS push notifications — deferred specifically on the paid Apple
  Developer Program membership requirement (the APNs key FCM relays
  through), not on usage data or any other reason; Android push is
  implemented (see "Push notifications" above)
- Offline support/sync — Phase 6d, deliberately deferred until there's
  real usage data from 6a/6b to design against
- Widget/unit tests beyond the one auth smoke test — Applications, the
  nested Contacts/Interviews/Documents panels, the three
  cross-application directory screens (v0.8.0), the
  push-notification/session-provider code, and the AI Tools feature all
  have none yet
- iOS build in CI (Android debug build only currently)
- `file_picker`'s Android/iOS native setup (manifest `queries` entries
  for content-type intents on Android API 30+, any iOS document-picker
  entitlements) hasn't been verified on-device yet — if document upload
  fails silently on a real device, check there first
- A currently-unverified assumption worth checking before building the
  profile/account-edit screen: whether `UserUpdate`'s `avatar_url` field
  implies an upload flow that needs a mobile equivalent of the webapp's
  document-upload pattern, or a simpler URL-only update

## Known gotchas hit during initial setup (worth knowing before repeating them)

- **`FormBuilderLocalizations`** lives in the `form_builder_validators`
  package, not `flutter_form_builder` — easy to import the wrong one.
  It must be registered in `MaterialApp.router`'s
  `localizationsDelegates` regardless of whether validators use custom
  `errorText` or the package's own localized messages
- **Package name**: the actual package name is `lwkapply_mobile` (see
  `pubspec.yaml`'s `name:` field) — any `package:lwkapply_mobile/...`
  import that doesn't match will fail silently confusing until checked
- **CI env files**: `.env.development`/`.env.production` are gitignored
  (see Environment config above) but declared as assets in
  `pubspec.yaml`, so a clean CI checkout has nothing for
  `flutter analyze`/build to point at unless a step explicitly creates
  them first (`mobile-ci.yml` does this via `cp .env.example
.env.development` etc. — mirror this if the CI workflow is ever rewritten)
- **`final` is a reserved Dart keyword**: the backend's Interview
  `"final"` type value can't be a Dart enum member name, hence
  `InterviewType.finalRound` in `features/interviews/domain/
interview.dart` — easy to trip over again if a future enum ever needs
  a member matching another Dart keyword (`class`, `void`, etc.)
- **`ColorScheme.surfaceContainerHighest`**: used by the Interviews/
  Documents result/type chips (`_ResultChip`/`_TypeChip`) — a newer
  Material 3 token. If the project's Flutter SDK predates it, swap for
  whatever `ApplicationStatus`'s own `backgroundColor(context)`/
  `foregroundColor(context)` extension already uses instead of a raw
  `ColorScheme` property, for consistency with the existing status-chip
  styling anyway
- **`flutter_timezone`'s `getLocalTimezone()` returns a `TimezoneInfo`
  object, not a bare `String`**, as of the version pinned in
  `pubspec.yaml` — pull the IANA name off `.identifier`
  (`core/utils/timezone.dart`). Older versions of this package returned
  a `String` directly; if this stops compiling after a version bump,
  check the package's actual return type first rather than assuming the
  field name is still right
- **Dart top-level type-inference cycles between Riverpod providers**:
  even when every provider in a chain has an explicit generic type
  argument on its _constructor_ (`Provider<Dio>(...)`, etc.), Dart's
  static analyzer can still report a circular-inference error if the
  _variable declarations themselves_ lack an explicit left-hand-side
  type and reference each other (even through a callback that only
  executes later, well after every provider has finished building -
  Dart's inference walk is purely textual/lexical, it doesn't know a
  reference is deferred). Fix: give the variable itself an explicit
  type (`final Provider<Dio> apiClientProvider = Provider<Dio>((ref) {
... })`), not just the constructor call. This is a _compile-time_
  analyzer issue, distinct from the genuine _runtime_
  `CircularDependencyError` case below - both can look similar at a
  glance but need different fixes
- **Genuine runtime `CircularDependencyError` between `apiClientProvider`
  and `authControllerProvider`**: see "`accessTokenProvider`/
  `currentUserProvider` — why the session lives outside `AuthController`"
  above for the full story. Short version: `authControllerProvider`
  transitively depends on `apiClientProvider` (via `pushServiceProvider`,
  for push-notification registration), so `apiClientProvider`'s
  interceptors must never read `authControllerProvider` back, even
  lazily inside a callback - Riverpod's dependency graph doesn't care
  when a read happens, only that it happened at all. The two leaf
  providers in `session_providers.dart` exist specifically to give
  `apiClientProvider` something to read/write that has zero
  dependencies of its own

## Development workflow

```bash
cd mobile
flutter pub get
cp .env.example .env.development
cp .env.example .env.production   # point at a real API URL later
flutter run --dart-define=ENV=development -d android
```

Checks CI runs, runnable locally first:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

## Testing notes

The one existing test (`test/app_smoke_test.dart`) overrides
`tokenStorageProvider` with an in-memory fake rather than exercising the
real `flutter_secure_storage` plugin — widget tests have no real
Keychain/Keystore behind the platform channel, so relying on however the
real plugin happens to fail without one would make the test's behavior
implementation-defined rather than deterministic. Follow this pattern
for any future test that touches `AuthController`'s startup bootstrap.

## Project structure

```
mobile/
  android/                       # generated by `flutter create`, native Android host project
  ios/                           # generated by `flutter create`, native iOS host project
  test/
    app_smoke_test.dart
  lib/
    main.dart                     # entry point: loads env, initializes Firebase +
                                   # background message handler, builds an explicit
                                   # ProviderContainer, wraps app in UncontrolledProviderScope
    app/
      app.dart                    # MaterialApp.router root widget, localization delegates
      router.dart                 # go_router config: redirects, 2-tab shell
                                   # (Applications + Home) + top-level pushed
                                   # routes (forms, Interviews/Contacts/
                                   # Documents/Analytics/AI Tools/Settings
                                   # directories)
      app_shell.dart               # bottom NavigationBar - 2 tabs now, see
                                    # its own doc comment for the full
                                    # 4-tabs-to-2 reasoning
    core/
      config/env_config.dart
      network/api_client.dart      # shared Dio instance (token interceptors -
                                    # reads/writes session_providers.dart's leaf
                                    # providers directly, never authControllerProvider)
      theme/app_theme.dart
      utils/timezone.dart          # getDeviceTimezone() via flutter_timezone
    shared/
      widgets/coming_soon_screen.dart  # no longer referenced by router.dart
                                        # (all 4 bottom-nav tabs are real
                                        # screens now) — left in place for
                                        # any future placeholder need
    features/
      auth/
        data/                       # token_storage.dart, auth_api.dart, auth_repository.dart
        domain/                      # user.dart, auth_state.dart
        presentation/                # auth_controller.dart (also registers/deregisters
                                      # push tokens - see Push notifications above),
                                      # session_providers.dart (accessTokenProvider/
                                      # currentUserProvider - see that section above),
                                      # login/register_screen.dart
      notifications/
        data/                        # device_tokens_api.dart (POST/DELETE
                                      # /users/me/device-tokens), push_service.dart
                                      # (PushService - registration, tap-to-deep-link),
                                      # local_notifications.dart (foreground display)
      home/
        presentation/                 # home_screen.dart - card-grid launcher,
                                       # the "Home" tab (Interviews/Contacts/
                                       # Documents/Analytics/AI Tools cards)
      settings/
        presentation/                 # settings_screen.dart (currently just
                                       # logout), settings_icon_button.dart
                                       # (shared AppBar action every top-level
                                       # screen should use)
      analytics/
        data/                        # analytics_api.dart (GET /analytics/
                                       # summary, /funnel, /activity, /interviews)
        domain/                      # analytics.dart - mirrors backend/app/
                                       # schemas/analytics.py response shapes
        presentation/                 # analytics_state.dart/_controller.dart
                                       # (one controller, all four endpoints,
                                       # independent fetch/error per section),
                                       # analytics_screen.dart (fl_chart)
      ai/
        data/                        # resume_analyses_api.dart, ats_scores_api.dart,
                                       # polling_timer.dart (Timer.periodic wrapper,
                                       # first usage in mobile/lib/)
        domain/                      # ai_job_status.dart, parsed_resume.dart,
                                       # ats_score_result.dart, resume_analysis.dart,
                                       # ats_score.dart - mirror backend/app/schemas/ai.py
        presentation/                 # ai_tools_screen.dart (TabBar host, FAB),
                                       # resume_analyses_tab.dart/ats_scores_tab.dart,
                                       # new_analysis_sheet.dart/new_ats_score_sheet.dart
                                       # (create bottom sheets), resume_document_picker.dart/
                                       # application_picker.dart (debounced remote search,
                                       # call the stateless API classes directly - no
                                       # isolated search method needed, unlike web),
                                       # resume_analysis_detail_controller.dart/
                                       # ats_score_detail_controller.dart (.family, fetch-
                                       # and-poll only - create() lives in the screens),
                                       # resume_analysis_detail_screen.dart/
                                       # ats_score_detail_screen.dart, parsed_resume_card.dart/
                                       # ats_score_result_card.dart, ai_job_status_style.dart
      applications/
        data/applications_api.dart
        domain/                      # application.dart, application_draft.dart
        presentation/                 # list state/controller/screen, form screen/result,
                                       # status style, formatting (application_formatting.dart
                                       # now uses intl's DateFormat — see above)
      contacts/
        data/                        # contacts_api.dart,
                                       # contact_directory_api.dart (GET /contacts)
        domain/                      # contact.dart, contact_draft.dart,
                                       # contact_with_application.dart (+ ApplicationSummary)
        presentation/                 # contacts_panel.dart (nested tab content),
                                       # contact_form_sheet.dart (add/edit),
                                       # contact_directory_state/controller.dart,
                                       # contact_directory_screen.dart (bottom-nav tab)
      interviews/
        data/                        # interviews_api.dart,
                                       # interview_directory_api.dart (GET /interviews)
        domain/                      # interview.dart (InterviewType/InterviewResult
                                       # enums), interview_draft.dart,
                                       # interview_with_application.dart (+ ApplicationSummary)
        presentation/                 # interviews_list_state/controller.dart
                                       # (infinite scroll, .family-scoped),
                                       # interviews_panel.dart (nested tab content),
                                       # interview_form_sheet.dart (add/edit),
                                       # interview_formatting.dart (intl DateFormat),
                                       # interview_directory_state/controller.dart,
                                       # interview_directory_screen.dart (bottom-nav tab)
      documents/
        data/                        # documents_api.dart (upload() sends multipart
                                       # FormData, not JSON), document_directory_api.dart
                                       # (GET /documents, search + file_type)
        domain/                      # document.dart (DocumentType enum,
                                       # DocumentDownloadResponse), no *_draft.dart —
                                       # upload/update take params directly;
                                       # document_with_application.dart (+ ApplicationSummary)
        presentation/                 # documents_list_state/controller.dart
                                       # (infinite scroll, local prepend/replaceById/
                                       # removeById instead of refresh()),
                                       # documents_panel.dart (nested tab content),
                                       # document_upload_sheet.dart, document_edit_sheet.dart,
                                       # document_directory_state/controller.dart,
                                       # document_directory_screen.dart (bottom-nav tab)
  pubspec.yaml
  analysis_options.yaml
  .env.example                    # committed template; .env.development/.env.production gitignored
  .github/workflows/mobile-ci.yml
```

Every future feature should get the same `data`/`domain`/`presentation`
split as `auth/`, `applications/`, `contacts/`, `interviews/`, and
`documents/` — and, if it needs both nested per-application CRUD and a
cross-application directory, the same `*_api.dart`/`*_directory_api.dart`
and `*_panel.dart`/`*_directory_screen.dart` pairing Contacts/Interviews/
Documents now demonstrate.
