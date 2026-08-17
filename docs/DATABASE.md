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
- role
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
- status
- salary_min
- salary_max
- applied_date
- job_url
- notes

### interviews

- id (UUID)
- application_id
- type
- scheduled_at
- duration
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

### contacts

- id (UUID)
- application_id
- name
- title
- email
- linkedin_url

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
User -> Applications -> Contacts
User -> Documents (direct — not nested under Application)
Applications <-> Documents (many-to-many, via ApplicationDocument)
User -> ResumeAnalyses (direct — not nested under Application)
User -> AtsScores (direct — not nested under Application)
ResumeAnalysis -> Document
AtsScore -> ResumeAnalysis
