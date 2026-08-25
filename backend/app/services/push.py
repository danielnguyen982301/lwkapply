"""
Push notification service via Firebase Cloud Messaging (Phase B - see
TODO.md). Same "isolate the network client behind one module" shape as
app/services/r2.py and app/services/email.py.

Deliberately network-only, same boundary r2.py/email.py both hold - this
module knows nothing about interviews, reminders, or the DB. Anything
that needs to fan out to a user's multiple devices, or prune a token
that FCM reports as dead, lives in the caller (app/tasks/reminders_celery.py)
so this file stays a thin, easily-mocked client boundary, matching how
Documents' tests mock only `app.services.r2._r2_client` and nothing
else in that module.
"""

import json
import logging
from enum import Enum, auto

import firebase_admin
from firebase_admin import credentials, messaging

from app.core.config import settings

logger = logging.getLogger(__name__)

_app: firebase_admin.App | None = None


def _get_app() -> firebase_admin.App:
    """Lazily initializes the Firebase Admin app on first use, not at
    import time - mirrors r2.py's `_r2_client()` lazy-client pattern, and
    matters more here: importing this module must not crash app startup
    just because Firebase isn't configured yet (e.g. local dev before a
    Firebase project exists - see TODO.md's Phase B setup note)."""
    global _app
    if _app is not None:
        return _app

    if settings.FIREBASE_SERVICE_ACCOUNT_JSON:
        cred = credentials.Certificate(
            json.loads(settings.FIREBASE_SERVICE_ACCOUNT_JSON)
        )
    elif settings.FIREBASE_SERVICE_ACCOUNT_PATH:
        cred = credentials.Certificate(settings.FIREBASE_SERVICE_ACCOUNT_PATH)
    else:
        raise RuntimeError(
            "Neither FIREBASE_SERVICE_ACCOUNT_JSON nor "
            "FIREBASE_SERVICE_ACCOUNT_PATH is set - push notifications "
            "are not configured."
        )

    _app = firebase_admin.initialize_app(cred)
    return _app


class PushResult(Enum):
    SENT = auto()
    INVALID_TOKEN = auto()  # token is dead - caller should delete the
    # DeviceToken row rather than retry it
    FAILED = auto()  # transient/unknown failure - safe to retry later,
    # NOT a signal to delete the token


def send_push(
    token: str, title: str, body: str, data: dict[str, str] | None = None
) -> PushResult:
    try:
        message = messaging.Message(
            token=token,
            notification=messaging.Notification(title=title, body=body),
            data=data or {},
        )
        messaging.send(message, app=_get_app())
        return PushResult.SENT
    except (messaging.UnregisteredError, messaging.SenderIdMismatchError):
        # Token is no longer valid for this app - app uninstalled, token
        # rotated and the old one expired, etc. This is the expected,
        # routine case a caller prunes on, not an error to log loudly.
        return PushResult.INVALID_TOKEN
    except Exception:
        logger.exception("FCM send failed for a device token (token not logged)")
        return PushResult.FAILED
