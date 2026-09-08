"""applications: add external_id

Revision ID: c2d4e6f8a0b1
Revises: b1c2d3e4f5a6
Create Date: 2026-09-08 00:00:00.000000

The source system's own identifier for a posting (paired with `source`
as the real identity of a browser-extension-tracked row) - see
app/models/application.py::Application.external_id's docstring for why
job_url alone isn't a trustworthy natural key. The partial unique index
only applies where both source and external_id are set, so ordinary
manually created rows (both null) are never compared against each
other.
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "c2d4e6f8a0b1"
down_revision: Union[str, None] = "b1c2d3e4f5a6"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "applications",
        sa.Column("external_id", sa.String(length=255), nullable=True),
    )
    op.create_index(
        "ix_applications_user_source_external_id",
        "applications",
        ["user_id", "source", "external_id"],
        unique=True,
        postgresql_where=sa.text("source IS NOT NULL AND external_id IS NOT NULL"),
    )


def downgrade() -> None:
    op.drop_index("ix_applications_user_source_external_id", table_name="applications")
    op.drop_column("applications", "external_id")
