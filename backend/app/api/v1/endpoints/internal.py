"""
Internal, cron-triggered endpoints - not part of the public API surface.
Authenticated by a shared secret (X-Internal-Cron-Secret header) instead
of get_current_user's Bearer JWT, since the caller is a scheduler, not a
logged-in user.

Currently one route: trigger app/tasks/reminders_inline.py's
send_due_reminders on demand. This replaces Celery beat's every-10-minutes
schedule (app/core/celery_app.py's beat_schedule, still there for local
dev/study) with an external scheduler hitting this endpoint instead -
Render has no free tier for an always-on beat process. See
.github/workflows/reminders-cron.yml for the default scheduler and
docs/DEPLOYMENT.md for the full picture.
"""

import secrets

from fastapi import APIRouter, Depends, Header, HTTPException, status

from app.core.config import settings
from app.tasks.reminders_inline import send_due_reminders

router = APIRouter()


def _verify_cron_secret(
    x_internal_cron_secret: str | None = Header(default=None),
) -> None:
    if not settings.INTERNAL_CRON_SECRET:
        # Same "unconfigured feature fails clearly" precedent as
        # app/api/v1/endpoints/ai.py's _require_ai_configured - an empty
        # secret is never treated as "no secret required".
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="This endpoint is not configured.",
        )
    if not x_internal_cron_secret or not secrets.compare_digest(
        x_internal_cron_secret, settings.INTERNAL_CRON_SECRET
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or invalid X-Internal-Cron-Secret header.",
        )


@router.post("/reminders/run", dependencies=[Depends(_verify_cron_secret)])
def run_due_reminders() -> dict[str, int]:
    """Runs send_due_reminders synchronously and reports how many it
    sent - same plain-dict-response shape as main.py's /health, since
    this is an ops endpoint rather than a public API resource."""
    return {"sent_count": send_due_reminders()}
