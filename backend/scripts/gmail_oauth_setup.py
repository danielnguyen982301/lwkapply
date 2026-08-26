"""
One-time local script to mint a Gmail API refresh token for
app/services/email_gmail_api.py's send-only OAuth flow. Run this once,
locally, from a browser session where you can sign in - never runs in
production, and doesn't send anything itself.

Prerequisites (Google Cloud Console, console.cloud.google.com - the
"Google Auth Platform" section specifically, which has been reshuffled
more than once, so treat exact labels/navigation here as approximate):

1. Create a project (or reuse one) - top bar's project picker ->
   New Project.
2. Enable the Gmail API - top search bar -> "Gmail API" -> Enable.
3. Set up branding/consent (Google Auth Platform -> Overview -> "Create
   branding" or similar) - a short wizard: App name + a support email
   (App Information) -> Audience -> Contact Information -> Finish. This
   wizard does NOT include adding test users.
4. Add yourself as a test user separately - Google Auth Platform's own
   left sidebar -> Audience -> add your Gmail address under Test users.
   Required: an unpublished app only lets its own test users complete
   the consent flow, which is exactly what this needs (nobody else
   should be able to authorize as you anyway).
5. Create credentials - Google Auth Platform's left sidebar -> Clients
   -> Create client. Application type: Desktop app. Download the JSON
   it generates.

Usage (from backend/, with requirements-dev.txt installed):

    .venv/bin/python scripts/gmail_oauth_setup.py path/to/client_secret.json

Opens a browser for you to sign in and consent to the send-only scope,
then prints the four values to paste into Render's environment
variables. access_type="offline" + prompt="consent" below are both
required to reliably get a refresh_token back - Google only issues one
on a consent screen the user actually saw, not on a silently-remembered
prior approval.
"""

import sys
from pathlib import Path

from google_auth_oauthlib.flow import InstalledAppFlow

SCOPES = ["https://www.googleapis.com/auth/gmail.send"]


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(
            "Usage: python scripts/gmail_oauth_setup.py path/to/client_secret.json\n"
            "(download that file from Google Cloud Console - see this script's "
            "module docstring for the full setup path)"
        )

    client_secret_path = Path(sys.argv[1])
    if not client_secret_path.exists():
        raise SystemExit(f"{client_secret_path} not found")

    flow = InstalledAppFlow.from_client_secrets_file(str(client_secret_path), SCOPES)
    credentials = flow.run_local_server(port=0, access_type="offline", prompt="consent")

    if not credentials.refresh_token:
        raise SystemExit(
            "No refresh_token in the response - this can happen if Google "
            "silently reused a prior approval. Revoke this app's access at "
            "https://myaccount.google.com/permissions and run this script "
            "again."
        )

    # Not fetched via the API (e.g. users().getProfile()) deliberately -
    # that needs a broader scope than gmail.send grants, and the whole
    # point of this flow is keeping the token scoped to send-only. You
    # already know which address you just signed in with.
    sender_email = input(
        "\nGmail address you just signed in with (for GMAIL_API_SENDER_EMAIL): "
    ).strip()

    print("\nAdd these to Render's environment variables:\n")
    print(f"GMAIL_API_CLIENT_ID={credentials.client_id}")
    print(f"GMAIL_API_CLIENT_SECRET={credentials.client_secret}")
    print(f"GMAIL_API_REFRESH_TOKEN={credentials.refresh_token}")
    print(f"GMAIL_API_SENDER_EMAIL={sender_email}")


if __name__ == "__main__":
    main()
