# AI_CONTEXT.md

## Purpose

This repository contains a full-stack Job Application Tracker platform that helps users manage job applications, resumes, interviews, contacts, documents, and job-search analytics.

The project serves both as a production-style SaaS application and a learning platform for:

- Full-stack engineering
- System design
- Cloud deployment
- DevOps workflows
- AI-assisted productivity features

AI assistants working on this repository should preserve architectural consistency, prioritize maintainability, and align new work with the roadmap and existing implementation summaries.

---

# Source of Truth

When determining current project status:

1. `BACKEND_SUMMARY.md` = backend implementation status
2. `WEBAPP_SUMMARY.md` = web app implementation status
3. `TODO.md` = high-level task tracking
4. `ROADMAP.md` = long-term feature planning
5. `ARCHITECTURE.md` = intended architecture

If documentation conflicts:

- Trust implementation summaries first.
- Trust actual code over documentation.
- Treat roadmap items as planned, not implemented.

---

# Product Overview

The platform manages the full job application lifecycle:

- User registration and authentication
- Application tracking
- Resume and document management
- Interview scheduling and notes
- Contact management
- Analytics and reporting
- AI-assisted job-search tools

Primary user type:

- Individual job seekers

Potential future expansion:

- Premium subscriptions
- Multi-tenant SaaS architecture
- Administrative tooling

---

# System Architecture

## High-Level Design

```text
Web Application (Vue 3)
         |
         v
     FastAPI API
         |
  -----------------
  |       |       |
  v       v       v
Postgres Redis    R2
```

### Clients

#### Web Application

Stack:

- Vue 3
- TypeScript
- Pinia
- Vue Router
- PrimeVue
- Tailwind CSS

Responsibilities:

- User interface
- State management
- Forms
- Application workflows
- Analytics visualization

#### Mobile Application

Planned stack:

- Flutter
- Riverpod
- Dio

Responsibilities:

- Application management
- Notifications
- Offline access

Mobile is planned but not yet considered a primary implementation target.

---

# Backend Architecture

Stack:

- FastAPI
- SQLAlchemy
- PostgreSQL
- Redis
- Celery

Responsibilities:

- Authentication
- Authorization
- Business logic
- Validation
- File handling
- AI integrations

Preferred architectural separation:

```text
API Layer
    |
Service Layer
    |
Repository/Data Layer
    |
Database
```

Backend code should remain business-logic-centric and avoid leaking database concerns into API routes.

---

# Database Model

Primary database:

- PostgreSQL

Core entities:

## Users

Stores:

- Identity
- Authentication
- Role information

Key fields:

- id
- email
- password_hash
- role

---

## Applications

Represents a job application.

Key fields:

- company
- position
- location
- status
- salary range
- application date
- notes

---

## Interviews

Associated with applications.

Stores:

- Interview type
- Schedule
- Feedback
- Outcome

---

## Documents

Stores metadata for uploaded files.

Examples:

- Resumes
- Cover letters
- Attachments

Actual file storage is external (Cloudflare R2).

---

## Contacts

People associated with an application.

Examples:

- Recruiters
- Hiring managers
- Interviewers

---

# Entity Relationships

```text
User
 |
 +-- Applications
        |
        +-- Interviews
        |
        +-- Documents
        |
        +-- Contacts
```

Ownership should always be enforced through user/application relationships.

---

# Authentication & Authorization

Authentication model:

- JWT access tokens
- Refresh tokens

Current implementation notes from TODO:

- Refresh token flow exists
- httpOnly cookie refresh token
- CSRF double-submit protection on refresh/logout

Security expectations:

- Never store plaintext passwords
- Use bcrypt hashing
- Validate all JWTs
- Protect authenticated routes
- Enforce ownership checks

---

# RBAC

Roles:

- User
- Premium User
- Admin

Future features should consider RBAC requirements from the beginning.

Do not hardcode assumptions that all authenticated users are identical.

---

# File Storage

Provider:

- Cloudflare R2 (migrated from AWS S3 in v0.5.0, before S3 ever carried
  real traffic — no AWS account is used or required; R2's S3-compatible
  API means `boto3` is still the client library, just pointed at R2's
  endpoint with R2 credentials. See BACKEND_SUMMARY.md /
  `app/services/r2.py` for details.)

Documents should not be stored directly in PostgreSQL.

Current approach:

- Server-mediated uploads

Future consideration:

- Direct presigned uploads to R2 if scaling requires it

---

# Background Processing

Technologies:

- Celery
- Redis

Intended uses:

- Resume parsing
- Analytics generation
- Email notifications
- AI processing

Heavy or long-running operations should be delegated to background jobs whenever practical.

---

# Frontend Conventions

Current web stack:

- Vue 3
- TypeScript
- Pinia
- Vue Router
- PrimeVue
- Tailwind CSS

Existing implementation includes:

- Authentication screens
- Protected routes
- Router guards
- Typed API client
- Token refresh handling

When adding features:

- Prefer strongly typed APIs
- Keep business logic out of views
- Centralize API interactions
- Use Pinia for shared state
- Use composables when appropriate

---

# Testing Expectations

Backend:

- pytest

Frontend:

- Vitest
- Vue Test Utils

End-to-end:

- Playwright (planned)

Project goal:

- 80%+ coverage

New backend features should include:

- Schema tests
- Service tests
- Endpoint tests

New frontend features should include:

- Component tests
- State-management tests
- Routing tests where relevant

---

# Deployment Architecture

Frontend:

- Vercel

Backend:

- Railway or Render

Database:

- PostgreSQL (Supabase)

Storage:

- Cloudflare R2

CI/CD:

- GitHub Actions

Pipeline philosophy:

1. Lint
2. Test
3. Build
4. Deploy

Changes should preserve automated deployment compatibility.

---

# Security Requirements

Always maintain:

- JWT authentication
- RBAC enforcement
- Input validation
- Rate limiting
- Secure CORS configuration
- Secure file uploads

Never:

- Commit secrets
- Store credentials in code
- Disable authentication checks for convenience

Configuration belongs in environment variables.

---

# AI Features Roadmap

Planned capabilities:

- Resume review
- ATS scoring
- Resume parsing
- Job matching
- Cover letter generation
- Interview question generation

AI functionality should be designed as modular services rather than deeply coupling AI logic into core CRUD workflows.

Future AI integrations may become separate services.

---

# Roadmap Priorities

Development phases:

1. Foundation
2. Application Tracking
3. Resume Management
4. Interview Management
5. Analytics
6. Mobile
7. AI Features
8. Production Readiness

When proposing work:

- Prioritize unfinished items from TODO.
- Respect roadmap ordering unless implementation summaries indicate otherwise.
- Avoid introducing large architectural changes without clear justification.

---

# Current Project Reality

The roadmap describes the target product.

The actual implementation status is maintained separately.

Before modifying code:

1. Read `BACKEND_SUMMARY.md`.
2. Read `WEBAPP_SUMMARY.md`.
3. Read `TODO.md`.
4. Inspect the actual code.

Do not assume a roadmap feature already exists.

---

# Guidance for Future AI Agents

When making changes:

- Prefer incremental improvements.
- Maintain existing architecture.
- Preserve type safety.
- Preserve security controls.
- Add tests alongside new functionality.
- Update documentation when behavior changes.

Before implementing a feature:

1. Verify current implementation status.
2. Identify affected layers (frontend, backend, database, storage).
3. Consider RBAC implications.
4. Consider testing requirements.
5. Consider deployment impact.

Success is measured by consistency, maintainability, and alignment with the existing architecture rather than introducing novel patterns.
