# LwkApply - Job Tracker — Mobile Client

Flutter + Riverpod + go_router + Dio, implementing Phase 6 (Mobile
Application): project scaffold, auth, and the Applications feature
(list/create/edit/delete, including an optional `applicationName`
label). Contacts, Interviews, and Documents are implemented twice over,
same as on web: nested inside `ApplicationFormScreen`'s own 4-tab layout
(Details / Contacts / Interviews / Documents) for per-application
CRUD — see "Contacts, Interviews, and Documents" below — and as
cross-application directory screens (mirroring `ContactDirectoryView.vue`/
`InterviewDirectoryView.vue`/`DocumentDirectoryView.vue` on web) — see
"Cross-application directory screens" below. Interviews' stays
read-only; Contacts'/Documents' are now the primary places to manage the
whole contact directory/document library, since each became a
top-level, user-owned resource no longer nested under a single
application (see the Contacts/Documents bullets in both sections). The
app also registers for and displays push
notifications for interview reminders (Android only — see "Push
notifications" below) and reports the device's timezone to the backend
(see "Timezone reporting" below).

The bottom nav shrank from 4 tabs to 2 (Applications + a card-grid
"Home" hub) to make room for Analytics and AI Tools without crowding
the tab bar further — see "Navigation shell" below for the full
reasoning. Settings has grown from a logout-only screen into the full
account-settings screen (profile/avatar, password, timezone,
notification preferences, account deletion), and a new in-app
notification feed (bell icon + Unread/Read list) exists alongside the
push notifications already implemented — see "Settings screen" and
"Notifications feed" below. Analytics is implemented — see "Analytics
feature" below.

AI Tools (Resume Parser + ATS Score) is implemented — the backend and
web UI already existed; this is the mobile client for both, including a
later pass that caught it up to a `Document`-decoupling + AI-Tools-
polish rework that had already landed on the backend/web (`analysis_name`,
`scored_at`, server-side name joins, attach/detach documents, a
search-based resume-analysis picker, and cross-links between the score
and analysis detail screens). See "AI Tools feature" below.

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
start.

- **Password reset** — `ForgotPasswordScreen` (email ->
  `POST /auth/password-reset/request`) and `ResetPasswordScreen` (token
  + new password -> `POST /auth/password-reset/confirm`), guest routes
  reached from `LoginScreen`'s "Forgot password?" link. `token` normally
  arrives via the emailed reset link itself: `data/deep_link_service.dart`
  (the `app_links` package) listens for the OS handing this app the
  `https://lwkapply.vercel.app/reset-password?token=...` URL — see the
  matching intent-filter on `MainActivity` in
  `android/app/src/main/AndroidManifest.xml` — and pushes
  `/reset-password?token=...`, same "capture a `GoRouter` reference"
  shape as `PushService`'s FCM tap-to-deep-link handling. A real,
  verified Android App Link (`android:autoVerify="true"` on the
  intent-filter, checked against `webapp/public/.well-known/
  assetlinks.json`) — this turned out to be required, not optional: an
  unverified intent-filter is invisible to Android 12+'s link
  resolution entirely (no disambiguation dialog, the link just always
  opens in the browser), and Gmail's own in-app link handling (Chrome
  Custom Tabs) only ever hands off to a verified App Link regardless of
  Android version. `assetlinks.json`'s fingerprint currently points at
  this project's debug keystore (see the intent-filter's own comment in
  `AndroidManifest.xml` for why, and how to regenerate it) — there's no
  release-signing/Play Store setup yet, only a sideloaded APK. There's
  no dedicated screen for completing the API contract from a *typed-in*
  token; if the link is ever opened somewhere this app isn't installed
  to intercept it, the same URL still works as a normal page in the web
  app.

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

