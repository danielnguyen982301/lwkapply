"""
Import all models here so that Base.metadata is fully populated
for Alembic autogenerate and for SQLAlchemy relationship resolution.
"""

from app.models.user import User  # noqa: F401
from app.models.application import Application  # noqa: F401
from app.models.interview import Interview  # noqa: F401
from app.models.document import Document  # noqa: F401
from app.models.contact import Contact  # noqa: F401
