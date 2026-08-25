"""contacts: drop application_id

Revision ID: f05f779b8378
Revises: 431e02cf06b4
Create Date: 2026-08-25 00:00:02.000000

Last step of decoupling Contact from a single Application - safe now
that both consumers of contacts.application_id (05a18d15d0c5's user_id
backfill and 431e02cf06b4's application_contacts backfill) have already
run.
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "f05f779b8378"
down_revision: Union[str, None] = "431e02cf06b4"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.drop_constraint("contacts_application_id_fkey", "contacts", type_="foreignkey")
    op.drop_index(op.f("ix_contacts_application_id"), table_name="contacts")
    op.drop_column("contacts", "application_id")


def downgrade() -> None:
    op.add_column("contacts", sa.Column("application_id", sa.UUID(), nullable=True))
    op.execute(
        """
        UPDATE contacts
        SET application_id = application_contacts.application_id
        FROM application_contacts
        WHERE application_contacts.contact_id = contacts.id
        """
    )
    # A contact reused across several applications only keeps one link on
    # downgrade (arbitrary pick, since the single-application column can't
    # represent the rest) - contacts left with no application_contacts row
    # at all (never attached to begin with under the new model) end up
    # NULL here and must be resolved manually before re-enforcing NOT NULL.
    op.alter_column("contacts", "application_id", nullable=False)
    op.create_index(
        op.f("ix_contacts_application_id"),
        "contacts",
        ["application_id"],
        unique=False,
    )
    op.create_foreign_key(
        "contacts_application_id_fkey",
        "contacts",
        "applications",
        ["application_id"],
        ["id"],
        ondelete="CASCADE",
    )
