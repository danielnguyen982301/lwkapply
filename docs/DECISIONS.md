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
  a DB session, check the JWT, load the user" into composable,
  independently-testable functions; why a FastAPI process has to stay
  stateless behind a load balancer; why `response_model` is a security
  boundary, not just documentation. Full detail, with code citations, in
  [LEARNING_NOTES.md's FastAPI section](LEARNING_NOTES.md#fastapi).

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

- **What building with it actually surfaced:** the difference between an
  ORM's own relationship semantics and the database's own constraints (the
  `IntegrityError` case study), lazy loading hiding N+1 queries, and why
  Alembic's `autogenerate` output still needs a human read-through. Full
  detail in [LEARNING_NOTES.md's SQLAlchemy/Alembic
  section](LEARNING_NOTES.md#sqlalchemy-alembic-postgresql).

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

- **What building with it actually surfaced:** a full comparison of Vue's
  primitives against their React equivalents (`ref`/`useState`,
  `onMounted`/`useEffect`, and so on), grounded in real code in this
  project (`webapp/src/layouts/AppLayout.vue`, the chart theming fix). Full
  detail in [LEARNING_NOTES.md's Vue 3
  section](LEARNING_NOTES.md#vue-3-versus-react).

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

- **What building with it actually surfaced:** how a Riverpod provider
  graph can form a circular dependency that only throws at runtime (fixed
  in commit
  [`c9e24de`](https://github.com/danielnguyen982301/lwkapply/commit/c9e24de100878a643a96008aaa2d2529193aee6a)),
  and how a cold-start deep link can lose a race against the router's own
  redirect (fixed in commit
  [`ac19b4b`](https://github.com/danielnguyen982301/lwkapply/commit/ac19b4bf45756bbc1b0413fa7139a6fb08ff4eff)).
  Full detail, with diagrams, in [LEARNING_NOTES.md's Flutter
  section](LEARNING_NOTES.md#flutter--riverpod-versus-react-native).

---

## Decision 5: Cloudflare R2 for object storage

**Reason:**
- Study purpose
- R2 offers a permanent free tier for a project like this; S3's free tier
  is only for the first 6 months after account creation, then billing
  starts

**Alternatives:**
- AWS S3

Storing uploaded resumes and cover letters in object storage at all
(rather than as BLOB columns in PostgreSQL) wasn't really a live trade-off
weighed from experience — keeping large files out of the relational
database is close to universal advice in backend documentation, closer to
following established practice than an informed comparison made
firsthand. The actual choice worth comparing is which object storage
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

**Note — this project originally used S3, then switched to R2:** the
earliest version of this project's document storage used
`app/services/s3.py` directly. It was migrated to Cloudflare R2 in v0.5.0
(see `CHANGELOG.md` and `backend/BACKEND_SUMMARY.md`'s "A note on the AWS
S3 → Cloudflare R2 migration" section), before S3 ever carried real
production traffic — so it was a client/config swap, not a data
migration. Because R2 implements the same S3-compatible API,
`upload_document`/`delete_document`/`generate_download_url`'s actual logic
never changed; only the client construction (`endpoint_url`,
`region_name="auto"`) and the credential/config names did. The original
`s3.py` is kept in the repo as a reference implementation. The switch
happened for exactly the reason listed above: S3's free tier expires 6
months after account creation, which doesn't fit a study project meant to
keep running indefinitely without turning into a recurring bill, while
R2's free tier has no such expiration.

- **What building it actually surfaced:** `backend/app/services/r2.py`'s
  own design notes — uploads are server-proxied rather than presigned,
  specifically so file size/type can be validated before anything touches
  the bucket; downloads are always short-lived presigned URLs, never a
  permanent public link; object keys are namespaced by
  `user_id`/`application_id` so a misconfigured bucket listing can't
  trivially expose one user's files to another.

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

**Note — this project originally planned to use Resend, then switched to
the Gmail API:** `backend/app/services/email_smtp.py` (kept as the
local-dev/reference implementation, still supporting a `"resend"` provider
mode over HTTP as well as an `"smtp"` mode pointed at MailHog for local
development) was the original plan for production. Two real deployment
blockers surfaced once reminder emails were actually tried against a live
Render deployment (see `backend/BACKEND_SUMMARY.md`'s "Email backend:
Gmail API added alongside SMTP/Resend" section): Render blocks outbound
SMTP-port traffic on free web services, and Resend requires a verified
sending domain this project doesn't have. The fix was
`backend/app/services/email_gmail_api.py`, which
`backend/app/tasks/reminders_inline.py` (the production reminders
pipeline) uses instead — sending over HTTPS, not blocked by Render, and
through Google's own servers, carrying real SPF/DKIM/DMARC authentication
automatically rather than a same-inbox workaround with weaker
deliverability. `backend/app/tasks/reminders_celery.py` (the local-dev/
reference Celery path) is untouched and still uses the original
`email_smtp.py` against MailHog.

---

## Decision 7: Role-based access control

**Reason:**
- Study purpose

**Alternatives:**
- No role distinction (a single kind of user)

**Note:** a premium user-tier role is planned, to gate access to advanced
features — for example, more capable AI features — behind it in the
future. It isn't implemented yet: `UserRole` only has `USER`/`ADMIN` today
(`backend/app/models/user.py:19-21`), and `require_admin` isn't wired into
any actual endpoint either.
