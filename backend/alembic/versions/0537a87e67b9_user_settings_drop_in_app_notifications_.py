"""user_settings_drop_in_app_notifications_enabled

Revision ID: 0537a87e67b9
Revises: 85a2b6ae241d
Create Date: 2026-08-18 17:20:46.379256

"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "0537a87e67b9"
down_revision: Union[str, None] = "85a2b6ae241d"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Removed: the in-app notification feed is purely pull-based (a list
    # you only see if you open the bell), unlike email/push which reach
    # the user outside this app - so it doesn't get its own opt-out, only
    # the master `notifications_enabled` switch gates it. See
    # app/tasks/reminders.py::_channel_enabled.
    op.drop_column("user_settings", "in_app_notifications_enabled")


def downgrade() -> None:
    op.add_column(
        "user_settings",
        sa.Column(
            "in_app_notifications_enabled",
            sa.Boolean(),
            server_default=sa.text("true"),
            nullable=False,
        ),
    )
