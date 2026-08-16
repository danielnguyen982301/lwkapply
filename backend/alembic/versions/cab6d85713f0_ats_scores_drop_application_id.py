"""ats_scores: drop application_id

Revision ID: cab6d85713f0
Revises: 5bd2ff18bf39
Create Date: 2026-08-16 00:00:05.000000

See app/models/ats_score.py's module docstring - a score is never
cross-checked against any application's own job_url/company/position, so
the FK never actually guaranteed anything trustworthy; dropped entirely
rather than kept as a derived/validated link.
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "cab6d85713f0"
down_revision: Union[str, None] = "5bd2ff18bf39"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.drop_constraint(
        "ats_scores_application_id_fkey", "ats_scores", type_="foreignkey"
    )
    op.drop_index(op.f("ix_ats_scores_application_id"), table_name="ats_scores")
    op.drop_column("ats_scores", "application_id")


def downgrade() -> None:
    op.add_column("ats_scores", sa.Column("application_id", sa.UUID(), nullable=True))
    op.create_index(
        op.f("ix_ats_scores_application_id"),
        "ats_scores",
        ["application_id"],
        unique=False,
    )
    op.create_foreign_key(
        "ats_scores_application_id_fkey",
        "ats_scores",
        "applications",
        ["application_id"],
        ["id"],
        ondelete="CASCADE",
    )
