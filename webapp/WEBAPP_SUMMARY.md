# Job Tracker — Web Frontend

Vue 3 + TypeScript + Vite + Pinia + Vue Router + Tailwind + PrimeVue
(`primevue` pinned to exactly `4.5.4` — `4.5.5` has a `DatePicker`
regression, see CHANGELOG.md).
Phase 1 (foundation, auth) and Phase 2 application tracking (list, search/
filter, details, Kanban board) are implemented. Phase 4's Contact
management, Interview scheduling, and Phase 3's Document upload/download
are now all implemented on the frontend too — see Contacts, Interviews,
and Documents below. All three now also have a cross-application
directory view (Contacts, Interviews, and Documents), each mirroring the
same `DataTable`/`Paginator` skeleton — see each section below. Phase 5's
Analytics dashboard is implemented as of this pass — see Analytics below.
Phase 7's Resume Parser and ATS Score (backend already existed) now have
a web UI too — see AI Tools below, the first async/polling flow in this
frontend.

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
  client-side validation; create redirects to detail on success. The
  page's `<h1>` is the `application_name` field itself — an editable
  text input styled to read as a heading (no visible border by default;
  PrimeVue's own `.p-inputtext` border/shadow needed `!`-important
  Tailwind overrides to actually disappear, since its base styles beat
  plain utility classes), placeholder falling back to `company` (then
  "Edit Application"/"New Application") when blank. A small pencil icon
  next to it, wrapped in a native `<label for="application_name">` (so
  clicking it focuses the input via the browser's own label/input
  association, no click handler needed) plus a `v-tooltip` ("Edit
  application name"), signals that it's editable rather than static text
  — the field isn't otherwise present anywhere else in the form
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
`primeicons`, and the `Tooltip` directive registered globally as
`v-tooltip`). Global `ConfirmDialog` lives in `App.vue`. Components used
across the app include `Button`, `InputText`, `Password`, `Select`,
`DataTable`, `Column`, `Paginator`, `Tag`, `Badge`, `Card`, `Message`,
`ProgressSpinner`, `TabMenu`, `DatePicker`, `InputNumber`, `Textarea`,
`IconField`, `InputIcon`, `Dialog`, and `ConfirmDialog`.

**`v-tooltip`, not the native `title` attribute**, on every icon-only
action button app-wide — native `title` has a fixed, unstyleable ~1s
OS-level show delay that makes an icon-only control feel unresponsive on
hover. `src/lib/tooltip.ts`'s `tooltip(value)` helper returns `{ value,
showDelay: 150 }`, so every usage (`v-tooltip.bottom="tooltip('Edit
contact')"`) gets the same fast, consistent delay instead of each call
site hand-rolling its own options object. Plain text still uses native
`title` where it's genuinely just "show the full value of this truncated
cell on hover," not a primary interactive affordance — see
`TruncatedText.vue` below.

**`components/common/TruncatedText.vue`** — single-line ellipsis
truncation with an explicit `max-width` and a `title` fallback showing
the full value on hover. Exists because a bare Tailwind `truncate` class
does nothing by itself inside a `DataTable` cell: the `<td>` grows to fit
its content in an auto-layout table, so truncation needs a hard width
constraint on the inner element, not just `overflow-hidden`. Used across
every list/directory table's free-text columns (`ApplicationListView.vue`,
`ContactDirectoryView.vue`, `InterviewDirectoryView.vue`,
`DocumentDirectoryView.vue`, the AI Tools tables, and the AutoComplete
picker/dialog suggestion lists) — company/position/application_name/
file_name/location/title, anything that can't be trusted to fit.

**`src/lib/row-click.ts`**'s `useApplicationRowClick<T>(getApplicationId)`
— a shared composable returning a `handleRowClick` handler for
`DataTable`'s `@row-click`: skips clicks that originated on an
already-interactive element inside the row (a link, a button — checked
via `event.originalEvent.target.closest('a, button')`), otherwise
navigates to `application-detail`. Used by `ApplicationListView.vue`
(`row => row.id`), `ContactDirectoryView.vue`/`InterviewDirectoryView.vue`
(`row => row.application.id`) so clicking anywhere in a row opens the
application, not just its Company-column link.

