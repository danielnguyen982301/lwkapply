# Job Application Tracker

A full-stack job application management platform designed to help job seekers organize applications, track interview progress, manage resumes, and gain insights into their job search through analytics and AI-powered features.

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

- Docker
- GitHub Actions
- AWS S3
- Railway / Render
- Vercel

## Deployment

### Environments

- Development
- Staging
- Production

### Frontend

Platform: Vercel

### Backend

Platform: Railway or Render

### Database

Platform: PostgreSQL (Supabase)

### Storage

Platform: AWS S3

### CI/CD

GitHub Actions

Pipeline:

1. Lint
2. Test
3. Build
4. Deploy

### Monitoring

- Sentry
- Application Logs
- Database Monitoring

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
- docs/DECISIONS.md
- TODO.md
