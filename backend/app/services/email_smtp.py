"""
Transactional email service. Same "isolate the network client behind one
module, switch on config" shape as app/services/r2.py.

Two backends, chosen by `settings.EMAIL_PROVIDER`:

- "resend" - the real provider (staging/production). Talks to Resend's
  HTTP API directly via `httpx` rather than pulling in the `resend`
  package, since the API surface we need (POST /emails) is one call -
  not worth a new dependency for that. If Resend's SDK ever gets used
  for more (webhooks, batch sending, etc.) it's worth reconsidering.
- "smtp" - local dev, points at MailHog (docker-compose's `mailhog`
  service: SMTP on 1025, web UI on 8025). MailHog never actually
  delivers anything - it just catches whatever hits port 1025 and shows
  it in its UI, so nothing sent in local dev ever reaches a real inbox.
  Uses stdlib `smtplib`, no new dependency needed.

Both backends log-and-swallow send failures rather than raising, on
purpose: a reminder email failing to send shouldn't crash the Celery
task for every *other* due reminder in the same batch (see
app/tasks/reminders_celery.py, which calls this per-reminder in a loop). The
caller checks the boolean return to decide whether to stamp `sent_at`.
"""

import logging
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

import httpx

from app.core.config import settings

logger = logging.getLogger(__name__)

_RESEND_API_URL = "https://api.resend.com/emails"


def _from_header() -> str:
    return f"{settings.EMAIL_FROM_NAME} <{settings.EMAIL_FROM_ADDRESS}>"


def _send_via_resend(to: str, subject: str, html: str, text: str) -> bool:
    if not settings.RESEND_API_KEY:
        logger.error("EMAIL_PROVIDER=resend but RESEND_API_KEY is not set")
        return False

    try:
        response = httpx.post(
            _RESEND_API_URL,
            headers={"Authorization": f"Bearer {settings.RESEND_API_KEY}"},
            json={
                "from": _from_header(),
                "to": [to],
                "subject": subject,
                "html": html,
                "text": text,
            },
            timeout=10.0,
        )
        response.raise_for_status()
        return True
    except httpx.HTTPError:
        logger.exception("Resend send failed for to=%s", to)
        return False


def _send_via_smtp(to: str, subject: str, html: str, text: str) -> bool:
    message = MIMEMultipart("alternative")
    message["Subject"] = subject
    message["From"] = _from_header()
    message["To"] = to
    # Attach text before html - per MIME convention the *last* part is
    # preferred by clients that support it, so html (the richer version)
    # should come second.
    message.attach(MIMEText(text, "plain"))
    message.attach(MIMEText(html, "html"))

    try:
        with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT, timeout=10) as smtp:
            if settings.SMTP_USE_TLS:
                smtp.starttls()
            if settings.SMTP_USERNAME:
                smtp.login(settings.SMTP_USERNAME, settings.SMTP_PASSWORD)
            smtp.sendmail(settings.EMAIL_FROM_ADDRESS, [to], message.as_string())
        return True
    except (smtplib.SMTPException, OSError):
        logger.exception("SMTP send failed for to=%s (host=%s)", to, settings.SMTP_HOST)
        return False


def send_email(to: str, subject: str, html: str, text: str) -> bool:
    """Returns True if the send succeeded, False otherwise. Never raises -
    see module docstring for why."""
    if settings.EMAIL_PROVIDER == "resend":
        return _send_via_resend(to, subject, html, text)
    return _send_via_smtp(to, subject, html, text)