`lib/features/settings/presentation/settings_screen.dart` (`/settings`
route) — started as a logout-only menu; now the full account-settings
entry point, each section a pushed sub-screen rather than one long
scrolling page (mobile's usual shape for anything more than a couple of
fields — see ApplicationFormScreen's per-tab screens, or Interviews/
Contacts/Documents each being their own screen). Every top-level screen
that needs a way into Settings uses the same shared `SettingsIconButton`
widget (`lib/features/settings/presentation/settings_icon_button.dart`)
in its `AppBar.actions`, rather than each screen duplicating an inline
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

**Sub-screens** (all under `lib/features/settings/presentation/`):

- **`ProfileScreen`** (`/settings/profile`) — avatar upload/remove
  (`file_picker`, restricted to `png`/`jpg`/`jpeg`/`webp` — matches the
  backend's `AVATAR_ALLOWED_CONTENT_TYPES`), first/last name
  (`flutter_form_builder`), and a timezone override: an explicit
  "Auto-detect timezone" `SwitchListTile` (mapped onto
  `User.timezoneIsManual` — off means the app keeps overwriting
  `User.timezone` from the device on every login/refresh, on means it's
  locked to what's picked below) plus a "Choose your own timezone" row
  that opens `TimezonePickerSheet` — a searchable bottom sheet over
  `core/utils/timezone.dart`'s `timezoneOptions()` (every IANA zone
  `package:timezone`'s bundled tzdata knows about, each labeled with its
  live UTC offset, e.g. `"Asia/Ho Chi Minh (UTC+7)"` — mirrors
  `webapp/src/lib/timezone.ts`). `package:timezone` was already a
  transitive dependency via `flutter_local_notifications`; this pass
  promotes it to direct in `pubspec.yaml`, since Dart's core `DateTime`
  has no named-timezone support at all without it. All three fields
  submit through new `AuthController` methods
  (`updateProfile`/`uploadAvatar`/`removeAvatar`) that update
  `currentUserProvider` in place, same reasoning `stores/auth.ts`
  mutates `this.user` directly on web. `timezone` is only included in
  the `PATCH /users/me` body when it actually changed (own dirty-check
  against the saved value, kept as plain widget state rather than a
  `FormBuilder` field) — the backend flips `timezone_is_manual` purely
  from that key's *presence*, so resaving the name fields alone must
  never silently re-lock an auto-detected timezone.
- **`ResetPasswordRequestScreen`** (`/settings/password`) and
  **`NotificationPreferencesScreen`**
  (`/settings/notification-preferences`) — call `userApiProvider`/
  `userSettingsApiProvider` directly rather than through
  `AuthController`; neither changes anything `currentUserProvider`
  holds, so there's nothing else that needs to observe them completing.
  `ResetPasswordRequestScreen` is a single button
  (`POST /users/me/password-reset/request`) rather than a current+new
  password form — see "Password reset" below.
  `NotificationPreferencesScreen` mirrors `NotificationSettingsCard.vue`
  (master + per-channel email/push toggles, dimmed *and* disabled when
  the master switch is off; a switch to opt into a custom reminder lead
  time vs. sending an explicit `null` to fall back to the server's
  global default) — plain widget state, not `flutter_form_builder`,
  same reasoning `DocumentUploadSheet`'s own file-type dropdown gives:
  no validation happening here `form_builder` would add value to.
- **`DeleteAccountDialog`** — an `AlertDialog` + `FormBuilder`
  re-confirming the password before `DELETE /users/me`, called via
  `AuthController.deleteAccount` (deregisters the push device token,
  calls the API, then clears local session state the same way
  `logout()` does — except through a new `AuthRepository
  .clearLocalSession()` that skips `POST /auth/logout`'s server-side
  refresh-token revoke, since the account, and therefore that token, no
  longer exists once the delete succeeds). The router's own
  auth-state `redirect` (see `app/router.dart`) sends the user to
  `/login` afterward on its own, same as a plain logout — the dialog
  itself doesn't navigate anywhere.

### Notifications feed

New ground on mobile — no in-app notification list/bell UI existed
before this pass (push notifications for interview reminders already
did, see "Push notifications" below; this is the separate in-app feed
of notification *events*, mirroring the backend's `Notification`
model/`/notifications` endpoints and web's `NotificationBell.vue`).

- **`NotificationBellButton`**
  (`lib/features/notifications/presentation/notification_bell_button.dart`)
  — same `AppBar.actions` placement convention as `SettingsIconButton`,
  a `Badge`-wrapped bell icon showing `NotificationsController`'s
  `unreadCount`, pushing `/notifications` on tap.
- **`NotificationsScreen`** — a full pushed screen, not a popover
  (mobile has no hover/click popover equivalent) — with a full-width
  Unread/Read `SegmentedButton` and an infinite-scroll `ListView`
  (`ScrollController` threshold, same pattern
  `ApplicationsListScreen`'s `_onScroll` uses), "Mark all read" on the
  Unread tab. Tapping an unread item marks it read and, if it carries an
  `application_id`, **pushes** (not replaces) into that application's
  edit screen — backing out returns to the feed rather than to whatever
  screen originally opened it.
- **`NotificationsController`** (`StateNotifier`, mirrors
  `stores/notifications.ts`) — deliberately **not** `.autoDispose` and
  does **not** fetch anything on construction, unlike
  `ApplicationsListController`: the unread-count badge has to keep
  polling on every authenticated screen, not just while
  `NotificationsScreen` happens to be open. `startPolling()`/
  `stopPolling()` are called from `AuthController` on
  login/register/silent-restore and logout respectively — the exact
  same lifecycle `PushService.registerCurrentDevice()`/
  `deregisterCurrentDevice()` already follow. Poll interval (30s)
  matches `webapp/src/stores/notifications.ts`'s own constant, for
  consistency across clients.
- Backend needed a small change to support the Unread/Read tabs:
  `GET /notifications` used to take a plain `unread_only: bool`, with no
  way to ask for read-only. It's now `status: "all"|"unread"|"read"` —
  additive, and this is the first client to depend on the new shape
  (see `backend/BACKEND_SUMMARY.md`'s "In-app notification feed").

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

This feature (and Documents, below) went through a second, later pass
catching mobile up to a `Document`-decoupling + AI-Tools-polish rework
that had already landed on the backend/web (see CHANGELOG.md v0.11.0's
"AI Tools follow-up" entry) — the bullets below describe the *current*
shape directly, not the first-pass-then-patched history.

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
- **No more client-side label joins.** `ResumeAnalysis`/`AtsScore` now
  carry `analysisName`/`documentFileName` (and `AtsScore.analysisName`)
  straight off the wire — joined server-side (see
  BACKEND_SUMMARY.md's "`analysis_name`, `scored_at`, and server-side
  `document_file_name` joins"). `resume_analyses_tab.dart`/
  `ats_scores_tab.dart` just read the fields directly; the
  fetch-every-document/application-and-look-up-by-id join both tabs
  used to build client-side is gone.
- **Remote-search pickers** — `resume_document_picker.dart`,
  `application_picker.dart`, and `resume_analysis_picker.dart` (added
  once `GET /ai/resume-analyses` gained `status`/`search` params,
  replacing `new_ats_score_sheet.dart`'s old full-preload-then-filter
  bottom sheet). All three follow the same plain debounced (350ms)
  `TextField` + results-list-below shape — not Flutter's built-in
  `Autocomplete<T>` (its async `optionsBuilder` integration was fiddlier
  to get predictably right than a small purpose-built widget) — and call
  their target API class directly (`DocumentDirectoryApi`/
  `ApplicationsApi`/`ResumeAnalysesApi.searchCompletedForPicker`) rather
  than through a list controller, so a picker search can never disturb
  the real Documents/Applications/Resume-Analyses list screens' own
  state the way reusing a Riverpod list controller's paginated fetch
  would. `documents/presentation/document_attach_sheet.dart` (see
  Documents below) is a fourth picker in the same shape, just scoped to
  documents not yet attached to the current application.
  - **All four also search on focus**, not just on keystroke — each
    owns a `FocusNode` and fires the same debounced search the instant
    the field gains focus (empty query = first page of results), so
    tapping into an empty search field shows something immediately
    instead of an empty list until the user starts typing.
- **`new_ats_score_sheet.dart`**: a `SegmentedButton` toggles between
  "Tracked application" (`ApplicationPicker`) and "Paste a job
  description" (a plain multiline `TextField`, 50–20000 char hint,
  server is the real validator) — mirrors web's automatic-job_url-first/
  paste-as-fallback contract, just surfaced as an upfront choice instead
  of a retry path. Also accepts an optional `initialAnalysis` (used by
  `ResumeAnalysisDetailScreen`'s "Score against a job" button), which
  skips the resume-picker step entirely.
- **`analysis_name_edit_sheet.dart`**: single-field rename bottom sheet
  for `ResumeAnalysis.analysisName` (`PATCH /ai/resume-analyses/{id}`),
  same shape as `document_edit_sheet.dart`. Wired up only on
  `resume_analyses_tab.dart`'s row (a pencil `IconButton`) — deliberately
  **not** duplicated onto `resume_analysis_detail_screen.dart`, which
  only ever displays the name read-only, mirroring web's own
  one-edit-surface decision (see WEBAPP_SUMMARY.md).
- **"Latest" framing via `isLatest`** — `ResumeAnalysisDetailScreen`
  takes an optional `isLatest` param (`?isLatest=true` query param on
  `/resume-analyses/:id`), set only by `viewResumeAnalysisAction` below.
  When true: shows a "Latest" chip plus Analyzed/Scored timestamps, and
  looks up/offers the existing `AtsScore` for that analysis
  automatically instead of always presenting a blank "Score against a
  job" button. `AiToolsScreen`'s plain history-list tab and "New
  Analysis" create flow leave it `false` — a specific row tap there
  isn't necessarily "the latest" in any meaningful sense.
  `AtsScoreDetailScreen` has the mirror-image flag, `showAnalysisLink`
  (see below), for the same "is this a from-scratch entry point or a
  drill-down from somewhere that already had the context" distinction.
- **`view_resume_analysis_action.dart`**: the shared "find the latest
  analysis for this document, or confirm-and-create one, then navigate
  with `isLatest: true`" flow, factored out so `DocumentsPanel`'s
  application-scoped "View Analysis" row action and
  `DocumentDirectoryScreen`'s library-scoped "View AI analysis" row
  action (see Documents below) share one implementation instead of
  drifting apart — `AtsScore` has no application link at all any more
  (see AtsScore's own doc comment), so the two entry points behave
  identically here; there's nothing left that would make them diverge.
  Fetches-or-creates only: `create()` hits a rate-limited AI call, so it
  never fires just because a row action was tapped, only after an
  explicit "Analyze now" confirmation (a bug caught and fixed in an
  earlier pass — see CHANGELOG.md v0.11.0 — where the original version
  called `create()` automatically whenever no analysis existed yet).
- **Score ↔ analysis cross-links, each with a real touch target.**
  `resume_analysis_detail_screen.dart` has a "View score" `Card`/
  `ListTile` row (leading score-circle or icon, chevron trailing) when a
  score exists; `ats_score_detail_screen.dart` has the mirror-image
  "View resume analysis" row (leading `Icons.description_outlined`,
  analysis name as title, document file name as subtitle, chevron
  trailing) — same `Card`/`ListTile` shape both directions, not a small
  inline text link. The resume-analysis→score row always shows; the
  score→analysis row is gated by `showAnalysisLink`
  (`AtsScoreDetailScreen`'s own constructor param, threaded through as
  `?showAnalysisLink=true`) — **true** only when reached directly from
  `AtsScoresTab`'s card tap or `AiToolsScreen`'s "New Score" flow (the
  user hasn't necessarily seen the underlying analysis yet there),
  **false** when reached via `resume_analysis_detail_screen.dart`'s own
  "Score against a job"/"View score" (which is also how
  `DocumentsPanel`'s/`DocumentDirectoryScreen`'s "View AI analysis"
  action lands here) — a link back to a screen the user just came from
  would be redundant. `AtsScoresTab`'s own card shows the analysis name
  as plain, non-interactive text — it isn't its own tap target; tapping
  anywhere on the card already opens `AtsScoreDetailScreen`, where the
  properly-sized row lives instead.
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

`Application`/`ApplicationDraft` also carry `applicationName` — an
optional, user-chosen label distinguishing applications that share the
same company/position (e.g. a re-apply after rejection), same field/
reasoning as web's (see CHANGELOG.md v0.11.0). Editable via a
`FormBuilderTextField` on `application_form_screen.dart`'s Details tab,
shown in `applications_list_screen.dart`'s cards, and in
`application_picker.dart`'s results (see AI Tools above) — plus
Interviews' own directory-screen `ApplicationSummary` (below; Contacts'
equivalent existed at the time this field was added but has since been
deleted along with the rest of `contact_with_application.dart`), a
deliberately separate, non-shared class that needed the field added
individually.

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

- **Contacts** — `contacts_panel.dart` is **attach/detach, not
  create/delete**: a contact is a top-level, user-owned resource now
  (`domain/contact.dart` has no `applicationId` at all any more — see
  BACKEND_SUMMARY.md's "A note on Contact / ApplicationContact"), so
  this panel no longer creates a contact scoped to this application
  directly. Two ways a contact ends up attached: **"Attach existing"**
  (`contact_attach_sheet.dart`, a search picker over the whole
  directory — see AI Tools above for the shared picker shape) or **"Add
  new"** (`ContactDirectoryApi.create` creates in the directory, then
  `ApplicationContactsApi.attach` links it — two sequential calls where
  there used to be one; either exception propagates rather than a
  created-but-not-attached contact disappearing silently). "Remove from
  this application" only detaches the link
  (`ApplicationContactsApi.detach`) — the contact itself, and any of
  its other applications' attachments, are untouched; the confirm
  dialog says so explicitly. Add/edit still goes through the shared
  `ContactFormSheet` (unchanged — its `onSubmit` callback was already
  decoupled from which API it calls, so the same sheet now serves both
  this panel and `ContactDirectoryScreen`, below). Email and LinkedIn
  URL remain tappable via `url_launcher` (`mailto:`/`https:`) once a
  value is present.
  - `contacts_list_controller.dart`/`contacts_list_state.dart` (new)
    replace the plain local `State` this panel used to keep back when
    the nested backend list was deliberately unpaginated — it's
    paginated now (a contact can be reused across applications, same
    reason `Document` needed this shape), so the panel needs the same
    infinite-scroll bookkeeping every other paginated panel already
    has. Patches state locally for every mutation
    (`prepend`/`replaceById`/`removeById`), same shape
    `DocumentsListController` established.
  - **`ContactDirectoryApi`** (`contacts/data/`) owns the full
    `/contacts` CRUD now — `create`/`get`/`update`/`delete`, not just
    the `list` it had before this rework. `ApplicationContactsApi`
    (`contacts/data/application_contacts_api.dart`, new) owns
    `list`/`attach`/`detach` against `/applications/{id}/contacts` —
    the old `contacts_api.dart`'s nested create/update/delete contract
    no longer exists on the backend at all (deleted along with
    `contact_with_application.dart`, the domain class that used to pair
    a `Contact` with a single owning `ApplicationSummary` — there's no
    longer a single one to embed).
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
- **Documents** — `documents_panel.dart` is **attach/detach, not
  create/delete**: a document is a top-level, user-owned resource now
  (`domain/document.dart` has no `applicationId` at all any more — see
  CHANGELOG.md v0.11.0's Document-decoupling entry), so this panel no
  longer uploads a file scoped to this application directly. Two ways a
  document ends up attached: **"Attach existing"**
  (`document_attach_sheet.dart`, a search picker over the whole library
  — see AI Tools above for the shared picker shape) or **"Upload new"**
  (`DocumentDirectoryApi.create` uploads to the library, then
  `ApplicationDocumentsApi.attach` links it — two sequential calls where
  there used to be one; either exception propagates rather than a
  partial upload-but-not-attached failure disappearing silently).
  "Remove from this application" only detaches the link
  (`ApplicationDocumentsApi.detach`) — the document itself, and any of
  its other applications' attachments, are untouched; the confirm
  dialog says so explicitly. `documents_list_controller.dart` still
  patches state locally for every mutation (`prepend`/`replaceById`/
  `removeById`) rather than refetching, same reasoning as before
  (`created_at DESC` ordering, and neither an attach nor a `file_type`
  edit can change an item's position).
  - **`DocumentDirectoryApi`** (`documents/data/`) owns the full
    `/documents` CRUD now — `create`/`get`/`update`/`delete`/`download`,
    not just the `list` it had before this rework. Upload
    (`DocumentUploadSheet`, still the one Create call anywhere in this
    app sending `multipart/form-data` — `dio`'s `FormData` +
    `MultipartFile`, matching the backend's `file: UploadFile =
    File(...)` + `file_type: DocumentType = Form(...)` contract, file
    selection via `file_picker`) now targets this API instead of a
    per-application nested route. `ApplicationDocumentsApi`
    (`documents/data/application_documents_api.dart`, new) owns
    `list`/`attach`/`detach` against `/applications/{id}/documents` —
    the old `documents_api.dart`'s multipart-upload-to-an-application
    contract no longer exists on the backend at all (deleted along with
    `document_with_application.dart`, the domain class that used to pair
    a `Document` with a single owning `ApplicationSummary` — there's no
    longer a single one to embed).
  - **`_DocumentCard` layout** (both `documents_panel.dart`'s and
    `document_directory_screen.dart`'s): file name gets a full-width
    line (up to 2 lines) followed by the type chip and "Uploaded
    {date, time}" each on their own line — not a `ListTile`
    title/subtitle squeezed against a trailing `Row` of 3-4
    `IconButton`s, which left too little width for either the name or
    the timestamp to actually show. The row actions (Download, View
    Analysis, Edit type, Remove/Delete) collapse into a single
    `PopupMenuButton` overflow menu instead.
  - Download (`DocumentDirectoryApi.download`) fetches a fresh
    short-lived presigned R2 URL per tap and hands it to `url_launcher`
    to open externally (browser/PDF viewer) — no in-app
    download-to-storage yet, see "Not yet implemented" below.

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
per-application panels above. **Interviews is the one still read-only**,
for the reason its web view is: uploads/edits/deletes still only happen
from within the owning application, reached via
`context.push('/applications/{id}/edit')` on any row (the existing
`application-edit` route). Documents and now Contacts are the
exceptions — since each became a top-level, user-owned resource (see
their bullets above), `document_directory_screen.dart` and
`contact_directory_screen.dart` are each now the primary place to manage
the *whole* library/directory (Documents also gets upload/download/view
AI analysis, Contacts add/edit/delete), matching
`DocumentDirectoryView.vue`/`ContactDirectoryView.vue`'s own rework;
neither screen's rows point back to "the" owning application any more,
since both resources can belong to zero, one, or several now.

The three no longer follow one consistent shape — Interviews still fits
the original read-only pattern; Documents diverged first, and Contacts
has now diverged the same way:

- **`domain/*_with_application.dart`** (Interviews only now —
  Contacts'/Documents' equivalents, `contact_with_application.dart`/
  `document_with_application.dart`, were both deleted once their
  resource stopped having a single owning application to embed) —
  composes the existing per-application model (`Interview`) with a new
  `ApplicationSummary` (id/company/position/`applicationName`/status),
  rather than duplicating its fields. Mirrors the backend's own
  precedent of each directory schema owning its copy (see
  BACKEND_SUMMARY.md).
- **`data/*_directory_api.dart`** — Interviews' calls the flat
  `GET /interviews` endpoint and reuses the nested feature's existing
  exception type (`InterviewsException`). Contacts'/Documents' are no
  longer just this shape — see their bullets above for the full CRUD
  each absorbed.
- **`presentation/*_directory_state.dart` + `*_directory_controller.dart`**
  — the same fetch/append infinite-scroll split
  `InterviewsListController` established, but as a plain (non-`.family`)
  `StateNotifierProvider`, since each is one global, cross-application
  list rather than something scoped per application. Interviews' stays
  read-only (no mutation methods). Contacts'/Documents'
  (`contact_directory_controller.dart`/`document_directory_controller.dart`)
  both gained the same `prepend`/`replaceById`/`removeById` shape
  `DocumentsListController` established, once each screen itself
  stopped being read-only.
- **`presentation/*_directory_screen.dart`** — built from
  `ApplicationsListScreen`'s scroll/empty-state/footer conventions, with
  a filter UI that differs per resource since the backend's own filter
  support differs:
  - **Contacts** — debounced text search only (`name` — no more company
    match, since there's no single parent application to search on).
    **No longer read-only**: an "Add contact" FAB (reuses
    `ContactFormSheet`, same as `ContactsPanel`), and each card's
    edit/delete `IconButton`s (two actions is few enough to stay plain
    buttons rather than collapsing into an overflow menu). Delete here
    is a real, permanent, cross-application delete (confirm dialog says
    so explicitly) — distinct from `ContactsPanel`'s detach-only
    "Remove from this application". Tappable email/LinkedIn per row via
    `url_launcher`, same as `ContactsPanel`. No row `onTap` to an owning
    application any more — there isn't necessarily one.
  - **Interviews** — a `result` filter via a bottom sheet (lifted from
    `ApplicationsListScreen`'s status-filter sheet shape); no text
    search, since `Interview` has no name-like field. Cards reuse
    `interview_formatting.dart`'s `formatDateTime` and duplicate
    `InterviewsPanel`'s private `_ResultChip` color logic. Still
    read-only — rows do navigate to the owning application, via
    `context.push('/applications/{id}/edit')`.
  - **Documents** — combines a debounced search (`file_name` only now —
    no more company match, since there's no single parent application
    to search on) with a `file_type` filter sheet, clearing
    independently, plus a combined "Clear filters" action. **No longer
    read-only**: an "Upload document" FAB (reuses
    `document_upload_sheet.dart` unmodified — its `onSubmit` already
    took a bare `Document`, no `applicationId`), and each row's overflow
    menu offers Download/View AI analysis (resume documents only, via
    `view_resume_analysis_action.dart` — see AI Tools above)/Edit type/
    Delete. Delete here is a real, permanent, cross-application delete
    (confirm dialog says so explicitly) — distinct from
    `DocumentsPanel`'s detach-only "Remove from this application". No
    row `onTap` to an owning application any more — there isn't
    necessarily one. Cards reuse `document_formatting.dart`'s
    `formatDateTime` and the same `_DocumentCard`/`_TypeChip` shape
    `documents_panel.dart` uses (each still a private duplicate, not a
    shared widget).

  Every screen also renders an `_StatusChip` for the embedded
  application status (Interviews only now — Contacts'/Documents' both
  have none any more, for the same reason each lost its `*_with_
  application.dart` above), styled via `ApplicationStatus`'s own
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
                                       # ats_score_result.dart, resume_analysis.dart
                                       # (analysisName/documentFileName/completedAt),
                                       # ats_score.dart (scoredAt/documentFileName/
                                       # analysisName) - mirror backend/app/schemas/ai.py
        presentation/                 # ai_tools_screen.dart (TabBar host, FAB),
                                       # resume_analyses_tab.dart/ats_scores_tab.dart
                                       # (no more client-side label joins),
                                       # ai_formatting.dart (formatDateTime),
                                       # new_analysis_sheet.dart/new_ats_score_sheet.dart
                                       # (create bottom sheets), resume_document_picker.dart/
                                       # application_picker.dart/resume_analysis_picker.dart
                                       # (debounced + search-on-focus remote pickers,
                                       # call the stateless API classes directly - no
                                       # isolated search method needed, unlike web),
                                       # analysis_name_edit_sheet.dart (rename, wired only
                                       # on resume_analyses_tab.dart's row),
                                       # view_resume_analysis_action.dart (shared find-or-
                                       # create-then-navigate-isLatest flow, used by both
                                       # DocumentsPanel and DocumentDirectoryScreen),
                                       # resume_analysis_detail_controller.dart/
                                       # ats_score_detail_controller.dart (.family, fetch-
                                       # and-poll only - create() lives in the screens),
                                       # resume_analysis_detail_screen.dart (isLatest param)/
                                       # ats_score_detail_screen.dart (showAnalysisLink param),
                                       # parsed_resume_card.dart/ats_score_result_card.dart,
                                       # ai_job_status_style.dart
      applications/
        data/applications_api.dart
        domain/                      # application.dart, application_draft.dart
        presentation/                 # list state/controller/screen, form screen/result,
                                       # status style, formatting (application_formatting.dart
                                       # now uses intl's DateFormat — see above)
      contacts/
        data/                        # contact_directory_api.dart (full /contacts CRUD -
                                       # create/get/update/delete/list), application_contacts_api.dart
                                       # (list/attach/detach against /applications/{id}/contacts,
                                       # JSON {contact_id} body - replaces the old, now-deleted
                                       # contacts_api.dart's nested create/update/delete contract)
        domain/                      # contact.dart (no applicationId any more - a contact has
                                       # zero/one/many owning applications), contact_draft.dart.
                                       # contact_with_application.dart deleted (no single
                                       # owning application left to embed)
        presentation/                 # contacts_list_state/controller.dart
                                       # (infinite scroll, .family-scoped - replaces the old
                                       # plain local State once the nested endpoint paginated),
                                       # contacts_panel.dart (nested tab content, attach/detach),
                                       # contact_attach_sheet.dart (search picker),
                                       # contact_form_sheet.dart (add/edit),
                                       # contact_directory_state/controller.dart,
                                       # contact_directory_screen.dart (bottom-nav tab,
                                       # full CRUD now, not read-only)
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
        data/                        # document_directory_api.dart (full /documents CRUD -
                                       # create/get/update/delete/download/list, upload sends
                                       # multipart FormData not JSON), application_documents_api.dart
                                       # (list/attach/detach against /applications/{id}/documents,
                                       # JSON {document_id} body - replaces the old, now-deleted
                                       # documents_api.dart's broken multipart-upload contract)
        domain/                      # document.dart (DocumentType enum,
                                       # DocumentDownloadResponse, no applicationId any more -
                                       # a document has zero/one/many owning applications),
                                       # no *_draft.dart — upload/update take params directly.
                                       # document_with_application.dart deleted (no single
                                       # owning application left to embed)
        presentation/                 # documents_list_state/controller.dart
                                       # (infinite scroll, local prepend/replaceById/
                                       # removeById instead of refresh()),
                                       # documents_panel.dart (attach/detach, not
                                       # create/delete - see Documents section above),
                                       # document_attach_sheet.dart (search picker over
                                       # the library, filters already-attached ids),
                                       # document_formatting.dart (formatDateTime),
                                       # document_upload_sheet.dart, document_edit_sheet.dart,
                                       # document_directory_state/controller.dart (gained
                                       # prepend/replaceById/removeById - no longer read-only),
                                       # document_directory_screen.dart (bottom-nav tab -
                                       # now the primary library management screen: upload
                                       # FAB, per-row overflow menu)
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
