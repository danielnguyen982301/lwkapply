# LwkApply

A full-stack job application management platform designed to help job seekers organize applications, track interview progress, manage resumes, and gain insights into their job search through analytics and AI-powered features.

**Live:** [https://lwkapply.vercel.app](https://lwkapply.vercel.app)

> Interview-reminder emails currently tend to land in spam — expected
> for a personal study project without its own verified sending
> domain, not a bug. See the Email section under Deployment below for
> why.

## Overview

Job Application Tracker provides a centralized workspace for managing the entire job application lifecycle, from saving opportunities to accepting offers.

The project is built as a modern multi-platform application consisting of:

- Web Application (Vue.js + TypeScript)
- Mobile Application (Flutter)
- REST API Backend (FastAPI)
- PostgreSQL Database
- Cloud File Storage
- AI-Assisted Productivity Features

## Key Features

### Authentication & Security

- User registration and login
- JWT authentication
- Role-based access control (RBAC)
- Password reset workflow

### Application Management

- Create, update, and archive applications
- Kanban-style application pipeline
- Advanced filtering and search
- Status tracking and timelines

### Resume Management

- Resume upload and storage
- Resume version tracking
- Resume parsing and metadata extraction

### Interview Tracking

- Interview scheduling
- Interview feedback and notes
- Contact management

### Analytics

- Application funnel analysis
- Interview conversion rate
- Offer rate tracking
- Job search activity dashboard

### AI Features

- Resume review
- ATS compatibility scoring
- Job description matching
- Cover letter generation
- Interview question generation

## Technology Stack

### Frontend

- Vue 3
- TypeScript
- Pinia
- Vue Router
- Tailwind CSS
- PrimeVue

### Backend

- FastAPI
- SQLAlchemy
- PostgreSQL
- Redis
- Celery

### Mobile

- Flutter
- Riverpod
- Dio

### Infrastructure

- Docker (local dev)
- GitHub Actions (CI/CD)
- Vercel (web frontend)
- Render (backend API)
- Supabase (PostgreSQL)
- Cloudflare R2 (storage)
- Upstash (Redis)
- Gmail API (transactional email)
- cron-job.org (scheduled reminders)

## Deployment

### Environments

- Development
- Production

### Frontend

Platform: Vercel — [https://lwkapply.vercel.app](https://lwkapply.vercel.app)

### Backend

Platform: Render (Docker-based Web Service, using `backend/Dockerfile` as-is)

### Database

Platform: PostgreSQL (Supabase)

### Storage

Platform: Cloudflare R2

### Background jobs / scheduled reminders

Render has no free tier for an always-on background worker, so
production doesn't run Celery for this — see `backend/BACKEND_SUMMARY.md`'s
"Background job execution" section for the full reasoning. Interview
reminders are triggered by [cron-job.org](https://cron-job.org) hitting
a secret-authenticated internal endpoint every 10 minutes. A GitHub
Actions workflow does the same job as a free backup but is currently
disabled — its scheduling turned out to be unreliable in production
(multi-hour gaps with the trigger not firing at all).

### Email

Originally planned to send through Resend (still the local-dev/reference
backend — see `backend/app/services/email_smtp.py`), but Resend — like
most transactional-email providers — requires verifying your own
sending domain before it'll deliver to arbitrary recipients, and this
project doesn't have (or want to pay for) one. Render also blocks
outbound SMTP ports on free web services, closing off a plain SMTP
fallback too. Reminder emails go through the Gmail API instead — free,
no domain required, and still carries Gmail's own authentication since
it's genuinely sent through Google's servers. See
`backend/BACKEND_SUMMARY.md`'s "Email backend" section for the full
story. Because there's no verified domain behind it, these emails
commonly land in spam — expected here, not a bug.

### CI/CD

GitHub Actions

Pipeline:

1. Lint
2. Test
3. Build
4. Deploy

### Monitoring

Not yet set up (error tracking, application logs beyond Render's own,
database monitoring).

## Project Goals

- Build a production-style SaaS application
- Demonstrate full-stack development skills
- Practice system design and architecture
- Explore AI-assisted workflows
- Learn cloud deployment and DevOps practices

## Current Status

In Active Development



See:
- docs/ARCHITECTURE.md
- docs/ROADMAP.md
- TODO.md