**`src/lib/date-utils.ts`**'s `formatDate`/`formatDateTime` — two shared
`Intl.DateTimeFormat` instances (date-only `'medium'`; date+time
`'medium'`/`'short'`), replacing what used to be eight separately
hand-constructed formatter instances scattered across pickers, dialogs,
and directory views. `formatDateTime` is used wherever two rows could
otherwise share a date-only label (a resume re-uploaded/re-analyzed
same-day, two documents with the same file name) and the time is what
actually tells them apart.

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
  via `components/contacts/ContactFormDialog.vue` (name required,
  client-side email-format check, title, LinkedIn URL) — one dialog for
  both, keyed off a `contact: Contact | null` prop (`null` = add mode);
  `createContact()`/`updateContact()` already patch the store's own
  `items` array on success, so the panel needs no follow-up sync, no
  emit from the dialog. Delete via the existing `ConfirmDialog` pattern.
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
  Schedule/edit via `components/interviews/InterviewFormDialog.vue`
  (same one-dialog-both-modes shape as `ContactFormDialog.vue`, keyed off
  an `interview: Interview | null` prop): type, date & time (`DatePicker`
  with `show-time`), duration in minutes, result, and freeform feedback.
  Create and update both refetch the current page afterward rather than
  patching the item in place client-side, since the list is
  server-sorted by `scheduled_at` and a client-side guess at where a
  new/edited row belongs could land in the wrong spot — so, unlike
  `ContactFormDialog.vue`, the dialog needs no emit either (the store's
  own refetch already keeps the panel in sync).
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

