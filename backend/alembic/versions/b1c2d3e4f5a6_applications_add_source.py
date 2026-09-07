"""applications: add source

Revision ID: b1c2d3e4f5a6
Revises: f31d24b6e372
Create Date: 2026-09-06 00:00:00.000000

Free-form provenance field (e.g. "vietnamworks", "linkedin") so rows
created by a future browser-extension quick-capture can be told apart
from ones created manually in-app - see app/models/application.py.

Rebased onto f31d24b6e372 (salary_currency, merged to master after this
migration was first written) - both originally branched off 3108fccbf808,
which would have left two alembic heads.
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "b1c2d3e4f5a6"
down_revision: Union[str, None] = "f31d24b6e372"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "applications",
        sa.Column("source", sa.String(length=100), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("applications", "source")
