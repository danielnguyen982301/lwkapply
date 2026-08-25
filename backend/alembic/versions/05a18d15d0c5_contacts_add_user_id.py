"""contacts: add user_id

Revision ID: 05a18d15d0c5
Revises: 0537a87e67b9
Create Date: 2026-08-25 00:00:00.000000

First step of decoupling Contact from a single Application (see
app/models/contact.py's module docstring) - a contact becomes a
top-level, user-owned resource. Backfilled from the still-present
contacts.application_id (dropped later, in
f05f779b8378_contacts_drop_application_id.py, once nothing else still
needs it - see that file for why the split).
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "05a18d15d0c5"
down_revision: Union[str, None] = "0537a87e67b9"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("contacts", sa.Column("user_id", sa.UUID(), nullable=True))
    op.execute(
        """
        UPDATE contacts
        SET user_id = applications.user_id
        FROM applications
        WHERE contacts.application_id = applications.id
        """
    )
    op.alter_column("contacts", "user_id", nullable=False)
    op.create_index(op.f("ix_contacts_user_id"), "contacts", ["user_id"], unique=False)
    op.create_foreign_key(
        "contacts_user_id_fkey",
        "contacts",
        "users",
        ["user_id"],
        ["id"],
        ondelete="CASCADE",
    )


def downgrade() -> None:
    op.drop_constraint("contacts_user_id_fkey", "contacts", type_="foreignkey")
    op.drop_index(op.f("ix_contacts_user_id"), table_name="contacts")
    op.drop_column("contacts", "user_id")
