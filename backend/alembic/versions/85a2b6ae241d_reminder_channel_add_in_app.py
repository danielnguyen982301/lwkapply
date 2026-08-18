"""reminder_channel_add_in_app

Revision ID: 85a2b6ae241d
Revises: a6f5a3a863a2
Create Date: 2026-08-18 09:44:24.017494

"""

from typing import Sequence, Union

from alembic import op


# revision identifiers, used by Alembic.
revision: str = "85a2b6ae241d"
down_revision: Union[str, None] = "a6f5a3a863a2"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Adding a value to an *existing* Postgres enum (unlike every enum
    # this repo has migrated so far, which were all fresh CREATE TYPEs -
    # see d65db92902b9_interview_reminders_and_user_timezone.py's original
    # reminder_channel). Kept in its own revision, separate from the
    # notifications/user_settings migration: Postgres forbids using a
    # newly-added enum value in the same transaction that added it, so
    # this must not be combined with any migration that also inserts rows
    # using 'in_app'.
    op.execute("ALTER TYPE reminder_channel ADD VALUE IF NOT EXISTS 'in_app'")


def downgrade() -> None:
    # Postgres has no ALTER TYPE ... DROP VALUE. Standard workaround: drop
    # any rows using the value (an in_app channel doesn't exist in the
    # downgraded schema), then swap the enum type out from under the
    # column for one built without it.
    op.execute("DELETE FROM interview_reminders WHERE channel = 'in_app'")
    # The column's existing DEFAULT expression is itself typed as the old
    # enum - dropped and re-added around the type swap, or the ALTER
    # COLUMN ... TYPE below fails trying to cast it.
    op.execute("ALTER TABLE interview_reminders ALTER COLUMN channel DROP DEFAULT")
    op.execute("ALTER TYPE reminder_channel RENAME TO reminder_channel_old")
    op.execute("CREATE TYPE reminder_channel AS ENUM ('email', 'push')")
    op.execute(
        "ALTER TABLE interview_reminders "
        "ALTER COLUMN channel TYPE reminder_channel "
        "USING channel::text::reminder_channel"
    )
    op.execute(
        "ALTER TABLE interview_reminders "
        "ALTER COLUMN channel SET DEFAULT 'email'::reminder_channel"
    )
    op.execute("DROP TYPE reminder_channel_old")
