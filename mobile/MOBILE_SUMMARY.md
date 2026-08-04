# LwkApply - Job Tracker — Mobile Client

Flutter + Riverpod + go_router + Dio, implementing Phase 6 (Mobile
Application): project scaffold, auth, a 4-tab bottom nav shell, and the
Applications feature (list/create/edit/delete). Contacts, Interviews,
and Documents are now implemented too, but nested inside
`ApplicationFormScreen`'s own 4-tab layout (Details / Contacts /
Interviews / Documents) rather than as their own top-level screens —
see "Contacts, Interviews, and Documents" below. The bottom-nav
Interviews/Contacts/Documents tabs (the future cross-application
directory screens, mirroring `ContactDirectoryView.vue`/etc. on web)
are still `ComingSoonScreen` placeholders; that's separate, not-yet-
started work.

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
.indexedStack`: bottom `NavigationBar`, 4 tabs (Applications default,
Interviews, Contacts, Documents). Chosen over the webapp's side menu —
comments in `app_shell.dart` cover the reasoning (discoverability,
`IndexedStack` keeping each tab's scroll/nav state alive). Interviews/
Contacts/Documents render `ComingSoonScreen`
(`lib/shared/widgets/coming_soon_screen.dart`) for now — these three
tabs are reserved for the future cross-application directory screens
(mirroring `ContactDirectoryView.vue`/etc. on web), a different thing
from the nested per-application Contacts/Interviews/Documents tabs now
live inside `ApplicationFormScreen` — see "Contacts, Interviews, and
Documents" below. Old placeholder home screen (route `/`) is gone;
`ApplicationsListScreen` at `/applications` is `initialLocation`, and
its logout button lives on that screen's `AppBar` now.

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

## Not yet implemented

- Password reset screen (backend endpoints already exist per
  BACKEND_SUMMARY.md; no mobile UI/repository method calls them yet)
- Cross-application Interviews/Contacts/Documents directory screens
  (the bottom-nav tabs of the same names) — still `ComingSoonScreen`.
  What's implemented instead is the _nested_, per-application CRUD for
  each — see "Contacts, Interviews, and Documents" below; this
  directory-screen item mirrors `ContactDirectoryView.vue`/
  `InterviewDirectoryView.vue`/`DocumentDirectoryView.vue` on web, a
  different (not-yet-started) screen entirely
- Interview reminder system — unimplemented everywhere (backend,
  webapp, mobile); TODO.md tracks it at the backend level
- In-app document download / offline document storage — downloads
  currently open the presigned URL externally via `url_launcher` only,
  no on-device copy kept
- Swipe-to-delete on the Applications list row (delete only lives on
  the Edit screen for now)
- Push notifications (FCM/APNs, device-token model) — Phase 6c
- Offline support/sync — Phase 6d, deliberately deferred until there's
  real usage data from 6a/6b to design against
- Widget/unit tests beyond the one auth smoke test — Applications,
  Contacts, Interviews, and Documents all have none yet
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
    main.dart                     # entry point: loads env, wraps app in ProviderScope
    app/
      app.dart                    # MaterialApp.router root widget, localization delegates
      router.dart                 # go_router config: redirects, shell + form routes
      app_shell.dart               # bottom NavigationBar around the shell tabs
    core/
      config/env_config.dart
      network/api_client.dart      # shared Dio instance (token interceptors)
      theme/app_theme.dart
    shared/
      widgets/coming_soon_screen.dart  # placeholder for not-yet-built tabs
    features/
      auth/
        data/                       # token_storage.dart, auth_api.dart, auth_repository.dart
        domain/                      # user.dart, auth_state.dart
        presentation/                # auth_controller.dart, login/register_screen.dart
      applications/
        data/applications_api.dart
        domain/                      # application.dart, application_draft.dart
        presentation/                 # list state/controller/screen, form screen/result,
                                       # status style, formatting (application_formatting.dart
                                       # now uses intl's DateFormat — see above)
      contacts/
        data/contacts_api.dart
        domain/                      # contact.dart, contact_draft.dart
        presentation/                 # contacts_panel.dart (tab content),
                                       # contact_form_sheet.dart (add/edit)
      interviews/
        data/interviews_api.dart
        domain/                      # interview.dart (InterviewType/InterviewResult
                                       # enums), interview_draft.dart
        presentation/                 # interviews_list_state/controller.dart
                                       # (infinite scroll, .family-scoped),
                                       # interviews_panel.dart (tab content),
                                       # interview_form_sheet.dart (add/edit),
                                       # interview_formatting.dart (intl DateFormat)
      documents/
        data/documents_api.dart       # upload() sends multipart FormData, not JSON
        domain/                      # document.dart (DocumentType enum,
                                       # DocumentDownloadResponse), no *_draft.dart —
                                       # upload/update take params directly
        presentation/                 # documents_list_state/controller.dart
                                       # (infinite scroll, local prepend/replaceById/
                                       # removeById instead of refresh()),
                                       # documents_panel.dart (tab content),
                                       # document_upload_sheet.dart, document_edit_sheet.dart
  pubspec.yaml
  analysis_options.yaml
  .env.example                    # committed template; .env.development/.env.production gitignored
  .github/workflows/mobile-ci.yml
```

Every future feature (the cross-application Interviews/Contacts/
Documents directory screens, still `ComingSoonScreen`) should get the
same `data`/`domain`/`presentation` split as `auth/`, `applications/`,
`contacts/`, `interviews/`, and `documents/`.