Reworked into a top-level document library, matching the backend's own
decoupling (see BACKEND_SUMMARY.md's "A note on Document /
ApplicationDocument") — a document is no longer owned by exactly one
application, so this is no longer a CRUD-panel-vs-read-only-directory
split like Contacts/Interviews. Instead, **two stores split by
relationship, not by CRUD-vs-read-only**:

- **`stores/documents.ts`** — the user's whole document library:
  paginated list (search by `file_name`, filter by `file_type`), upload,
  update (`file_type` only), download (presigned R2 URL, minted per
  click and opened directly via `window.open` — the API never returns a
  permanent file URL), and permanent delete. Used by
  `DocumentDirectoryView.vue` (route `/documents`, the "Documents" nav
  item — now the primary place to manage the library, not a read-only
  view) and, for search/upload/download, by `DocumentsPanel.vue` too.
- **`stores/applicationDocuments.ts`** — one application's *attached*
  documents: list, attach (`POST`, picks an existing library document by
  id), detach (`DELETE`, removes the link only — never deletes the
  document). Used by `DocumentsPanel.vue` (`components/applications/`),
  rendered inside `ApplicationFormView.vue` same as Contacts/Interviews.
  `confirmDetach()`'s copy is explicit that this doesn't delete the
  document ("... stays in your document library").
- **Three shared dialog components** (`components/documents/`), used by
  both `DocumentsPanel.vue` and `DocumentDirectoryView.vue`:
  - `DocumentUploadDialog.vue` — uploads straight to the library
    (`useDocumentsStore`), regardless of which view opened it. Emits
    `uploaded` with the created `Document`; closes itself immediately on
    success. `DocumentsPanel.vue`'s extra step — attaching the new
    document to the current application — is deliberately **not** this
    component's concern: the panel does that as a follow-up call in its
    `uploaded` handler, after the dialog has already closed, surfacing
    any attach failure via its own `attachError` message rather than
    inside the (by then closed) dialog
  - `DocumentEditDialog.vue` — edits `file_type`, always through the
    library store even when opened from the application-scoped panel
    (`file_type` is a property of the document, not of any one
    application it's attached to). `DocumentsPanel.vue` patches its own
    `applicationDocuments.items` array on the `updated` emit, since
    that's a different store's array than the one the dialog itself
    updated
  - `DocumentAttachDialog.vue` — only used by `DocumentsPanel.vue` today
    (pulled out alongside the other two anyway, to keep the panel's
    template down to just the list it owns). `AutoComplete` search
    against the library (already-attached documents filtered out of the
    suggestions client-side, since attaching one twice would just `409`);
    suggestion rows show file name (`TruncatedText`) and upload date+time
    (`formatDateTime` — two documents can share a file name, e.g.
    "resume.pdf" re-uploaded after edits, so the timestamp is what tells
    them apart)
- `src/types/document.ts` mirrors `DocumentRead`/`DocumentUpdate`/the
  presigned-download response — no more `application_id` anywhere on
  `Document`, no more `DocumentApplicationSummary`/`DocumentWithApplication`
  (a document can have zero, one, or several parent applications now, so
  there's no single one left to embed). New
  `ApplicationDocumentCreatePayload` for the attach call.
  `src/lib/document-ui.ts` unchanged (labels/options/severity,
  `documentTypeFilterOptions()`).

Table columns on `DocumentDirectoryView.vue`: file name (`TruncatedText`),
type as a `Tag`, and uploaded date+time (`formatDateTime` — was date-only
before this pass, changed to match the pickers/attach dialog's
same-file-name-distinguishing reasoning above). No more company/position/
status columns — those only made sense when a document had exactly one
parent application.

### Analytics

`AnalyticsDashboardView.vue` (route `/analytics`, "Analytics" nav item in
`AppLayout.vue`, appended last per the order features were added), backed
by one Pinia store (`src/stores/analytics.ts`) covering all four
`GET /analytics/*` endpoints — deliberately one store, not four, unlike
Contacts/Interviews/Documents' CRUD-vs-directory split: these four
endpoints are only ever consumed together by this one screen, so a
single store keeps that relationship visible. Each of the four sections
(`fetchSummary`/`fetchFunnel`/`fetchActivity`/`fetchInterviews`) tracks
its own `status`/`error` independently and `fetchAll()` fires them via
`Promise.allSettled` — one slow or failing endpoint doesn't block the
other three from rendering.

- **First chart usage in this codebase** — new `chart.js` dependency,
  rendered via PrimeVue's `Chart` wrapper component (bundled with
  `primevue`, but `chart.js` itself isn't, so it needed adding
  separately).
- **Overview**: five `StatCard`s (Total Applications, Active, Offers
  Received, Interviews Scheduled, Response Rate). "Response Rate" carries
  a one-line hint (`Applications that moved past "applied"`) since the
  number alone would read as a real employer-response metric — it's a
  documented proxy, not a tracked one (see BACKEND_SUMMARY.md).
- **Pipeline**: horizontal bar chart, one deliberate design choice worth
  knowing about — the funnel stages (`saved` → `accepted`) read
  top-to-bottom as one continuous gradient of teal intensity
  (`src/lib/analytics-ui.ts`'s `funnelStageColor()`), so the color itself
  encodes progression through the pipeline rather than being decorative.
  This diverges from every other status-color mapping in the app
  (`application-ui.ts`'s severity-based Tag colors), which is
  intentional: those exist to distinguish statuses at a glance in a list;
  this chart's job is to show _progression_, which a shared-hue gradient
  communicates and a set of unrelated severity colors wouldn't. The
  caption below the chart states explicitly that this is a current-status
  snapshot, not a lifetime conversion funnel — see BACKEND_SUMMARY.md's
  note on `application_status_history` for why. `off_ramps`
  (rejected/withdrawn) render as plain text below the chart, not
  additional bars.
- **Interview Outcomes**: donut chart (pending/passed/failed/cancelled)
  plus a pass-rate line that spells out its own denominator inline
  (`passed ÷ passed+failed, excludes pending/cancelled`).
- **Activity**: bar chart of monthly application counts, zero-filled, with
  a `SelectButton` toggle (3/6/12 months) that refetches just that one
  section via `fetchActivity(months)`.
- `AnalyticsSection.vue` extracts the loading/error/retry pattern
  `ContactDirectoryView.vue` established, so it's not copy-pasted four
  times across one screen.
- `src/types/analytics.ts` mirrors the backend's `app/schemas/analytics.py`
  response shapes exactly, including the same nullability on
  `response_rate`/`pass_rate` (null when there's no data to compute them
  from yet).

### AI Tools

`ResumeAnalysesView.vue` (route `/resume-analyses`) and `AtsScoresView.vue`
(route `/ats-scores`), reached via one "AI Tools" nav item
(`layouts/AppLayout.vue`) pointing at `/resume-analyses`, with a shared
`AiToolsTabs.vue` switching between the two routes — copies
`ViewTabs.vue`'s List/Board toggle shape exactly (`TabMenu`,
`router.push` per tab, `activeIndex` synced off `route.name`), not a new
"combined tabs" pattern. Two separate stores
(`stores/resumeAnalyses.ts`/`stores/atsScores.ts`), one per resource type,
matching every other feature's "one store per resource" convention.

- **First async/polling flow in this frontend.** Both backend endpoints
  (`POST /ai/resume-analyses`, `POST /ai/ats-scores`) return `202` with a
  `pending` row; each store's `startPolling(id)` sets a 3s `setInterval`
  calling `fetchOne(id)` until status is `completed`/`failed`, with a
  40-attempt (~2 min) safety cap (`pollingTimedOut`). Every view/component
  that starts a poll stops it in `onUnmounted`/`onBeforeUnmount` — same
  "don't leak a background operation into a screen the user has left"
  reasoning `stores/documents.ts`'s `reset()`-on-unmount already
  established, just applied to an interval instead of request state.
- **`AtsScore` has no application link at all** (see
  BACKEND_SUMMARY.md's "A note on Document / ApplicationDocument") — the
  create payload takes `job_url` directly instead of an `application_id`
  for the backend to resolve later. `NewAtsScoreDialog.vue`'s job-
  description-source toggle has three options, not two: "Use a tracked
  application" (`ApplicationPicker.vue` picks an `Application`, and the
  view reads `selectedApplication.job_url` client-side into the payload —
  a client-side warning shows if the picked application has no
  `job_url`), "Paste a job URL" (a plain `InputText`, sent as `job_url`
  directly, no application involved), or "Paste a job description".
- **Create/detail dialogs extracted into their own components**
  (`components/ai/`): `NewResumeAnalysisDialog.vue`/
  `ResumeAnalysisDetailDialog.vue` (out of `ResumeAnalysesView.vue`) and
  `NewAtsScoreDialog.vue`/`AtsScoreDetailDialog.vue` (out of
  `AtsScoresView.vue`). Both detail dialogs read their store's `current`
  directly (set by the parent right before opening, and reassigned by
  `store.create()` on a fresh create or a failed-score retry) rather than
  taking the record as a prop — a prop would need the parent to re-sync
  it on every retry; reading the store directly means it doesn't have to.
  Both own their own polling start/stop, keyed off their `visible` model.
- **New reusable components** (`components/ai/`): `ResumeDocumentPicker.vue`
  / `ApplicationPicker.vue` (both a `defineModel`-based PrimeVue
  `AutoComplete` — first use of that component in this codebase —
  debounced search, mirroring `DocumentDirectoryView.vue`'s 300ms
  debounce), `ParsedResumeDisplay.vue` / `AtsScoreDisplay.vue`
  (read-only result renderers), `AiToolsTabs.vue`.
  - `ResumeDocumentPicker.vue`'s suggestions show upload date+time
    (`formatDateTime`) next to the (`TruncatedText`) file name — two
    resumes can share a file name (a re-upload after edits), so the
    timestamp is what actually tells them apart.
  - `ApplicationPicker.vue`'s suggestions show `application_name` (when
    set, truncated) and `applied_date` alongside company/position, plus
    the existing "Has job URL"/"No job URL" tag.
  - `AtsScoreDisplay.vue` shows `job_url` (when the score was sourced
    from one) instead of the old `applicationSummary` prop — there's no
    application to summarize from any more.
- **Isolated search methods, not the existing directory stores' mutating
  fetches.** `ResumeDocumentPicker`/`ApplicationPicker` need live search
  against `documents`/`applications`, but calling
  `documents.fetchDocuments()`/`applications.fetchApplications()`
  directly would clobber the Documents Library/Applications List views'
  own `items`/`page`/`filters` state, since both are reachable in the
  same session without a full reload. Fixed by
  `documents.searchDocuments(query, fileType?, pageSize?)` and
  `applications.searchApplications(query)` — small isolated methods that
  return data directly without touching shared list state. Same
  reasoning extends to `resumeAnalyses.fetchLatestForDocument()`/
  `fetchCompletedForPicker()` and
  `atsScores.fetchLatestForResumeAnalysis()` (the latter renamed from
  `fetchLatestForApplication()` now that a score is looked up by
  `resume_analysis_id` alone, no `application_id` to also filter by —
  and simplified in the process: the backend's `GET /ai/ats-scores` now
  filters by `resume_analysis_id` directly, so the store no longer needs
  its own client-side `.find()` over a larger page the way the old
  application-scoped version did).
- **`ResumeAnalysisModal.vue`**: opened from a per-row action on
  `components/applications/DocumentsPanel.vue` (icon-only button, resume-
  type documents only) — lets a user view/start an analysis and score it
  against the current application directly from the Documents panel,
  without switching to the AI Tools tab. Takes a `jobUrl: string | null`
  prop (the current application's `job_url`, already loaded by the
  parent `ApplicationFormView.vue`) rather than an `applicationId` — the
  score itself no longer references any application, so there's nothing
  to derive server-side. Shows only the *latest* analysis/score for the
  document, not full history (that's the AI Tools tab's job). Reuses
  `resumeAnalyses`/`atsScores`' `current`/polling state directly rather
  than local component state — safe because this modal,
  `ResumeAnalysesView`, and `AtsScoresView` are never mounted at the same
  time (different routes, Vue Router unmounts one before mounting
  another).
  - **Can re-score even when a completed score already exists** — a
    "Score again" toggle reveals the same scoring form below the
    existing score, without hiding it until the new attempt actually
    completes. This matters specifically because a score has no
    application link any more: the *latest* score for a resume could
    just as easily be one run from `AtsScoresView.vue` against a
    completely different application's job description, so "there's
    already a score" no longer means "there's nothing useful left to do
    here." A `showRescoreForm` ref plus a `showScoreForm` computed
    (`!current || showRescoreForm`) drive this; a watcher on the score's
    `status` collapses the form back down once a rescore actually
    completes. Fixed two computeds (`atsScoreErrorMessage`/
    `showAtsPasteFallback`) that used to gate on `!atsScores.current` —
    during a rescore `current` still holds the *previous* completed
    score while the new attempt is in flight/failing, so that guard
    would have silently swallowed a real rescore error instead of
    showing it.
- **Cross-link**: a completed analysis's detail view has a "Score against
  a job" button that navigates to `{ name: 'ats-scores', query:
  { resume_analysis_id } }`; `AtsScoresView.vue` reads that query param on
  mount to pre-select the resume in its own create dialog.
- **Bug caught during manual verification, fixed same pass**:
  `ResumeAnalysisModal.vue`'s inline "Analyze now"/"Score now" buttons
  originally had no error display at all — a `503`/`429` failure was
  correctly caught by the store but the user got zero feedback, just a
  button that silently stopped loading. Fixed by rendering
  `resumeAnalyses.createError`/`atsScores.createError` in those two
  states. `ResumeAnalysesView.vue`/`AtsScoresView.vue`'s own create
  dialogs already had this (verified working), since they follow the
  `DocumentsPanel.vue` upload-dialog convention of a `Message` at the top
  of the form — the modal's inline buttons just didn't have an
  equivalent form to attach one to.
- Job-description length hint (50–20000 chars) on the paste `Textarea`
  (`NewAtsScoreDialog.vue`, `AtsScoreDetailDialog.vue`'s retry form,
  `ResumeAnalysisModal.vue`'s paste fallback) is a client-side hint only
  — the server is the real validator, same "hint, not a hard block"
  approach as everywhere else a backend constraint is surfaced
  client-side in this app.
- Resume Analyses table gained an "Analyzed At" column
  (`formatDateTime(data.completed_at)`, showing "—" while still
  pending/failed) alongside the existing "Created" column — `completed_at`
  is the field that actually distinguishes re-runs of the same resume.
  `NewAtsScoreDialog.vue`'s resume `Select` shows the same "Analyzed at"
  timestamp next to each (`TruncatedText`) resume label, for the same
  reason.
- **Server-side `document_file_name`/`analysis_name` joins replaced a
  frontend-only join capped at 100 items** — see BACKEND_SUMMARY.md's
  "`analysis_name`, `scored_at`, and server-side `document_file_name`
  joins" section for the backend side. `ResumeAnalysesView.vue`/
  `AtsScoresView.vue` used to call `documents.searchDocuments('', 'resume', 100)`
  on mount (and, for `AtsScoresView.vue`, `resumeAnalyses.fetchCompletedForPicker()`
  too) purely to build a `document_id -> file_name` lookup map for row
  labels — a real correctness bug for any user with more than 100
  documents/analyses, since anything past the cap silently fell back to a
  generic date-based label. Both views now just read
  `data.document_file_name`/`data.analysis_name` straight off the API
  response; `stores/documents.ts`/`useDocumentsStore` is no longer
  imported by either view at all.
- **`NewAtsScoreDialog.vue`'s Resume field: preloaded `Select` → live
  `AutoComplete`.** Previously backed by `resumeAnalyses.fetchCompletedForPicker()`
  (fetch the most recent 100 analyses, filter to `status="completed"`
  client-side) — same 100-item ceiling problem as the join above, just for
  a picker instead of a label. Now a debounced `AutoComplete`
  (`resumeAnalyses.searchCompletedForPicker(query)`, hitting the backend's
  new `status`/`search` params directly), matching
  `ApplicationPicker.vue`/`ResumeDocumentPicker.vue`'s existing pattern
  exactly — `option-label="analysis_name"`. The `?resume_analysis_id=...`
  prefill (arriving from `ResumeAnalysesView.vue`'s "Score against a job"
  button) no longer needs the id to be present in a preloaded list either:
  a new isolated `resumeAnalyses.fetchResumeAnalysisById(id)` fetches it
  directly, same "isolated, doesn't touch shared `current`/polling state"
  reasoning as `applications.fetchApplicationById()`. `AtsScoresView.vue`
  correspondingly dropped its own `completedAnalyses` preload entirely —
  `openCreateDialog()` is a plain synchronous function again.
- **`ResumeAnalysisModal.vue`: "Latest" tags, Analyzed/Scored timestamps,
  and the analysis name.** Since this modal only ever shows the *latest*
  analysis/score for a document (not full history — see its own
  docstring), a `Tag value="Latest"` now makes that explicit above both
  the parsed-resume section and the score section, each paired with a
  formatted `completed_at`/`scored_at` ("Analyzed …" / "Scored …"). An
  "Analysis name: {{ analysis_name }}" line sits at the very top of the
  analysis section, above the "Latest" tag.
- **New `components/ai/DocumentAnalysisModal.vue`** — the Document
  Library's own "View AI analysis" action, wired into
  `DocumentDirectoryView.vue`'s row actions (same `pi-sparkles`
  icon-only button, resume-type documents only, as
  `DocumentsPanel.vue`'s). Same overall shape and `load()`/polling logic
  as `ResumeAnalysisModal.vue`, but takes no `jobUrl` prop — a Document
  Library document isn't reached from any one application's detail page,
  so there's no single job to default-score against. Scoring here always
  goes through the same 3-option `application`/`url`/`paste` picker
  `NewAtsScoreDialog.vue` uses (`ApplicationPicker.vue` +
  `SelectButton` + `InputText`/`Textarea`), inlined directly rather than
  the single-button-plus-paste-fallback flow `ResumeAnalysisModal.vue`
  offers — shown immediately when there's no score yet, and again behind
  a "Score again" toggle once one exists, mirroring that same toggle
  mechanics.
- **Renaming `analysis_name`: `EditAnalysisNameDialog.vue` + a row-level
  pencil button in `ResumeAnalysesView.vue`.** A single-field rename
  dialog, same shape as `components/documents/DocumentEditDialog.vue`
  (`file_type`) — PATCHes via a new `resumeAnalyses.updateAnalysisName(id, payload)`
  store action (new `mutationStatus`/`mutationError` state, mirroring
  `stores/documents.ts`'s `updateDocument()`; patches the row in `items`
  in place so the table updates without a refetch). Deliberately **not**
  added to `ResumeAnalysisModal.vue`/`DocumentAnalysisModal.vue` (quick
  "check latest status" popups, not where a user is organizing/comparing
  multiple named analyses) or duplicated into
  `ResumeAnalysisDetailDialog.vue` — one edit surface, in the list view
  where the name actually earns its keep (it's also now what
  `search` filters on). Since `ResumeAnalysesView.vue`'s table already has
  `@row-click` opening the detail dialog, `handleRowClick` gained the same
  `target.closest('a, button')` guard `lib/row-click.ts`'s
  `useApplicationRowClick` uses, so clicking the rename button doesn't
  also pop the detail dialog open underneath it.
- **New table columns**: "Analysis name" on `ResumeAnalysesView.vue`
  (`data.analysis_name`, `TruncatedText` + the rename button above) and
  "Analysis used" on `AtsScoresView.vue` (`data.analysis_name` — the name
  of the resume analysis that score was run against), both reading
  straight off the server-joined field, no client-side lookup.

## What's deliberately not here yet

- RBAC-aware UI — explicitly skipped per current backend scope
- Component/store tests for Applications UI (auth tests exist; application
  views not yet covered) — Contacts, Interviews, Documents, Analytics, and
  AI Tools (including their directory/dashboard views/stores) are in the
  same boat: no tests yet, matching this frontend's existing convention of
  shipping new feature UI without test coverage (only `LoginView`/
  `authGuard`/`api.ts` have any)
- Analytics reporting (CSV/PDF export) — the dashboard itself (charts,
  summary cards) is done; exporting it isn't

## Known gap: the home page (`/`) is still an empty placeholder

`DashboardView.vue` (route `/`, the "Dashboard" nav item — not the same
route as `/analytics`) renders a single static "No applications yet"
card and nothing else; it's never been built out past the original
scaffold. Flagged here rather than fixed as part of the Analytics work,
since it's a distinct piece of scope (a real landing-page design, not
just wiring up data) — noted in TODO.md for whenever there's a pass
dedicated to it.

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
`ContactFormDialog.vue`, `ContactDirectoryView.vue`, `stores/contacts.ts`,
`stores/contactDirectory.ts`), the Interviews UI (`InterviewsPanel.vue`,
`InterviewFormDialog.vue`, `InterviewDirectoryView.vue`,
`stores/interviews.ts`, `stores/interviewDirectory.ts`), the Documents UI
(`DocumentsPanel.vue`, `DocumentDirectoryView.vue`, the three
`components/documents/*Dialog.vue`, `stores/documents.ts`,
`stores/applicationDocuments.ts`), and the AI Tools UI (all of
`components/ai/`, `stores/resumeAnalyses.ts`, `stores/atsScores.ts`) —
worth adding next as the UI stabilises. Same gap applies to the newer
shared utilities (`lib/tooltip.ts`, `lib/row-click.ts`, the
`formatDate`/`formatDateTime` additions to `lib/date-utils.ts`,
`components/common/TruncatedText.vue`).

New devDependency: `@pinia/testing` (store stubbing for component tests).
