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

### documents

- id (UUID)
- application_id
- file_name
- file_url
- file_type

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

### ats_scores (AI features — backend/BACKEND_SUMMARY.md)

- id (UUID)
- user_id — direct FK, same reasoning as resume_analyses
- resume_analysis_id
- application_id (nullable — source of `job_url` when `job_description` isn't pasted)
- job_description
- job_description_source (pasted/url)
- status (pending/processing/completed/failed)
- score
- feedback (JSONB)
- error_message

## Relationships

User -> Applications -> Interviews
User -> Applications -> Documents
Application -> Contacts
User -> ResumeAnalyses (direct — not nested under Application)
User -> AtsScores (direct — not nested under Application)
ResumeAnalysis -> Document
AtsScore -> ResumeAnalysis
AtsScore -> Application (optional)
