# Database Design

## Overview

The application uses PostgreSQL as the primary relational database.

## Core Tables

### users

- id (UUID)
- email
- password_hash
- first_name
- last_name
- avatar_url
- role (user/admin)
- is_active
- timezone (nullable IANA name), timezone_is_manual (true once the user
  picks one, so auto-detection stops overwriting it)
- token_version (bumped to invalidate previously issued JWTs)
- created_at
- updated_at

### applications

- id (UUID)
- user_id
- company
- position
- application_name (optional — user-chosen label to tell apart
  applications to the same company/position, e.g. a re-apply after
  rejection)
- location
- source (nullable — where the application came from, e.g. the browser
  extension's site name)
- external_id (nullable — the source's own job id; unique per
  `(user_id, source, external_id)` when both are set, so a sync from the
  extension can't create duplicates)
- status (saved/applied/phone_screen/interviewing/offer/rejected/
  withdrawn/accepted)
- salary_min
- salary_max
- salary_currency (ISO 4217 code, default `USD`)
- applied_date
- job_url
- notes

### interviews

- id (UUID)
- application_id
- type
- scheduled_at
- duration_minutes
- feedback
- result

### documents (backend/BACKEND_SUMMARY.md — "A note on Document / ApplicationDocument")

- id (UUID)
- user_id — direct FK; a document is a top-level, user-owned resource,
  **no longer** tied to a single application (`application_id` was
  dropped — see `application_documents` below)
- file_name
- file_url
- file_type

### application_documents (AI features rework — backend/BACKEND_SUMMARY.md)

Many-to-many join between `applications` and `documents` — a document
can be attached to zero, one, or several applications (e.g. one base
resume reused across many job postings). Replaces the old
`documents.application_id` single-owner FK.

- id (UUID)
- application_id
- document_id
- created_at / updated_at

Deleting an application only removes the join rows here; the document
itself is untouched. Deleting a document cascades its join rows (and its
`resume_analyses`/`ats_scores`, unchanged).

### application_status_history

Append-only log of `applications.status` transitions. Not read by any
analytics yet — those query the current status directly.

- id (UUID)
- application_id
- from_status (nullable — null for the first row)
- to_status
- created_at (the transition time; rows are never updated)

### interview_reminders

One row per (interview, lead time, channel).

- id (UUID)
- interview_id
- remind_at
- sent_at (nullable — stamped once sent; the idempotency guard)
- channel (email/push/in_app)

### contacts

A top-level, user-owned resource, like `documents`, no longer tied to a
single application.

- id (UUID)
- user_id — direct FK (`application_id` was dropped)
- name
- title
- email
- linkedin_url

### application_contacts

Many-to-many join between `applications` and `contacts`, mirroring
`application_documents`. Unique on `(application_id, contact_id)`.
Deleting an application only removes its join rows; the contact
itself is untouched.

- id (UUID)
- application_id
- contact_id
- created_at / updated_at

### user_settings

1:1 with `users`; created at registration.

- id (UUID)
- user_id (unique)
- reminder_lead_hours (nullable)
- notifications_enabled
- email_notifications_enabled
- push_notifications_enabled

### notifications

In-app notification feed (the bell icon).

- id (UUID)
- user_id
- type (currently only `interview_reminder`)
- title
- body
- application_id (nullable)
- interview_id (nullable)
- read_at (nullable — null means unread)

### device_tokens

Push-notification (FCM) device registrations.

- id (UUID)
- user_id
- platform (android/ios)
- token (globally unique; reassigned to a new user on re-login)
- last_seen_at

### resume_analyses (AI features — backend/BACKEND_SUMMARY.md)

- id (UUID)
- user_id — direct FK, not nested under an application (see backend summary)
- document_id
- status (pending/processing/completed/failed)
- raw_text
- parsed_data (JSONB)
- error_message
- completed_at (nullable — set only when status transitions to
  `completed`; distinct from `created_at` since parsing is async)
- analysis_name (nullable — auto-generated in the same commit as
  `completed_at`: slugified `documents.file_name` + completion timestamp
  + a random suffix, e.g. `resume_20260817_143205_a1b2c3`. Not
  DB-unique — user-editable afterward via `PATCH /ai/resume-analyses/{id}`)

### ats_scores (AI features — backend/BACKEND_SUMMARY.md)

- id (UUID)
- user_id — direct FK, same reasoning as resume_analyses
- resume_analysis_id
- job_description
- job_description_source (pasted/url)
- job_url (nullable — the pasted URL when `job_description_source="url"`;
  `score_ats_task` fetches and backfills `job_description` from this)
- status (pending/processing/completed/failed)
- score
- feedback (JSONB)
- error_message
- scored_at (nullable — same shape as resume_analyses.completed_at, set
  only when status transitions to `completed`)

**No `application_id`.** Originally had one (nullable, mirroring
`documents.application_id`), dropped in the same pass as
`documents.application_id` — nothing ever cross-checked it against the
resume's actual application, and the pasted `job_description`/`job_url`
content is caller-supplied and unverifiable either way, so the link only
ever looked trustworthy without actually being enforceable. See
`backend/BACKEND_SUMMARY.md`'s "A note on Document / ApplicationDocument"
for the full reasoning.

## Relationships

User -> Applications -> Interviews
User -> Contacts (direct — not nested under Application)
Applications <-> Contacts (many-to-many, via ApplicationContact)
Applications -> StatusHistory
Interviews -> InterviewReminders
User -> UserSettings (1:1)
User -> Notifications
User -> DeviceTokens
User -> Documents (direct — not nested under Application)
Applications <-> Documents (many-to-many, via ApplicationDocument)
User -> ResumeAnalyses (direct — not nested under Application)
User -> AtsScores (direct — not nested under Application)
ResumeAnalysis -> Document
AtsScore -> ResumeAnalysis
