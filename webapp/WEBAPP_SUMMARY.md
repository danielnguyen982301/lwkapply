# Job Tracker — Web Frontend

Vue 3 + TypeScript + Vite + Pinia + Vue Router + Tailwind + PrimeVue
(`primevue` pinned to exactly `4.5.4` — `4.5.5` has a `DatePicker`
regression, see CHANGELOG.md).
Phase 1 (foundation, auth) and Phase 2 application tracking (list, search/
filter, details, Kanban board) are implemented. Phase 4's Contact
management, Interview scheduling, and Phase 3's Document upload/download
are now all implemented on the frontend too — see Contacts, Interviews,
and Documents below. Interviews also now has a cross-application
directory view, mirroring Contacts' — see Interviews below.

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

### Form validation

All forms (`LoginView.vue`, `RegisterView.vue`, `ApplicationFormView.vue`,
and the Contacts/Interviews panel dialogs) run on
**vee-validate** + **`@vee-validate/zod`**, replacing the hand-rolled
`reactive()` + manual `validate()` function pattern each used to have.

- **Schema-per-form**, defined with `zod` and wrapped in
  `toTypedSchema()`, passed to `useForm({ validationSchema, initialValues })`.
  `zod` is pinned to `^3.24.0` — `@vee-validate/zod`'s `toTypedSchema`
  has a hard peer dependency on Zod v3 and does not support v4 (see
  CHANGELOG.md, v0.5.0). Don't bump `zod` past v3 until vee-validate v5
  (which drops `toTypedSchema` for Standard Schema support) is stable.
- **Reusable field components**
  (`src/components/custom_form_fields/CustomInputText.vue`,
  `CustomPassword.vue`) wrap the corresponding PrimeVue input and call
  `useField(() => props.name)` internally, exposing the bound `value` via
  `v-model` to the underlying PrimeVue component and rendering the
  field's `errorMessage` itself. Consuming views just render
  `<CustomInputText name="email" ... />` — they don't touch `useField`
  directly, similar in spirit to how PrimeVue Forms' `name`-based
  auto-registration was meant to work, but without depending on PrimeVue's
  own (buggier) Forms package.
- **Dirty-tracking / disabled-Save-button** on edit forms
  (`ApplicationFormView.vue` and the panel edit dialogs) is intended to
  use vee-validate's field `meta.dirty`, which reflects "differs from the
  form's current initial values" (not "was ever touched") — the semantics
  the Save button needs — with re-baselining after an async data load via
  vee-validate's documented pattern of watching the fetched data and
  calling `resetForm()` with the new values once it arrives.
- **PrimeVue's own `@primevue/forms` package was evaluated and rejected**
  first — see CHANGELOG.md (v0.5.0) for the specific, confirmed upstream
  bugs that drove the switch (DatePicker formatting/typing bugs, unreliable
  post-load dirty-tracking, stale cross-field validation).

**Testing gotcha, worth knowing before writing new form tests**:
vee-validate's validation doesn't resolve synchronously the way the old
hand-rolled `validate()` functions did. A test that does
`await wrapper.find('form').trigger('submit')` and then immediately
asserts on error text or a `handleSubmit`-gated store call can fail even
when the form logic is correct, simply because the assertion runs before
validation has resolved — even an extra `await flushPromises()` isn't
always enough. Wrap the assertion itself in `vi.waitFor(() => { ... })`
instead. This bit `LoginView.spec.ts` directly during the migration.

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

### Interviews

Two separate pieces, backed by two separate stores — same split as
Contacts, one scoped to a single application (CRUD), one a read-only
cross-application listing:

- **Per-application panel** (`InterviewsPanel.vue`): rendered inside
  `ApplicationFormView.vue`, alongside `ContactsPanel.vue`, same
  `v-if="!isNew && applicationId"` gating. Pinia `interviews` store
  (`src/stores/interviews.ts`) — same application-scoping/`reset()`-on-
  unmount pattern as Contacts, but unlike Contacts' nested list, this
  backend endpoint IS paginated (see BACKEND_SUMMARY.md), so the store
  also tracks `page`/`pageSize`/`total` like the Applications store, and
  the panel shows a `Paginator` once there's more than one page.
  Schedule/edit via a PrimeVue `Dialog`: type, date & time (`DatePicker`
  with `show-time`), duration in minutes, result, and freeform feedback.
  Create and update both refetch the current page afterward rather than
  patching the item in place client-side, since the list is
  server-sorted by `scheduled_at` and a client-side guess at where a
  new/edited row belongs could land in the wrong spot.
