"""users add token_version

Revision ID: 3108fccbf808
Revises: f05f779b8378
Create Date: 2026-08-27 11:57:36.629506

server_default so existing rows don't need a separate backfill step -
every pre-existing account starts at version 0, same as a brand-new
user (see app/models/user.py::User.token_version).
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "3108fccbf808"
down_revision: Union[str, None] = "f05f779b8378"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column(
            "token_version", sa.Integer(), server_default=sa.text("0"), nullable=False
        ),
    )


def downgrade() -> None:
    op.drop_column("users", "token_version")
