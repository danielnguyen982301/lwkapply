# Engineering Decisions

---

## Decision 1: FastAPI as the backend framework

**Reason:**
- Study purpose

**Alternatives:**
- Node.js
- Ruby on Rails

**Trade-offs:**

| Aspect | FastAPI (Python) | Node.js | Ruby on Rails |
|---|---|---|---|
| Language | Python | JavaScript/TypeScript — same as the frontend | Ruby — not shared with the rest of the stack |
| Type safety | Built in, via type hints + Pydantic | Needs TypeScript layered on top | Optional, less central than in Python/TS |
| Batteries included | No — validation, DB session, and auth wired by hand via `Depends()` | Depends on the framework: Express is minimal; Nest.js is structured, with built-in DI | Yes — ships an ORM, generators, and scaffolding |
| Concurrency model | Async by choice (`def` vs `async def`) — easy to get wrong | Async by default — single-threaded event loop | Traditionally synchronous, worker-per-request |
| Auto-generated API docs | Built in — OpenAPI from type hints | Needs a separate library | Needs a separate gem |
| Fit for this project's AI features | Strong — Python's AI/ML ecosystem is dominant | Weaker — a secondary ecosystem | Weakest — little AI/ML presence |

- **What building with it actually surfaced:** how `Depends()` turns "get
  a DB session, check the JWT, load the user" into small, testable
  functions; why a FastAPI process has to stay stateless behind a load
  balancer; why `response_model` is a security boundary, not just docs.
  Full detail in [STUDY_NOTES.md's FastAPI section](STUDY_NOTES.md#fastapi).

---

## Decision 2: PostgreSQL as the primary database

**Reason:**
- Study purpose

**Alternatives:**
- MongoDB

**Trade-offs:**

| Aspect | PostgreSQL | MongoDB |
|---|---|---|
| Data model | Relational — tables linked by foreign keys | Document-based — JSON-like, often embedded |
| Schema enforcement | Enforced at the database level | Schema-less by default; validation is optional |
| Relationships | Native joins, resolved by the database | No native joins — embedded or resolved in app code |
| Migrations | Explicit, versioned scripts (Alembic) | No formal migrations — shape can drift silently |
| Fit for this project's data | Strong — this data is naturally relational | Weaker — would let relational modeling be skipped |

- **What building with it actually surfaced:** an ORM's relationship
  rules aren't the same as the database's own constraints (the
  `IntegrityError` case study), lazy loading can hide N+1 queries, and
  Alembic's `autogenerate` output still needs a human read-through, not
  blind trust. Full detail in [STUDY_NOTES.md's SQLAlchemy/Alembic
  section](STUDY_NOTES.md#sqlalchemy-alembic-postgresql).

---

## Decision 3: Vue 3 with TypeScript for the web app

**Reason:**
- Study purpose

**Alternatives:**
- React
- Angular

**Trade-offs:**

| Aspect | Vue | React | Angular |
|---|---|---|---|
| Reactivity model | Compiler-informed — automatic dependency tracking | Re-renders on every state change; opt out via `memo`/`useCallback`/`useMemo` | Change detection (Zone.js, or signals in newer versions) |
| Markup | Templates — HTML-like | JSX — full JavaScript expressiveness | Templates, with Angular-specific directives |
| Structure/opinionation | Batteries-included for routing/state (Vue Router, Pinia) | Unopinionated — pick your own router/state library | Highly opinionated — modules, DI, structure all baked in |
| Learning curve | Gentler | Steeper — hooks rules, dependency arrays | Steepest — modules, DI, reactive concepts up front |
| Ecosystem | Smaller | Largest of the three | Solid, but smaller than React's |
| Fit for this project | Chosen — an approachable first deep framework | Would add hooks, JSX, and a library choice on top | Would add much more up-front surface area |

- **What building with it actually surfaced:** how Vue's primitives map
  onto their React equivalents (`ref`/`useState`, `onMounted`/
  `useEffect`, etc.), grounded in real code here
  (`webapp/src/layouts/AppLayout.vue`, the chart theming fix). Full
  detail in [STUDY_NOTES.md's Vue 3 section](STUDY_NOTES.md#vue-3-versus-react).

---

## Decision 4: Flutter with Riverpod for the mobile app

**Reason:**
- Study purpose

**Alternatives:**
- React Native

**Trade-offs:**

| Aspect | Flutter | React Native |
|---|---|---|
| Rendering approach | Draws every pixel itself (Skia, or the newer Impeller) | Bridges to real native platform widgets |
| UI consistency | Pixel-identical across iOS and Android | Feels more natively "correct," but can differ subtly per platform |
| Language | Dart — not shared with the rest of this stack | JavaScript/TypeScript — same as the Vue web frontend |
| Native integration overhead | No bridge — compiles directly to native machine code | Crosses a JS-to-native bridge (or the newer JSI) |
| Widget/component source | Reimplements native look-and-feel itself | Gets real native components for free |
| Fit for this project | Chosen — Riverpod's DI model mirrors FastAPI's `Depends()` | Would mean learning React first, on top of mobile concepts |

- **What building with it actually surfaced:** a Riverpod provider graph
  can form a circular dependency that only throws at runtime (fixed
  in commit
  [`c9e24de`](https://github.com/danielnguyen982301/lwkapply/commit/c9e24de100878a643a96008aaa2d2529193aee6a)),
  and how a cold-start deep link can lose a race against the router's own
  redirect (fixed in commit
  [`ac19b4b`](https://github.com/danielnguyen982301/lwkapply/commit/ac19b4bf45756bbc1b0413fa7139a6fb08ff4eff)).
  Full detail, with diagrams, in [STUDY_NOTES.md's Flutter
  section](STUDY_NOTES.md#flutter--riverpod-versus-react-native).

---

## Decision 5: Cloudflare R2 for object storage

**Reason:**
- Study purpose
- R2 offers a permanent free tier for a project like this; S3's free tier
  is only for the first 6 months after account creation, then billing
  starts

**Alternatives:**
- AWS S3

Keeping large files out of PostgreSQL entirely (rather than BLOB
columns) wasn't really a decision weighed from experience — that's
close to universal backend advice, more "follow best practice" than an
informed comparison. The real choice was which object storage
provider.

**Trade-offs:**

| Aspect | Cloudflare R2 | AWS S3 |
|---|---|---|
| Free tier | Permanent | Free for 6 months, then billed |
| API compatibility | Implements the S3 API directly | The original API |
| Egress fees | None | Charged for outbound data transfer |
| Regions | None — `region_name="auto"` is a required literal | Region-based |
| Vendor relationship | No AWS account or IAM keys needed | Requires an AWS account and IAM credentials |
| Ecosystem/tooling | Smaller, but interoperates via the same S3-compatible client | Much larger — the default in most tutorials |

**Note — this project actually started on S3, then switched to R2:**
the earliest version used `app/services/s3.py` directly, migrated to
R2 in v0.5.0 (see `CHANGELOG.md` and `backend/BACKEND_SUMMARY.md`'s "A
note on the AWS S3 → Cloudflare R2 migration") before S3 ever carried
real traffic — a client/config swap, not a data migration. Same
S3-compatible API underneath, so
`upload_document`/`delete_document`/`generate_download_url`'s logic
never changed, only the client construction (`endpoint_url`,
`region_name="auto"`) and credential names. `s3.py` is still in the
repo as a reference. The switch was for exactly the reason in the
Reason section above: S3's free tier expires after 6 months, R2's
doesn't.

- **What building it actually surfaced:** uploads are server-proxied
  rather than presigned, so file size/type can be validated before
  anything touches the bucket; downloads are always short-lived
  presigned URLs, never a permanent public link; object keys are
  namespaced by `user_id`/`application_id` so a misconfigured bucket
  listing can't expose one user's files to another. See
  `backend/app/services/r2.py`'s own notes.

---

## Decision 6: Gmail API for transactional email in production

**Reason:**
- Study purpose

**Alternatives:**
- Resend

**Trade-offs:**

| Aspect | Gmail API | Resend |
|---|---|---|
| Works on Render's free tier | Yes — sends over HTTPS | No — Render blocks outbound SMTP ports on free web services |
| Domain requirement | None | Requires a verified sending domain this project doesn't have |
| Deliverability/authentication | Google's own SPF/DKIM/DMARC, automatically | Needs domain authentication for reliable delivery |
| Cost | Free, via an existing Gmail account | Has a free tier, but gated behind domain verification |
| Auth model | OAuth 2.0, a long-lived refresh token | An API key sent with each call |
| Real-world result | Works, but lands in spam without a verified domain — known, documented, not a bug | Not usable here in production, for the two reasons above |

**Note — planned to use Resend, switched to the Gmail API:**
`backend/app/services/email_smtp.py` (kept as the local-dev/reference
implementation, still supports a `"resend"` mode plus an `"smtp"` mode
for local MailHog) was the original production plan. Two real
deployment blockers killed it once actually tried against a live
Render deployment (see `backend/BACKEND_SUMMARY.md`'s "Email backend:
Gmail API added alongside SMTP/Resend"): Render blocks outbound SMTP
ports on free web services, and Resend needs a verified sending domain
this project doesn't have. Fixed with
`backend/app/services/email_gmail_api.py`, used by
`backend/app/tasks/reminders_inline.py` (the production path) instead —
sends over HTTPS, so Render doesn't block it, and through Google's own
servers, so it carries real SPF/DKIM/DMARC automatically instead of a
weaker same-inbox workaround. `backend/app/tasks/reminders_celery.py`
(local-dev Celery path) is untouched, still on `email_smtp.py` +
MailHog.

---

## Decision 7: Role-based access control

**Reason:**
- Study purpose

**Alternatives:**
- No role distinction (a single kind of user)

**Note:** a premium role is planned, to gate more advanced features
(better AI features, say) behind it eventually. Not implemented yet —
`UserRole` only has `USER`/`ADMIN` today
(`backend/app/models/user.py:19-21`), and `require_admin` isn't wired
into any endpoint.

---

## Decision 8: a browser extension to sync applications from other job boards

**Reason:**
- Let users track applications they make on external job boards (starting
  with VietnamWorks, a Vietnamese job board) without retyping them into
  LwkApply by hand
- Needed something that could react to a Save/Apply action as it happens,
  without needing the job board's cooperation (no public API) and without
  ever holding the user's credentials for that other site

**Alternatives:**
- Direct API integration with the job board
- A userscript (Tampermonkey/Greasemonkey)
- A bookmarklet
- Server-side polling with the user's job-board credentials stored
- Parsing job-board notification emails (via a forwarding rule)

**Trade-offs:**

| Aspect | Browser extension | Direct API integration | Userscript | Bookmarklet | Server-side polling (stored credentials) | Email parsing |
|---|---|---|---|---|---|---|
| Credential handling | None — rides the user's own already-authenticated browser session; the job board's session never touches LwkApply's server | An official API key/OAuth grant, scoped and revocable by the job board itself | Same as the extension | Same as the extension | Requires storing the user's job-board password or session server-side | None, but depends on inbox/forwarding-rule access instead |
| Reacts automatically | Yes — `chrome.webRequest` observes the site's own network requests for Save/Apply as they happen | Yes — a webhook, or a clean poll against a real endpoint meant for this | Limited — only page-injected JS, no privileged request-observation API, so some request types are unreliable to intercept | No — a one-shot script the user must click every single time; no background observation at all | Yes, but only on a polling interval, not instantly | No — dependent on whether, and when, an email actually shows up |
| Correctness | High — reads the same real network requests the site's own UI already triggers, not a scrape/guess | Highest — a real, documented contract, not inferred from traffic | Comparable in principle, but weaker interception guarantees for non-fetch/XHR requests | N/A | Only as good as whatever gets scraped from the polled pages | Low — not every relevant email even comes from the job board's own domain (a recruiter can email directly, bypassing any forwarding rule), and there's no equivalent mechanism at all for a user who isn't on Gmail |
| Distribution | Store review (Firefox AMO / Chrome Web Store), or self-distribution | N/A — a backend integration, nothing for the user to install | No store review — shared as a plain script | Simplest possible — just a bookmark, but has to be re-added per browser/device | N/A — a server-side job, nothing for the user to install | N/A — a mail rule, not installed software |
| Ethical/ToS risk | Low — acts only inside the user's own session; nothing is done on the user's behalf without them being present in the browser | None — this is the sanctioned integration path | Same as the extension | Same as the extension | High — automated, credentialed access to another site on the user's behalf is very likely a ToS violation regardless of intent, and any anti-bot/CAPTCHA measure would either block it or have to be deliberately bypassed, which this project won't do | Low risk, but doesn't reliably solve the actual problem |
| Manual-capture UI | Yes — a toolbar popup, reused for capturing jobs from any other site too | No | Possible, but typically minimal | None | None | None |
| Actually available here | Yes | **No** — VietnamWorks exposes no public API to integrate against, and even where a job board does have one, getting approved for it, and building/maintaining a separate integration per board, is realistically more scope than a personal study project should take on | Yes | Yes | Yes (technically) | Yes |

Direct API integration would honestly be the *correct* way to do this
— a real, sanctioned contract instead of quietly depending on a
private site's undocumented request shapes. It's not listed above as
"worse on some axis" — it's **not an option at all** for VietnamWorks
(no public API), and building/maintaining a separate integration per
job board in general is more scope than a study project should take
on. The extension is the best *available* option, not the best option
in the abstract.

Server-side polling and CAPTCHA-bypassing got ruled out on ethical
grounds before weighing them on any axis above — storing a third
party's credentials server-side, or defeating its anti-bot measures,
isn't something this project will do, even where it'd technically be
easier (polling doesn't even need the user's browser open). Different
kind of "no" than losing a trade-off.

- **What building it actually surfaced:** identity was the real
  problem, not the network interception. The first version keyed a
  tracked job by its page URL, which broke the moment the same posting
  showed up through a different referral link (VietnamWorks appends a
  varying `?source=...` query string). Switched to the job board's own
  internal id (`Application.external_id`) instead, which needed three
  new idempotent backend endpoints so Save/Apply/Unsave could each be
  upsert-safe against a retry or a race. Getting it working on Firefox
  too surfaced two more gaps Chrome alone never showed: Firefox
  enforces real CORS against extension origins where Chrome exempts
  them entirely, and Firefox randomizes its own extension origin per
  install, so a static CORS allowlist can't work at all. Full detail
  in `backend/BACKEND_SUMMARY.md`'s "Salary currency, application
  source, and the browser extension" and the README's "Browser
  Extension" section.
