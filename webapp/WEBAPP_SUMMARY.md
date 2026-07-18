# Job Tracker — Web Frontend

Vue 3 + TypeScript + Vite + Pinia + Vue Router + Tailwind + PrimeVue.
Phase 1 (foundation, auth) and Phase 2 application tracking (list, search/
filter, details, Kanban board) are implemented. Contact management (part
of Phase 4) is also implemented on the frontend now — see Contacts below;
Interview scheduling and Document upload/download, the rest of Phase 4/3,
are not yet built.

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
`IconField`, `InputIcon`, `Dialog`, and `ConfirmDialog`.

### Contacts

Two separate pieces, backed by two separate stores — one scoped to a
single application (CRUD), one a read-only cross-application listing:

- **Per-application panel** (`ContactsPanel.vue`): rendered inside
  `ApplicationFormView.vue`, below the main form, only once an
  application exists (`v-if="!isNew && applicationId"` — there's nowhere
  to nest a contact under an application that hasn't been created yet).
  Pinia `contacts` store (`src/stores/contacts.ts`) holds one
  application's contact list at a time, keyed by `applicationId` so a
  slow response can't clobber the panel after navigating to a different
  application; `reset()` is called on unmount for the same reason. Add/edit
  via a PrimeVue `Dialog` (name required, client-side email-format check,
  title, LinkedIn URL); delete via the existing `ConfirmDialog` pattern.
- **Directory view** (`ContactDirectoryView.vue`, route `/contacts`, the
  "Contacts" nav item in `AppLayout.vue` — no longer disabled): every
  contact across every application the user owns, with the parent
  application's company/position/status shown per row and linking back to
  `application-detail`. Read-only by design — the empty state and copy
  point the user back to the relevant application to add/edit a contact,
  rather than duplicating that form here. Pinia `contactDirectory` store
  (`src/stores/contactDirectory.ts`) — paginated + debounced search,
  same `DataTable`/`Paginator`/`IconField` skeleton as
  `ApplicationListView.vue`, hitting the backend's `GET /contacts`.
- `src/types/contact.ts` mirrors both backend response shapes: the plain
  `Contact` (nested CRUD) and `ContactWithApplication` (directory, adds
  the embedded `application` summary).

## What's deliberately not here yet

- Interviews/Documents UI — Phase 2+ (backend endpoints exist; Contacts UI
  is now done, see above)
- Analytics dashboard and charts — Phase 5
- RBAC-aware UI — explicitly skipped per current backend scope
- Component/store tests for Applications UI (auth tests exist; application
  views not yet covered) — Contacts UI (panel, directory, both stores) is
  in the same boat: no tests yet

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
`AppLayout`/`AuthLayout` (minimal placeholder/shell markup), all
Applications views/stores, and the new Contacts UI (`ContactsPanel.vue`,
`ContactDirectoryView.vue`, `stores/contacts.ts`,
`stores/contactDirectory.ts`) — worth adding next as the UI stabilises.

New devDependency: `@pinia/testing` (store stubbing for component tests).
