"""application_contacts: create join table

Revision ID: 431e02cf06b4
Revises: 05a18d15d0c5
Create Date: 2026-08-25 00:00:01.000000

Second step of decoupling Contact from a single Application (see
app/models/contact.py / app/models/application_contact.py) - the
many-to-many link table, backfilled one row per existing contact from
the still-present contacts.application_id (dropped in
f05f779b8378_contacts_drop_application_id.py, the last step, once this
backfill and 05a18d15d0c5's have both already read it).
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "431e02cf06b4"
down_revision: Union[str, None] = "05a18d15d0c5"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "application_contacts",
        sa.Column("application_id", sa.UUID(), nullable=False),
        sa.Column("contact_id", sa.UUID(), nullable=False),
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
        sa.ForeignKeyConstraint(["contact_id"], ["contacts.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "application_id", "contact_id", name="uq_application_contact"
        ),
    )
    op.create_index(
        op.f("ix_application_contacts_application_id"),
        "application_contacts",
        ["application_id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_application_contacts_contact_id"),
        "application_contacts",
        ["contact_id"],
        unique=False,
    )
    op.execute(
        """
        INSERT INTO application_contacts (id, application_id, contact_id, created_at, updated_at)
        SELECT gen_random_uuid(), application_id, id, created_at, created_at
        FROM contacts
        """
    )


def downgrade() -> None:
    op.drop_index(
        op.f("ix_application_contacts_contact_id"), table_name="application_contacts"
    )
    op.drop_index(
        op.f("ix_application_contacts_application_id"),
        table_name="application_contacts",
    )
    op.drop_table("application_contacts")
