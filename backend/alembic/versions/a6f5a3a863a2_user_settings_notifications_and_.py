"""user_settings_notifications_and_timezone_manual

Revision ID: a6f5a3a863a2
Revises: 5db76af53e3f
Create Date: 2026-08-18 09:43:43.425067

"""

import uuid
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "a6f5a3a863a2"
down_revision: Union[str, None] = "5db76af53e3f"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # --- users.timezone_is_manual -----------------------------------------
    # Guards _maybe_update_timezone (app/api/v1/endpoints/auth.py) from
    # silently overwriting an explicit PATCH /users/me timezone choice on
    # the next login/refresh. server_default so existing rows don't need a
    # separate backfill step - every pre-existing account is "not manual"
    # (auto-detected), which is exactly what False means here.
    op.add_column(
        "users",
        sa.Column(
            "timezone_is_manual",
            sa.Boolean(),
            server_default=sa.text("false"),
            nullable=False,
        ),
    )

    # --- user_settings -------------------------------------------------
    op.create_table(
        "user_settings",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("user_id", sa.UUID(), nullable=False),
        sa.Column("reminder_lead_hours", sa.Integer(), nullable=True),
        sa.Column(
            "notifications_enabled",
            sa.Boolean(),
            server_default=sa.text("true"),
            nullable=False,
        ),
        sa.Column(
            "email_notifications_enabled",
            sa.Boolean(),
            server_default=sa.text("true"),
            nullable=False,
        ),
        sa.Column(
            "push_notifications_enabled",
            sa.Boolean(),
            server_default=sa.text("true"),
            nullable=False,
        ),
        sa.Column(
            "in_app_notifications_enabled",
            sa.Boolean(),
            server_default=sa.text("true"),
            nullable=False,
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    # A single unique index (not a separate UniqueConstraint too) - matches
    # the model's `unique=True, index=True` on user_id, which SQLAlchemy
    # renders as one unique index, not two redundant objects.
    op.create_index(
        op.f("ix_user_settings_user_id"), "user_settings", ["user_id"], unique=True
    )

    # Every existing user gets a default-valued settings row, so
    # `user.settings` can be treated as always-present everywhere it's
    # read (see app/models/user_settings.py's module docstring) instead
    # of every call site needing an is-None branch. New users get one at
    # registration time instead (app/api/v1/endpoints/auth.py::register).
    user_settings = sa.table(
        "user_settings",
        sa.column("id", sa.UUID()),
        sa.column("user_id", sa.UUID()),
    )
    users = sa.table("users", sa.column("id", sa.UUID()))
    bind = op.get_bind()
    existing_user_ids = [row[0] for row in bind.execute(sa.select(users.c.id))]
    if existing_user_ids:
        op.bulk_insert(
            user_settings,
            [{"id": uuid.uuid4(), "user_id": user_id} for user_id in existing_user_ids],
        )

    # --- notifications ---------------------------------------------------
    # No separate .create() call for the enum type - op.create_table below
    # creates it automatically as part of the table DDL (matches every
    # other Enum column in this codebase, e.g. document_type/
    # application_status/interview_type - none of them call .create()
    # explicitly either).
    notification_type = sa.Enum("interview_reminder", name="notification_type")

    op.create_table(
        "notifications",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("user_id", sa.UUID(), nullable=False),
        sa.Column("type", notification_type, nullable=False),
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("body", sa.Text(), nullable=False),
        sa.Column("application_id", sa.UUID(), nullable=True),
        sa.Column("interview_id", sa.UUID(), nullable=True),
        sa.Column("read_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(
            ["application_id"], ["applications.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["interview_id"], ["interviews.id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        op.f("ix_notifications_user_id"), "notifications", ["user_id"], unique=False
    )
    # Matches the bell badge's unread-count query and the list view's
    # unread_only filter, both of which filter on exactly this pair.
    op.create_index(
        "ix_notifications_user_id_read_at",
        "notifications",
        ["user_id", "read_at"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_notifications_user_id_read_at", table_name="notifications")
    op.drop_index(op.f("ix_notifications_user_id"), table_name="notifications")
    op.drop_table("notifications")
    sa.Enum(name="notification_type").drop(op.get_bind(), checkfirst=True)

    op.drop_index(op.f("ix_user_settings_user_id"), table_name="user_settings")
    op.drop_table("user_settings")

    op.drop_column("users", "timezone_is_manual")
