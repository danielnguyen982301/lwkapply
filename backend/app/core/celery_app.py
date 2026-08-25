"""
Celery app instance. Redis (already wired up in docker-compose.yml) is
both broker and result backend - no separate result store needed for a
fire-and-forget periodic task like reminders.

Run locally as:
    celery -A app.core.celery_app worker --loglevel=info
    celery -A app.core.celery_app beat --loglevel=info
(two separate processes - see docker-compose.yml's `celery-worker` /
`celery-beat` services for the containerized equivalent)
"""

from celery import Celery
from celery.schedules import crontab

# Registers every model on Base.metadata / SQLAlchemy's mapper registry before any task runs - without this, a
# string-based relationship() on a model this worker's own task modules
# never import directly (e.g. Application.application_documents ->
# "ApplicationDocument") fails to resolve the first time any mapper gets
# configured, since mapper configuration is lazy and process-wide. Bit
# the hard way once already: app/tasks/ai_celery.py only imports Document/
# ResumeAnalysis/AtsScore/Application directly, none of which imports
# ApplicationDocument, so parse_resume_task crashed with
# `InvalidRequestError: ... failed to locate a name ('ApplicationDocument')`
# the first time it ran after that model was added. Same fix
# alembic/env.py already uses for the same reason.
from app import models  # noqa: F401

from app.core.config import settings

celery_app = Celery(
    "lwkapply",
    broker=settings.REDIS_URL,
    backend=settings.REDIS_URL,
    include=["app.tasks.reminders_celery", "app.tasks.ai_celery"],
)

celery_app.conf.update(
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    timezone="UTC",
    enable_utc=True,
)

# Every 10 minutes, comfortably inside the "every 5-15 min" window
# TODO.md's reminder plan calls for. Idempotency (sent_at IS NULL guard,
# see app/models/interview_reminder.py) is what actually makes a
# late/duplicate beat tick harmless, not the schedule's precision.
celery_app.conf.beat_schedule = {
    "send-due-interview-reminders": {
        "task": "app.tasks.reminders_celery.send_due_reminders",
        "schedule": crontab(minute="*/10"),
    },
}
