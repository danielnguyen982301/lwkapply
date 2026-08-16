"""resume_analyses: add completed_at

Revision ID: d40a14bebe2a
Revises: 2aa540c856bd
Create Date: 2026-08-16 00:00:03.000000

See app/models/resume_analysis.py - set only when status transitions to
COMPLETED (app/tasks/ai.py::parse_resume_task), distinct from created_at
since parsing is async.
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "d40a14bebe2a"
down_revision: Union[str, None] = "2aa540c856bd"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "resume_analyses",
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("resume_analyses", "completed_at")
