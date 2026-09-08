# LwkApply

A full-stack job application management platform designed to help job seekers organize applications, track interview progress, manage resumes, and gain insights into their job search through analytics and AI-powered features.

**Live:** [https://lwkapply.vercel.app](https://lwkapply.vercel.app)

> Emails sent by the app — interview reminders, password-reset links,
> anything else — currently tend to land in spam — expected for a
> personal study project without its own verified sending domain, not
> a bug. See the Email section under Deployment below for why.

## Study Notes

A section of what I learned from this project.
Full notes are in [docs/STUDY_NOTES.md](docs/STUDY_NOTES.md): the core
concepts and important notes of each technology (FastAPI, SQLAlchemy/Alembic,
Celery, Vue, Flutter/Riverpod), problems and fixes.

## Overview

LwkApply provides a centralized workspace for managing the entire job application lifecycle, from saving opportunities to accepting offers.

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

## Browser Extension

**LwkApply Quick Capture** auto-syncs your VietnamWorks job-application
activity into LwkApply — Save, Unsave, and Apply on VietnamWorks are
detected automatically and mirrored as an application in your LwkApply
account, keyed by VietnamWorks' own job id rather than the page URL.
It also supports capturing any job posting manually, on VietnamWorks
or elsewhere.

Source: [`extension/`](extension). It's self-distributed rather than
listed on addons.mozilla.org (see `extension/scripts/package.sh` for
how the submission build is put together) — Mozilla still signs it,
so it installs normally in release Firefox, it's just not searchable
in the store.

### Installing on Firefox

1. Go to the [Releases page](https://github.com/danielnguyen982301/lwkapply/releases/latest)
   and download the `.xpi` file attached to the latest release.

   <!-- screenshot: the Releases page with the .xpi asset visible -->

2. Open the downloaded file. Firefox will show an install prompt
   listing the permissions the extension requests and the categories
   of data it collects (login credentials, and the job-posting/
   application data it reads from VietnamWorks — see the
   [privacy policy](https://lwkapply.vercel.app/privacy) for detail).

   <!-- screenshot: Firefox's "Add extension?" prompt -->

3. Click **Add Extension**. Firefox confirms it was added and offers
   to pin its icon to the toolbar — do that for easy access.

   <!-- screenshot: "Added to Firefox" confirmation -->

4. Click the toolbar icon and log in with your LwkApply account.

   <!-- screenshot: the popup's login form -->

5. Open any VietnamWorks job posting and click **Save** or **Apply**
   as you normally would. LwkApply Quick Capture picks this up
   automatically and shows a toast confirming the application was
   synced — no extra clicks needed.

   <!-- screenshot: the "Saved to LwkApply" toast on a VietnamWorks
        job posting -->

To capture a job manually instead (any site, or a VietnamWorks
posting you don't want auto-tracked), click the toolbar icon and
switch to the popup's **Manual** tab.

> The screenshot placeholders above are intentional — they mark where
> real screenshots from an actual install/usage run should go, rather
> than fabricated ones. Drop the images in `docs/images/` (e.g.
> `firefox-install-prompt.png`) and swap each comment for
> `![alt text](docs/images/filename.png)`.

### Installing on Chrome

Coming soon — pending Chrome Web Store developer registration.

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
fallback too. Every transactional email the app sends — interview
reminders and password-reset confirmation links alike — goes through
the Gmail API instead (`backend/app/services/password_reset.py` for
resets, `backend/app/tasks/reminders_inline.py` for reminders): free,
no domain required, and still carries Gmail's own authentication since
it's genuinely sent through Google's servers. See
`backend/BACKEND_SUMMARY.md`'s "Email backend" section for the full
story. Because there's no verified domain behind it, all of these
emails commonly land in spam — expected here, not a bug. If you're
testing password reset yourself, check spam before assuming the send
failed.

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
- [docs/DECISIONS.md](docs/DECISIONS.md)
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- [docs/ROADMAP.md](docs/ROADMAP.md)
- [TODO.md](TODO.md)
