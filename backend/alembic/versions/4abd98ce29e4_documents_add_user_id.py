"""documents: add user_id

Revision ID: 4abd98ce29e4
Revises: 06abe39a184c
Create Date: 2026-08-16 00:00:00.000000

First step of decoupling Document from a single Application (see
app/models/document.py's module docstring) - a document becomes a
top-level, user-owned resource. Backfilled from the still-present
documents.application_id (dropped later, in
2aa540c856bd_documents_drop_application_id.py, once nothing else still
needs it - see that file for why the split).
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "4abd98ce29e4"
down_revision: Union[str, None] = "06abe39a184c"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("documents", sa.Column("user_id", sa.UUID(), nullable=True))
    op.execute(
        """
        UPDATE documents
        SET user_id = applications.user_id
        FROM applications
        WHERE documents.application_id = applications.id
        """
    )
    op.alter_column("documents", "user_id", nullable=False)
    op.create_index(
        op.f("ix_documents_user_id"), "documents", ["user_id"], unique=False
    )
    op.create_foreign_key(
        "documents_user_id_fkey",
        "documents",
        "users",
        ["user_id"],
        ["id"],
        ondelete="CASCADE",
    )


def downgrade() -> None:
    op.drop_constraint("documents_user_id_fkey", "documents", type_="foreignkey")
    op.drop_index(op.f("ix_documents_user_id"), table_name="documents")
    op.drop_column("documents", "user_id")
