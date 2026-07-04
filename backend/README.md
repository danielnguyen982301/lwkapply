# Backend — Job Application Tracker API

FastAPI + SQLAlchemy + PostgreSQL backend implementing Phase 1 (Foundation)
and the start of Phase 2 (Application Tracking) from the project roadmap.

## What's implemented

- **Auth**: register, login (JWT access + refresh tokens), token refresh,
  password reset (request/confirm), `GET /me`
- **Applications**: full CRUD, pagination, status filter, company/position
  search — all scoped to the authenticated user
- **Models**: User, Application, Interview, Document, Contact (matches
  `docs/DATABASE.md`)
- **Infra**: Alembic migrations wired up, Docker Compose (API + Postgres + Redis)

## Not yet implemented (next up per TODO.md)

- Interviews / Documents / Contacts endpoints (models exist, routers don't yet)
- S3 upload integration for documents
- Analytics endpoints
- Celery tasks (resume parsing, email sending, AI processing)
- RBAC beyond a `role` column (no admin endpoints protected yet)

## Local development

### Option A — Docker Compose (recommended)

```bash
cp backend/.env.example backend/.env
docker compose up --build
```

API will be live at http://localhost:8000, interactive docs at
http://localhost:8000/docs.

Then, in another terminal, run the initial migration:

```bash
docker compose exec api alembic upgrade head
```

### Option B — Local Python env

```bash
cd backend
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # then edit DATABASE_URL to point at your local Postgres
alembic revision --autogenerate -m "initial schema"
alembic upgrade head
uvicorn app.main:app --reload
```

## Creating the first migration

The models are already defined, but no migration exists yet. Generate one:

```bash
alembic revision --autogenerate -m "initial schema"
alembic upgrade head
```

## Project structure

```
backend/
  app/
    api/v1/endpoints/   # route handlers (auth, applications, ...)
    core/               # config, security (JWT, password hashing)
    db/                 # engine/session, declarative base
    models/             # SQLAlchemy ORM models
    schemas/            # Pydantic request/response models
    services/           # business logic (empty — next to fill in)
    main.py             # FastAPI app + router registration
  alembic/              # migrations
  requirements.txt
  Dockerfile
```

## Security notes for reviewers

- Passwords hashed with bcrypt (via passlib), never stored/logged in plaintext.
- JWTs are typed (`access` / `refresh` / `password_reset`) so a stolen
  refresh token can't be replayed as an access token, etc.
- `password-reset/request` always returns the same response regardless of
  whether the email exists, to prevent user enumeration.
- All application queries filter by `user_id` at the DB layer (not just
  hidden in the response) to prevent IDOR (one user reading/editing another
  user's data by guessing an ID).
- `SECRET_KEY` and DB credentials are read from environment variables only —
  never commit a real `.env` file (it's git-ignored).
