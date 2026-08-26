"""
One-time local script to mint a Gmail API refresh token for
app/services/email_gmail_api.py's send-only OAuth flow. Run this once,
locally, from a browser session where you can sign in - never runs in
production, and doesn't send anything itself.

Prerequisites (Google Cloud Console, console.cloud.google.com):

1. Create a project (or reuse one) - top bar's project picker ->
   New Project.
2. Enable the Gmail API - top search bar -> "Gmail API" -> Enable.
3. Configure the OAuth consent screen (left sidebar under "APIs &
   Services" -> OAuth consent screen). User type "External" is fine for
   personal use; app name and a support email are the only required
   fields. Leave publishing status as "Testing" and add your own Gmail
   address under "Test users" - an unpublished app only lets its own
   test users complete the consent flow, which is exactly what this
   needs (nobody else should be able to authorize as you anyway).
4. Create credentials ("APIs & Services" -> Credentials -> + Create
   Credentials -> OAuth client ID). Application type: Desktop app.
   Click "Download JSON" on the new client afterwards.

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
from googleapiclient.discovery import build

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

    service = build("gmail", "v1", credentials=credentials, cache_discovery=False)
    profile = service.users().getProfile(userId="me").execute()

    print("\nAdd these to Render's environment variables:\n")
    print(f"GMAIL_API_CLIENT_ID={credentials.client_id}")
    print(f"GMAIL_API_CLIENT_SECRET={credentials.client_secret}")
    print(f"GMAIL_API_REFRESH_TOKEN={credentials.refresh_token}")
    print(f"GMAIL_API_SENDER_EMAIL={profile['emailAddress']}")


if __name__ == "__main__":
    main()