- **Directory view** (`InterviewDirectoryView.vue`, route `/interviews`,
  the "Interviews" nav item in `AppLayout.vue` — no longer disabled):
  every interview across every application the user owns, with the
  parent application's company/position/status shown per row and
  linking back to `application-detail`. Read-only by design, same
  reasoning as the Contacts directory — the empty state and copy point
  the user back to the relevant application to schedule/edit an
  interview. Pinia `interviewDirectory` store
  (`src/stores/interviewDirectory.ts`) — paginated, same
  `DataTable`/`Paginator` skeleton as `ContactDirectoryView.vue`, hitting
  the backend's `GET /interviews`. One deliberate divergence from
  Contacts: no debounced text search — `Interview` has no name-like
  field to filter by — so this uses a PrimeVue `Select` filtering on
  `result` (`interviewResultFilterOptions()` in `interview-ui.ts`)
  instead of an `IconField`/`InputText` search box. Table columns show
  scheduled date/time, type, company, position, application status, and
  result as a `Tag` (`interviewResultSeverity()`), plus duration.
- `src/types/interview.ts` mirrors `InterviewRead`/`InterviewCreate`/
  `InterviewUpdate`, plus `InterviewWithApplication` (directory, adds the
  embedded `application` summary) and `InterviewDirectoryParams`.
  `src/lib/interview-ui.ts` holds type/result labels, select options,
  result-severity mapping, and `interviewResultFilterOptions()` (mirrors
  `application-ui.ts`'s `applicationStatusFilterOptions()` convention —
  an "All results" / `null` option prepended to the real values).

### Documents

- **Panel** (`DocumentsPanel.vue`): same location/gating as Contacts and
  Interviews. Pinia `documents` store (`src/stores/documents.ts`) — same
  scoping pattern, paginated like Interviews.
- Upload dialog: plain native `<input type="file">` (not PrimeVue's
  `FileUpload` — not currently part of this app's PrimeVue usage) plus a
  document-type select; uploads as `multipart/form-data`. Downloading
  fetches a short-lived presigned S3 URL from the backend per click and
  opens it directly (`window.open`) — the API never returns a permanent
  file URL, so nothing is cached client-side. A separate, smaller edit
  dialog covers the one field the backend actually allows changing after
  upload (`file_type`); delete uses the existing `ConfirmDialog` pattern.
- `src/types/document.ts` mirrors `DocumentRead`/`DocumentUpdate`/the
  presigned-download response. `src/lib/document-ui.ts` mirrors
  `interview-ui.ts`'s labels/options/severity convention.

## What's deliberately not here yet

- Analytics dashboard and charts — Phase 5
- RBAC-aware UI — explicitly skipped per current backend scope
- Documents directory view (cross-application, read-only — the
  `ContactDirectoryView.vue`/`InterviewDirectoryView.vue` /
  `GET /contacts`/`GET /interviews` pattern, not yet built for Documents;
  currently only has the per-application panel described above). See
  CHANGELOG.md's v0.5.0 Planned section
- Component/store tests for Applications UI (auth tests exist; application
  views not yet covered) — Contacts, Interviews (including the new
  directory view/store), and Documents UI (panels and stores) are in the
  same boat: no tests yet

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
Applications views/stores, the Contacts UI (`ContactsPanel.vue`,
`ContactDirectoryView.vue`, `stores/contacts.ts`,
`stores/contactDirectory.ts`), and the Interviews/Documents UI
(`InterviewsPanel.vue`, `InterviewDirectoryView.vue`, `DocumentsPanel.vue`,
`stores/interviews.ts`, `stores/interviewDirectory.ts`,
`stores/documents.ts`) — worth adding next as the UI stabilises.

New devDependency: `@pinia/testing` (store stubbing for component tests).
