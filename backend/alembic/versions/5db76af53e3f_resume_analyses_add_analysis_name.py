"""resume_analyses: add analysis_name

Revision ID: 5db76af53e3f
Revises: f1543bea584c
Create Date: 2026-08-17 00:00:01.000000

See app/models/resume_analysis.py - auto-generated from the source
document's file name + completion timestamp when status transitions to
COMPLETED (app/tasks/ai.py::parse_resume_task), user-editable afterwards
(PATCH /ai/resume-analyses/{id}).
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "5db76af53e3f"
down_revision: Union[str, None] = "f1543bea584c"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "resume_analyses",
        sa.Column("analysis_name", sa.String(length=255), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("resume_analyses", "analysis_name")
