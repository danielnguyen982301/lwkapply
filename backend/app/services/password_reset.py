"""
Builds and sends the password-reset email. Shared by the public "forgot
password" flow (POST /auth/password-reset/request) and the logged-in
"reset password" button (POST /users/me/password-reset/request) - see
app/api/v1/endpoints/auth.py's module docstring for the overall design
(a signed, time-limited JWT emailed to the user, not a DB-stored token).

The reset link always points at the web app, even for a request that
originated from the mobile client - see mobile/lib/features/auth/
presentation/forgot_password_screen.dart's docstring for why completing
a reset happens through this link rather than an inline mobile form.
"""

import logging

from app.core.config import settings
from app.core.security import create_password_reset_token
from app.models.user import User

logger = logging.getLogger(__name__)


def _build_reset_email(user: User, token: str) -> tuple[str, str, str]:
    """Returns (subject, html, text)."""
    reset_url = f"{settings.FRONTEND_URL}/reset-password?token={token}"
    minutes = settings.PASSWORD_RESET_TOKEN_EXPIRE_MINUTES

    subject = "Reset your LwkApply password"
    text = (
        f"Hi {user.first_name},\n\n"
        "We received a request to reset your password. This link expires "
        f"in {minutes} minutes:\n\n"
        f"{reset_url}\n\n"
        "If you didn't request this, you can safely ignore this email - "
        "your password won't be changed."
    )
    html = (
        f"<p>Hi {user.first_name},</p>"
        "<p>We received a request to reset your password. This link "
        f"expires in {minutes} minutes:</p>"
        f'<p><a href="{reset_url}">Reset your password</a></p>'
        "<p>If you didn't request this, you can safely ignore this "
        "email - your password won't be changed.</p>"
    )
    return subject, html, text


def send_password_reset_email(user: User) -> bool:
    """Issues a fresh reset token tied to the user's current
    token_version (see User.token_version) and emails it.

    Picks the email backend the same way app/tasks/reminders_inline.py
    (Render's prod pipeline) vs. app/tasks/reminders_celery.py (the
    Celery-beat reference copy) split: Gmail API in production, since
    Render blocks outbound SMTP ports on free web services, and
    SMTP/MailHog or Resend everywhere else via email_smtp.py's own
    EMAIL_PROVIDER switch. This request is handled inline in the FastAPI
    process either way (no Celery task) - there's no "no worker running"
    problem to work around here the way there is for reminders, since a
    request handler is already running code synchronously.
    """
    from app.services.email_gmail_api import send_email as send_via_gmail
    from app.services.email_smtp import send_email as send_via_smtp

    token = create_password_reset_token(str(user.id), token_version=user.token_version)
    subject, html, text = _build_reset_email(user, token)

    send = send_via_gmail if settings.ENVIRONMENT == "production" else send_via_smtp
    success = send(to=user.email, subject=subject, html=html, text=text)
    if not success:
        logger.error("Failed to send password reset email to=%s", user.email)
    return success
