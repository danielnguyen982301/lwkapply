"""applications: add salary_currency

Revision ID: f31d24b6e372
Revises: 3108fccbf808
Create Date: 2026-09-07 00:00:00.000000

Currency of the salary_min/salary_max range (see
app/models/application.py::SalaryCurrency). server_default so existing
rows don't need a separate backfill step - every pre-existing
application defaults to USD, same as a brand-new one.

add_column (unlike every enum this repo has migrated so far, which were
all created inline as part of create_table) doesn't get the implicit
CREATE TYPE that create_table's DDL compiler emits, so the enum type is
created explicitly first.
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "f31d24b6e372"
down_revision: Union[str, None] = "3108fccbf808"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


_salary_currency_enum = postgresql.ENUM(
    "USD",
    "EUR",
    "GBP",
    "CAD",
    "AUD",
    "NZD",
    "CHF",
    "SEK",
    "NOK",
    "DKK",
    "ISK",
    "PLN",
    "CZK",
    "HUF",
    "RON",
    "UAH",
    "RUB",
    "TRY",
    "ILS",
    "AED",
    "SAR",
    "EGP",
    "NGN",
    "KES",
    "ZAR",
    "INR",
    "PKR",
    "BDT",
    "CNY",
    "JPY",
    "KRW",
    "TWD",
    "HKD",
    "SGD",
    "MYR",
    "THB",
    "VND",
    "IDR",
    "PHP",
    "BRL",
    "MXN",
    "ARS",
    "CLP",
    "COP",
    name="salary_currency",
)


def upgrade() -> None:
    _salary_currency_enum.create(op.get_bind(), checkfirst=True)
    op.add_column(
        "applications",
        sa.Column(
            "salary_currency",
            _salary_currency_enum,
            server_default="USD",
            nullable=False,
        ),
    )


def downgrade() -> None:
    op.drop_column("applications", "salary_currency")
    _salary_currency_enum.drop(op.get_bind(), checkfirst=True)
