"""
Shared fixtures for integration tests that need a real database and HTTP
layer, as opposed to the pure-payload schema tests elsewhere in this
directory (e.g. test_contact_schema.py).

Why a real Postgres instance, not SQLite:
`Contact.application_id` / `Application.user_id` / all primary keys use
sqlalchemy.dialects.postgresql.UUID, and enum columns are declared with
values_callable to store lowercase .value strings - both are
Postgres-specific and don't behave the same (or at all) against an
in-memory SQLite DB. See BACKEND_SUMMARY.md's note on this. Point
TEST_DATABASE_URL at a throwaway Postgres database - never at the same
database DATABASE_URL uses for local dev, since tables are dropped at the
end of the test session.

Isolation strategy:
Each test gets its own SAVEPOINT-nested transaction on a single
connection. Endpoint code calls db.commit() as normal (it doesn't know
it's in a test), which only closes the current SAVEPOINT - an
after_transaction_end listener immediately opens a new one. The real
outer transaction is rolled back once the test finishes, so nothing ever
reaches the database permanently and tests can't leak state into each
other. This is the standard SQLAlchemy "join a session into an external
transaction" recipe.
"""

import uuid
from collections.abc import Generator

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, event
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import settings

# Importing these registers every mapped class on Base's registry before
# create_all() / mapper configuration runs. Application.py declares
# relationships to Interview and Document via string forward-refs
# (Mapped[list["Interview"]]); if those modules are never imported,
# SQLAlchemy fails to resolve those names the first time any mapper gets
# configured (e.g. on first query/insert), not at import time - so this
# has to happen here even though this test file never touches Interview
# or Document directly.
import app.models.application  # noqa: F401
import app.models.contact  # noqa: F401
import app.models.document  # noqa: F401
import app.models.interview  # noqa: F401
import app.models.user  # noqa: F401
from app.core.security import create_access_token, hash_password
from app.db.base_class import Base
from app.db.session import get_db
from app.main import app
from app.models.user import User


@pytest.fixture(scope="session")
def engine() -> Generator[Engine, None, None]:
    eng = create_engine(settings.TEST_DATABASE_URL)
    try:
        Base.metadata.create_all(bind=eng)
    except Exception as exc:  # pragma: no cover - fails fast with a clear hint
        raise RuntimeError(
            "Could not connect to the test database at "
            f"{settings.TEST_DATABASE_URL!r}. Integration tests need a "
            "real Postgres instance (SQLite won't work - see the module "
            "docstring in conftest.py). Set TEST_DATABASE_URL in "
            "backend/.env.local (or as a real env var, e.g. in CI) or "
            "create the default database it points at."
        ) from exc
    yield eng
    Base.metadata.drop_all(bind=eng)
    eng.dispose()


@pytest.fixture()
def db_session(engine: Engine) -> Generator[Session, None, None]:
    connection = engine.connect()
    outer_transaction = connection.begin()
    session_factory = sessionmaker(autocommit=False, autoflush=False, bind=connection)
    session = session_factory()

    session.begin_nested()

    @event.listens_for(session, "after_transaction_end")
    def _restart_savepoint(sess: Session, transaction) -> None:
        if transaction.nested and not transaction._parent.nested:
            sess.begin_nested()

    try:
        yield session
    finally:
        session.close()
        outer_transaction.rollback()
        connection.close()


@pytest.fixture()
def client(db_session: Session) -> Generator[TestClient, None, None]:
    """A TestClient whose every request runs against db_session, so
    anything the request commits is visible to assertions made directly
    via db_session, and everything rolls back together at teardown."""

    def _get_db_override() -> Generator[Session, None, None]:
        yield db_session

    app.dependency_overrides[get_db] = _get_db_override
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


@pytest.fixture()
def make_user(db_session: Session):
    """Factory fixture: make_user() -> User, inserted directly via the
    ORM rather than through POST /auth/register, since these tests are
    about GET /contacts, not registration."""

    def _make_user(
        email: str | None = None, password: str = "correct-horse-battery-staple"
    ) -> User:
        user = User(
            email=email or f"{uuid.uuid4()}@example.com",
            password_hash=hash_password(password),
            first_name="Test",
            last_name="User",
        )
        db_session.add(user)
        db_session.commit()
        db_session.refresh(user)
        return user

    return _make_user


@pytest.fixture()
def auth_headers():
    """Factory fixture: auth_headers(user) -> {"Authorization": "Bearer ..."}
    Mints a real access token via the app's own create_access_token, so
    these tests exercise the actual decode/lookup path in
    app.api.deps.get_current_user rather than bypassing it."""

    def _auth_headers(user: User) -> dict[str, str]:
        token = create_access_token(subject=str(user.id))
        return {"Authorization": f"Bearer {token}"}

    return _auth_headers
