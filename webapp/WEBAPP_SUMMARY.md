# Job Tracker — Web Frontend

Vue 3 + TypeScript + Vite + Pinia + Vue Router + Tailwind + PrimeVue.
Phase 1 (foundation, auth) and Phase 2 application tracking (list, search/
filter, details, Kanban board) are implemented.

## What's here

### Foundation (Phase 1)

- **Build tooling**: Vite, TypeScript (strict), path alias `@/` → `src/`
- **Styling**: Tailwind design tokens (`tailwind.config.js` + CSS variables
  in `src/style.css`) layered on top of PrimeVue's Aura theme; Tailwind
  handles layout/spacing/branding, PrimeVue handles interactive controls
- **Routing**: `src/router/index.ts` — `AppLayout` for authenticated routes,
  `AuthLayout` for login/register, lazy-loaded views, `beforeEach` guard
  driven by `route.meta`
- **State**: Pinia `auth` store (`src/stores/auth.ts`) — access token in
  memory only; refresh token in an httpOnly cookie the backend sets
- **API client**: `src/lib/api.ts` — Axios with `withCredentials: true`,
  bearer-token injection, CSRF double-submit header on unsafe requests,
  queued refresh-on-401 interceptor
- **Screens**: Login, Register, Dashboard placeholder, 404

### Application tracking (Phase 2)

- **Store**: Pinia `applications` store (`src/stores/applications.ts`) —
  typed API calls for paginated list, single fetch, create, update,
  delete, and board fetch; separate list vs. board state so switching
  List/Board views doesn't clobber pagination
- **List view** (`ApplicationListView.vue`): PrimeVue `DataTable` with
  server-side pagination (`Paginator`), debounced search (`IconField` +
  `InputText`), status filter (`Select`), status badges
  (`ApplicationStatusTag`), delete via `ConfirmDialog`
- **Details / New** (`ApplicationFormView.vue`): one component, two routes
  (`application-new`, `application-detail`); PrimeVue form controls with
  client-side validation; create redirects to detail on success
- **Kanban board** (`ApplicationBoardView.vue`): columns per status,
  drag-and-drop moves via `vue-draggable-plus`, optimistic UI with
  server sync; keyboard/screen-reader path via per-card status `Select`
- **View toggle** (`ViewTabs.vue`): PrimeVue `TabMenu` switching List ↔
  Board
- **Shared UI helpers**: `src/lib/application-ui.ts` (status severities,
  select options), `src/components/applications/ApplicationStatusTag.vue`

### PrimeVue usage

Configured in `src/main.ts` (Aura theme, `ConfirmationService`,
`primeicons`). Global `ConfirmDialog` lives in `App.vue`. Components used
across the app include `Button`, `InputText`, `Password`, `Select`,
`DataTable`, `Column`, `Paginator`, `Tag`, `Badge`, `Card`, `Message`,
`ProgressSpinner`, `TabMenu`, `DatePicker`, `InputNumber`, `Textarea`,
and `ConfirmDialog`.

## What's deliberately not here yet

- Interviews/Contacts/Documents UI — Phase 2+ (backend endpoints exist)
- Analytics dashboard and charts — Phase 5
- RBAC-aware UI — explicitly skipped per current backend scope
- Component/store tests for Applications UI (auth tests exist; application
  views not yet covered)

## Auth cookie flow

Sessions persist across a hard reload: the refresh token lives in an
httpOnly cookie set by the backend, and `Vue Router` calls
`authStore.bootstrap()` before each route if the `bootstrapped` flag is
`false` (runs once per app mount). See `src/stores/auth.ts`,
`src/lib/api.ts`, and `src/router/index.ts` for the full flow.

## CI

`.github/workflows/webapp-ci.yml` (repo root) runs on every push/PR
touching `webapp/**`: eslint → prettier --check → vue-tsc type-check →
vitest with coverage → production build.

Supporting config under `webapp/`:

- `eslint.config.js` — flat config (ESLint 9), Vue 3 + TypeScript
- `.prettierrc.json` / `.prettierignore`
- `vite.config.ts` — Vitest block (jsdom, v8 coverage)
- `package.json` — separate `lint` (CI-safe) from `lint:fix` (local);
  `type-check` and `format:check` scripts

`.pre-commit-config.yaml` (repo root) includes eslint and prettier hooks
for `webapp/`.

## UI tests

Beyond the pure-function `api.spec.ts` smoke test:

- `src/router/__tests__/authGuard.spec.ts` — exported `authGuard()`
  redirect logic, testable without a full router instance
- `src/views/auth/__tests__/LoginView.spec.ts` — mounts the real component
  with `@vue/test-utils`, `createTestingPinia`, a minimal test router, and
  the PrimeVue test helper (`src/test/primevue.ts`); covers empty-submit
  validation, successful login + redirect-to-intended-page, and error
  display

**Deliberately not tested yet**: `DashboardView`, `NotFoundView`,
`AppLayout`/`AuthLayout` (minimal placeholder/shell markup), and all
Applications views/stores — worth adding next as the UI stabilises.

New devDependency: `@pinia/testing` (store stubbing for component tests).
