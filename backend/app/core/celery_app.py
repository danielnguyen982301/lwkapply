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

from app.core.config import settings

celery_app = Celery(
    "lwkapply",
    broker=settings.REDIS_URL,
    backend=settings.REDIS_URL,
    include=["app.tasks.reminders", "app.tasks.ai"],
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
        "task": "app.tasks.reminders.send_due_reminders",
        "schedule": crontab(minute="*/10"),
    },
}
