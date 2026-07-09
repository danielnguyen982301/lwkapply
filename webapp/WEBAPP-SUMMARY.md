# Job Tracker — Web Frontend

Vue 3 + TypeScript + Vite + Pinia + Vue Router + Tailwind + PrimeVue, matching
Phase 1 of `docs/ROADMAP.md` (project setup, routing, layout system,
authentication screens).

## What's here (Phase 1)

- **Build tooling**: Vite, TypeScript (strict), path alias `@/` → `src/`
- **Styling**: Tailwind with a small design-token layer (`tailwind.config.js`
  + CSS variables in `src/style.css`) — palette/type choices are documented
  inline as comments in `tailwind.config.js`
- **Routing**: `src/router/index.ts` — two layout branches (`AppLayout` for
  authenticated routes, `AuthLayout` for login/register), lazy-loaded route
  components, a single `beforeEach` guard driven by `route.meta`
- **State**: Pinia `auth` store (`src/stores/auth.ts`) — access token held
  in memory only (never localStorage); refresh token lives in an httpOnly
  cookie the backend sets, so JS never touches it at all
- **API client**: `src/lib/api.ts` — Axios instance with `withCredentials:
  true` (cross-site cookies, since frontend/backend are on different
  domains), bearer-token injection, a double-submit CSRF header echoed
  from the readable `csrf_token` cookie on unsafe requests, and a queued
  refresh-on-401 interceptor (prevents duplicate refresh calls when
  several requests 401 at once)
- **Screens**: Login, Register, an empty-state Dashboard placeholder, 404

## What's deliberately not here yet

- Applications/Kanban UI, Interviews/Contacts/Documents UI — Phase 2+
- Analytics — Phase 5
- RBAC-aware UI — explicitly skipped per current backend scope

## Auth cookie flow (updated)

Sessions now persist across a hard reload: the refresh token lives in an
httpOnly cookie set by the backend, and `Vue Router` calls `authStore.bootstrap()`
before each route if `bootstrapped` flag is `false` (this should only run once when app is mounted since after calling `authStore.bootstrap()`, `bootstrapped` flag is set to `true`), which silently exchanges that cookie for a fresh
access token. See `src/stores/auth.ts`, `src/lib/api.ts` and `src/router/index.ts` for the full
flow, and the `backend/` reference files for the corresponding
backend changes (cookie-setting on login/refresh, CORS with
`allow_credentials`, and a CSRF double-submit check scoped to
`/auth/refresh` and `/auth/logout` only).

## CI

`.github/workflows/webapp-ci.yml` (lives at the **repo root**, not
inside `webapp/` — GitHub only reads workflows from the top-level
`.github/workflows/`) runs on every push/PR touching `webapp/**`:
eslint -> prettier --check -> vue-tsc type-check -> vitest with coverage ->
production build. Mirrors the backend's lint -> format -> test pattern.

Needed alongside it, all added in this pass since they didn't exist yet:
- `eslint.config.js` — flat config (ESLint 9), Vue 3 + TypeScript
- `.prettierrc.json` / `.prettierignore`
- `vite.config.ts` — switched to `vitest/config`'s `defineConfig` and
  added a `test` block (jsdom environment, v8 coverage)
- `src/lib/__tests__/api.spec.ts` — smoke test for `extractErrorMessage`,
  so CI has a real test to run rather than reporting a vacuous "0 tests
  passed"
- `package.json` — split `lint` (CI-safe, no autofix) from a separate
  `lint:fix` (local dev convenience only); the original `lint` script had
  `--fix` baked in, which in CI would have silently modified files in the
  runner instead of failing the build — worth knowing since it's an easy
  trap to reintroduce later. Added `type-check` and `format:check`
  scripts, plus the missing eslint/coverage devDependencies.

`.pre-commit-config.yaml` (repo root, alongside this project)
adds new hooks for eslint and prettier

## UI tests (added)

Two real component/logic tests beyond the pure-function `api.spec.ts`
smoke test:

- `src/router/__tests__/authGuard.spec.ts` — the redirect logic itself
  was pulled out of `router.beforeEach` into an exported `authGuard()`
  function specifically so it's testable without a full router instance
- `src/views/auth/__tests__/LoginView.spec.ts` — mounts the real
  component with `@vue/test-utils` + `createTestingPinia` (stubs the
  `auth` store's actions so nothing hits real network) + a minimal test
  router; covers empty-submit validation, successful login + redirect-
  to-intended-page, and the error-message path

**Deliberately not tested yet**: `DashboardView`, `NotFoundView`,
`AppLayout`/`AuthLayout` — placeholder or markup-only content that Phase
2 will substantially rewrite. Testing them now would mean testing code
guaranteed to be replaced.

New devDependency: `@pinia/testing` (store stubbing for component tests).
