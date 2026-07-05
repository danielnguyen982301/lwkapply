# Changelog

## v0.2.0 (in progress)

### Added

- FastAPI backend project structure (`backend/app/...`)
- SQLAlchemy models: User, Application, Interview, Document, Contact
- Alembic migrations wired up (no migration generated yet — run
  `alembic revision --autogenerate` after setting up the DB)
- JWT auth: register, login, refresh, password reset request/confirm, `/me`
- Application CRUD API with pagination, status filter, and search
- Docker Compose for local dev (API + Postgres + Redis)
- Unit tests for security, application schema and user schema.

## v0.1.0

### Added

- Documentation
- Architecture planning

## Upcoming

- Interview / Document / Contact endpoints
- S3 resume upload
- Frontend (Vue) project scaffold
- Analytics endpoints
- Kanban Board (frontend)