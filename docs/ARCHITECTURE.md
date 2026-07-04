# Architecture

## System Overview

The platform follows a client-server architecture where both web and mobile applications communicate with a shared FastAPI backend through REST APIs.

```text
Web App (Vue.js)
        │
        ▼
   FastAPI API
        │
 ┌──────┼──────┐
 ▼      ▼      ▼
DB    Cache   Storage
```

## Frontend

### Web Application

Responsibilities:

- User interface
- State management
- Form validation
- Analytics visualization
- Kanban interactions

Technologies:

- Vue 3
- TypeScript
- Pinia
- PrimeVue
- Tailwind CSS

### Mobile Application

Responsibilities:

- Application management
- Interview tracking
- Notifications
- Offline access

Technologies:

- Flutter
- Riverpod
- Dio

## Backend

Responsibilities:

- Authentication
- Authorization
- Business logic
- Data validation
- File management
- AI integrations

Technologies:

- FastAPI
- SQLAlchemy
- PostgreSQL

## Database

Primary database:

- PostgreSQL

Core entities:

- Users
- Applications
- Interviews
- Documents
- Contacts
- Reminders

## File Storage

Documents are stored outside the database.

Examples:

- Resumes
- Cover letters
- Attachments

Storage provider:

- AWS S3

## Background Processing

Used for:

- Email notifications
- Resume parsing
- Analytics generation
- AI processing tasks

Technologies:

- Celery
- Redis

## Security

- JWT authentication
- Password hashing with bcrypt
- Role-based access control
- Input validation
- Secure file uploads

## Future Architecture Enhancements

- Real-time notifications
- Event-driven processing
- AI microservices
- Multi-tenant support

## Mobile Application

- Flutter
- Riverpod
- Dio

## Security

- JWT Authentication
- RBAC
- bcrypt Password Hashing