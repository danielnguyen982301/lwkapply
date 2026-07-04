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

## Relationships

User -> Applications -> Interviews
User -> Applications -> Documents
Application -> Contacts
