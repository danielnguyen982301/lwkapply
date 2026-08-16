"""applications: add application_name

Revision ID: 5bd2ff18bf40
Revises: cab6d85713f0
Create Date: 2026-08-16 00:00:06.000000

Optional user-chosen label so applications to the same company/position
(a re-apply, or two postings with the same title) can be told apart in
list views - see app/models/application.py.
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "8c175054e5e6"
down_revision: Union[str, None] = "cab6d85713f0"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "applications",
        sa.Column("application_name", sa.String(length=255), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("applications", "application_name")
