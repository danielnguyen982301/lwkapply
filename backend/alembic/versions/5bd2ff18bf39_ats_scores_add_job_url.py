"""ats_scores: add job_url

Revision ID: 5bd2ff18bf39
Revises: d40a14bebe2a
Create Date: 2026-08-16 00:00:04.000000

See app/models/ats_score.py - the pasted URL when
job_description_source="url", kept around so
app/tasks/ai.py::score_ats_task has something to fetch from. Added before
application_id is dropped (cab6d85713f0) so the two AtsScore schema
changes stay in separate, independently revertible migrations.
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "5bd2ff18bf39"
down_revision: Union[str, None] = "d40a14bebe2a"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "ats_scores", sa.Column("job_url", sa.String(length=1000), nullable=True)
    )


def downgrade() -> None:
    op.drop_column("ats_scores", "job_url")
