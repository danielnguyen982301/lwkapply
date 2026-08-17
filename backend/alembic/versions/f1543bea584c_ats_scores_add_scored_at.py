"""ats_scores: add scored_at

Revision ID: f1543bea584c
Revises: 8c175054e5e6
Create Date: 2026-08-17 00:00:00.000000

See app/models/ats_score.py - set only when status transitions to
COMPLETED (app/tasks/ai.py::score_ats_task), distinct from created_at
since scoring is async.
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "f1543bea584c"
down_revision: Union[str, None] = "8c175054e5e6"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "ats_scores",
        sa.Column("scored_at", sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("ats_scores", "scored_at")
