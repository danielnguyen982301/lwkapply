"""application_documents: create join table

Revision ID: aa3bea687a29
Revises: 4abd98ce29e4
Create Date: 2026-08-16 00:00:01.000000

Second step of decoupling Document from a single Application (see
app/models/document.py / app/models/application_document.py) - the
many-to-many link table, backfilled one row per existing document from
the still-present documents.application_id (dropped in
2aa540c856bd_documents_drop_application_id.py, the last step, once this
backfill and 4abd98ce29e4's have both already read it).
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "aa3bea687a29"
down_revision: Union[str, None] = "4abd98ce29e4"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "application_documents",
        sa.Column("application_id", sa.UUID(), nullable=False),
        sa.Column("document_id", sa.UUID(), nullable=False),
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["application_id"], ["applications.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(["document_id"], ["documents.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "application_id", "document_id", name="uq_application_document"
        ),
    )
    op.create_index(
        op.f("ix_application_documents_application_id"),
        "application_documents",
        ["application_id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_application_documents_document_id"),
        "application_documents",
        ["document_id"],
        unique=False,
    )
    op.execute(
        """
        INSERT INTO application_documents (id, application_id, document_id, created_at, updated_at)
        SELECT gen_random_uuid(), application_id, id, created_at, created_at
        FROM documents
        """
    )


def downgrade() -> None:
    op.drop_index(
        op.f("ix_application_documents_document_id"), table_name="application_documents"
    )
    op.drop_index(
        op.f("ix_application_documents_application_id"),
        table_name="application_documents",
    )
    op.drop_table("application_documents")
