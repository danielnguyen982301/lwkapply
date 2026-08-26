"""
Transactional email, sent through the Gmail API over HTTPS rather than
raw SMTP (app/services/email_smtp.py's `smtplib` backend). This is what
app/tasks/reminders_inline.py - the production reminders pipeline -
actually calls.

Why not just use email_smtp.py in production: Render blocks outbound
traffic to SMTP ports (25/465/587) entirely on free web services, so
`smtplib.SMTP(...)` can't even open a connection there
("OSError: [Errno 101] Network is unreachable"). The Gmail API sends
over the same HTTPS port everything else on this API already uses, so
Render's SMTP-port block doesn't apply. It's also not just a workaround
for that block - mail sent through Google's own servers carries Google's
own SPF/DKIM/DMARC authentication automatically, which matters more than
it used to: Gmail/Yahoo (Feb 2024) and Microsoft (May 2025) now require
proper domain authentication for reliable inbox delivery, and this
project has no domain of its own to authenticate with a provider like
Resend/SendGrid.

Auth model: OAuth 2.0 with a long-lived refresh token for one specific
Gmail account (GMAIL_API_SENDER_EMAIL), minted once, locally, via
scripts/gmail_oauth_setup.py - see that script's docstring for the
one-time setup. `Credentials` below turns that stored refresh token
into short-lived access tokens automatically on every call; nothing
about that renewal needs to be handled explicitly here, the
googleapiclient transport does it.

Same log-and-swallow contract as email_smtp.py's send_email: a failure
here shouldn't crash the caller's loop over every other due reminder in
the same batch (see reminders_inline.py). The caller checks the boolean
return to decide whether to stamp `sent_at`.
"""

import base64
import logging
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

from google.auth.exceptions import RefreshError
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

from app.core.config import settings

logger = logging.getLogger(__name__)

# Send-only - deliberately not the broader gmail.modify/full-mailbox
# scopes, since this integration never needs to read anything.
_SCOPES = ["https://www.googleapis.com/auth/gmail.send"]
_TOKEN_URI = "https://oauth2.googleapis.com/token"


def _is_configured() -> bool:
    return bool(
        settings.GMAIL_API_CLIENT_ID
        and settings.GMAIL_API_CLIENT_SECRET
        and settings.GMAIL_API_REFRESH_TOKEN
        and settings.GMAIL_API_SENDER_EMAIL
    )


def _build_credentials() -> Credentials:
    return Credentials(
        token=None,  # no cached access token - fetched fresh via the refresh token below
        refresh_token=settings.GMAIL_API_REFRESH_TOKEN,
        client_id=settings.GMAIL_API_CLIENT_ID,
        client_secret=settings.GMAIL_API_CLIENT_SECRET,
        token_uri=_TOKEN_URI,
        scopes=_SCOPES,
    )


def _build_raw_message(to: str, subject: str, html: str, text: str) -> dict:
    message = MIMEMultipart("alternative")
    message["Subject"] = subject
    message["From"] = f"{settings.EMAIL_FROM_NAME} <{settings.GMAIL_API_SENDER_EMAIL}>"
    message["To"] = to
    # Attach text before html - per MIME convention the *last* part is
    # preferred by clients that support it, so html (the richer version)
    # should come second. Same ordering email_smtp.py uses.
    message.attach(MIMEText(text, "plain"))
    message.attach(MIMEText(html, "html"))
    raw = base64.urlsafe_b64encode(message.as_bytes()).decode("ascii")
    return {"raw": raw}


def send_email(to: str, subject: str, html: str, text: str) -> bool:
    """Returns True if the send succeeded, False otherwise. Never raises -
    see module docstring for why."""
    if not _is_configured():
        logger.error(
            "Gmail API email backend is not configured "
            "(GMAIL_API_CLIENT_ID/CLIENT_SECRET/REFRESH_TOKEN/SENDER_EMAIL)"
        )
        return False

    try:
        credentials = _build_credentials()
        service = build("gmail", "v1", credentials=credentials, cache_discovery=False)
        body = _build_raw_message(to, subject, html, text)
        service.users().messages().send(userId="me", body=body).execute()
        return True
    except (HttpError, RefreshError):
        logger.exception("Gmail API send failed for to=%s", to)
        return False
