# Changelog

## v0.3.0 (in progress)

### Added

- Interview endpoints: full CRUD, nested under `/applications/{id}/interviews`
- Contact endpoints: full CRUD, nested under `/applications/{id}/contacts`
- Document endpoints: multipart upload to S3, list, get metadata, presigned
  download URLs, update (`file_type`), delete — nested under
  `/applications/{id}/documents`
- `app/services/s3.py`: upload/delete/presigned-download helpers, with
  content-type validation and chunked size-limit enforcement
- Unit tests for Interview, Contact, and Document schemas
- Initial Alembic migration (`0001`), generated from models against a real
  Postgres instance

### Fixed

- Two enum columns (`interviews.result`, `documents.file_type`) were
  missing `nullable=False` in an earlier hand-drafted version of the
  initial migration; resolved by regenerating the migration via
  `alembic revision --autogenerate` directly from the models instead of
  hand-authoring it

### Changed

- All ownership checks for Interview/Contact/Document resources join
  through `Application.user_id`, matching the IDOR-prevention pattern
  already used by the Applications endpoints

## v0.2.0

### Added

- FastAPI backend project structure (`backend/app/...`)
- SQLAlchemy models: User, Application, Interview, Document, Contact
- Alembic migrations wired up
- JWT auth: register, login, refresh, password reset request/confirm, `/me`
- Application CRUD API with pagination, status filter, and search
- Docker Compose for local dev (API + Postgres + Redis)
- Unit tests for security, application schema and user schema.

## v0.1.0

### Added

- Documentation
- Architecture planning

## Upcoming

- Frontend (Vue) project scaffold — next up
- Analytics endpoints
- Kanban Board (frontend)
- Celery tasks (resume parsing, email sending, AI processing)
- RBAC beyond a `role` column