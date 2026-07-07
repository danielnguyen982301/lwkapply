# LwkApply - Job Tracker — Web Frontend

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
- **State**: Pinia `auth` store (`src/stores/auth.ts`) — access/refresh
  tokens held in memory only, never localStorage
- **API client**: `src/lib/api.ts` — Axios instance with bearer-token
  injection and a queued refresh-on-401 interceptor (prevents duplicate
  refresh calls when several requests 401 at once)
- **Screens**: Login, Register, an empty-state Dashboard placeholder, 404

## What's deliberately not here yet

- Applications/Kanban UI, Interviews/Contacts/Documents UI — Phase 2+
- Analytics — Phase 5
- RBAC-aware UI — explicitly skipped per current backend scope
- Persisted sessions across a hard reload — see the comment in
  `src/stores/auth.ts`; fixing this properly means the backend issuing the
  refresh token as an httpOnly cookie instead of a JSON field, which is a
  backend change, not a frontend one
