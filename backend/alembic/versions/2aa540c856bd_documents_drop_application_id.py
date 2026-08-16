"""documents: drop application_id

Revision ID: 2aa540c856bd
Revises: aa3bea687a29
Create Date: 2026-08-16 00:00:02.000000

Last step of decoupling Document from a single Application - safe now
that both consumers of documents.application_id (4abd98ce29e4's user_id
backfill and aa3bea687a29's application_documents backfill) have already
run.
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "2aa540c856bd"
down_revision: Union[str, None] = "aa3bea687a29"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.drop_constraint("documents_application_id_fkey", "documents", type_="foreignkey")
    op.drop_index(op.f("ix_documents_application_id"), table_name="documents")
    op.drop_column("documents", "application_id")


def downgrade() -> None:
    op.add_column("documents", sa.Column("application_id", sa.UUID(), nullable=True))
    op.execute(
        """
        UPDATE documents
        SET application_id = application_documents.application_id
        FROM application_documents
        WHERE application_documents.document_id = documents.id
        """
    )
    # A document reused across several applications only keeps one link on
    # downgrade (arbitrary pick, since the single-application column can't
    # represent the rest) - documents left with no application_documents
    # row at all (never attached to begin with under the new model) end up
    # NULL here and must be resolved manually before re-enforcing NOT NULL.
    op.alter_column("documents", "application_id", nullable=False)
    op.create_index(
        op.f("ix_documents_application_id"),
        "documents",
        ["application_id"],
        unique=False,
    )
    op.create_foreign_key(
        "documents_application_id_fkey",
        "documents",
        "applications",
        ["application_id"],
        ["id"],
        ondelete="CASCADE",
    )
