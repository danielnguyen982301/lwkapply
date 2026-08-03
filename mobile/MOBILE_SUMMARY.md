# LwkApply - Job Tracker — Mobile Client

Flutter + Riverpod + go_router + Dio, implementing Phase 6 (Mobile
Application): project scaffold, auth, a 4-tab bottom nav shell, and the
first feature screens (Applications — list/create/edit/delete).
Interviews, Contacts, Documents have nav tabs wired up but are still
`ComingSoonScreen` placeholders.

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
(`lib/shared/widgets/coming_soon_screen.dart`) for now. Old placeholder
home screen (route `/`) is gone; `ApplicationsListScreen` at
`/applications` is `initialLocation`, and its logout button lives on
that screen's `AppBar` now.

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
- Interviews, Contacts, Documents feature screens (tabs exist,
  screens are `ComingSoonScreen` — follow `features/applications/`'s
  folder split)
- Swipe-to-delete on the Applications list row (delete only lives on
  the Edit screen for now)
- Push notifications (FCM/APNs, device-token model) — Phase 6c
- Offline support/sync — Phase 6d, deliberately deferred until there's
  real usage data from 6a/6b to design against
- Widget/unit tests beyond the one auth smoke test — Applications has
  none yet
- iOS build in CI (Android debug build only currently)
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
                                       # status style, formatting
  pubspec.yaml
  analysis_options.yaml
  .env.example                    # committed template; .env.development/.env.production gitignored
  .github/workflows/mobile-ci.yml
```

Every future feature (Interviews, Contacts, Documents) should get the
same `data`/`domain`/`presentation` split as `auth/` and
`applications/`.
