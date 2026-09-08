"""
Application (job application) CRUD + search/filter endpoints.

All queries are scoped to `current_user` - a user can never read or
mutate another user's applications. This is enforced at the query
level (not just in the response) to avoid IDOR vulnerabilities.
"""

import uuid
from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.application import Application, ApplicationStatus
from app.models.user import User
from app.schemas.application import (
    ApplicationCreate,
    ApplicationDeleteByExternalIdResult,
    ApplicationListResponse,
    ApplicationRead,
    ApplicationUpdate,
    ApplicationUpsertByExternalId,
    ApplicationUpsertResult,
)
from app.services.application_history import record_status_change

router = APIRouter()

# Must match the Index name in app/models/application.py::Application.
# Used to tell "this insert lost a race on (user, source, external_id)"
# apart from any other IntegrityError (e.g. a broken FK), which should
# never be treated as that specific conflict.
_SOURCE_EXTERNAL_ID_INDEX = "ix_applications_user_source_external_id"


def _get_owned_application(
    db: Session, application_id: uuid.UUID, user: User
) -> Application:
    application = (
        db.execute(
            select(Application).where(
                Application.id == application_id, Application.user_id == user.id
            )
        )
        .scalars()
        .first()
    )
    if not application:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Application not found"
        )
    return application


def _find_by_external_id(
    db: Session, user: User, source: str, external_id: str
) -> Application | None:
    return (
        db.execute(
            select(Application).where(
                Application.user_id == user.id,
                Application.source == source,
                Application.external_id == external_id,
            )
        )
        .scalars()
        .first()
    )


def _is_source_external_id_conflict(exc: IntegrityError) -> bool:
    diag = getattr(exc.orig, "diag", None)
    return getattr(diag, "constraint_name", None) == _SOURCE_EXTERNAL_ID_INDEX


@router.get("", response_model=ApplicationListResponse)
def list_applications(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
    status_filter: ApplicationStatus | None = Query(default=None, alias="status"),
    search: str | None = Query(
        default=None, description="Search company/position/application_name"
    ),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
):
    # Built without order_by/offset/limit - reused as-is for the count
    # below (via .subquery()) and extended with those three only for the
    # items fetch, so the count query doesn't do the (pointless, for a
    # COUNT) work of sorting.
    stmt = select(Application).where(Application.user_id == current_user.id)

    if status_filter:
        stmt = stmt.where(Application.status == status_filter)

    if search:
        pattern = f"%{search}%"
        stmt = stmt.where(
            or_(
                Application.company.ilike(pattern),
                Application.position.ilike(pattern),
                Application.application_name.ilike(pattern),
            )
        )

    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    items = (
        db.execute(
            stmt.order_by(Application.updated_at.desc())
            .offset((page - 1) * page_size)
            .limit(page_size)
        )
        .scalars()
        .all()
    )

    return ApplicationListResponse(
        items=[ApplicationRead.model_validate(item) for item in items],
        total=total,
        page=page,
        page_size=page_size,
    )


@router.post("", response_model=ApplicationRead, status_code=status.HTTP_201_CREATED)
def create_application(
    payload: ApplicationCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    application = Application(**payload.model_dump(), user_id=current_user.id)
    db.add(application)
    # Flush (not commit) to populate application.id via UUIDMixin's
    # client-side default, without ending the transaction early - the
    # history row below needs a real FK value to insert against.
    try:
        db.flush()
    except IntegrityError as exc:
        db.rollback()
        # A plain create can carry source/external_id too (nothing
        # stops a caller from setting them, even though the intended
        # entry point for that pairing is PUT .../by-external-id below)
        # - if it collides with an existing row for the same
        # (user, source, external_id), surface a clean 409 rather than
        # an unhandled exception. Any other IntegrityError isn't ours to
        # explain, so it re-raises unchanged.
        if _is_source_external_id_conflict(exc):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="An application from this source with this external_id already exists",
            ) from exc
        raise
    record_status_change(
        db, application, from_status=None, to_status=application.status
    )
    db.commit()
    db.refresh(application)
    return application


@router.put("/by-external-id", response_model=ApplicationUpsertResult)
def upsert_application_by_external_id(
    payload: ApplicationUpsertByExternalId,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Idempotent create for a browser-extension "Save" action: repeating
    this call for the same (source, external_id) must never create a
    second row - if one already exists, it's returned unchanged rather
    than re-created or overwritten. See Application.external_id's
    docstring for why job_url alone isn't a trustworthy identity for
    this.

    Registered ahead of GET/PATCH/DELETE /{application_id} below - as a
    literal path segment, "by-external-id" would otherwise match
    {application_id} first (Starlette matches path shape before FastAPI
    validates the UUID), never reaching this route.
    """
    # Guaranteed non-None by ApplicationUpsertByExternalId's own
    # validator - narrows the inherited str | None annotation back to
    # str for the type checker, same as the runtime guarantee already
    # in effect.
    assert payload.source and payload.external_id
    existing = _find_by_external_id(
        db, current_user, payload.source, payload.external_id
    )
    if existing:
        return ApplicationUpsertResult(
            application=ApplicationRead.model_validate(existing), action="unchanged"
        )

    data = payload.model_dump()
    data["status"] = ApplicationStatus.SAVED  # this endpoint always creates as saved
    application = Application(**data, user_id=current_user.id)
    db.add(application)
    try:
        db.flush()
    except IntegrityError:
        # Lost a race with a concurrent identical request - the partial
        # unique index caught what the check above alone couldn't. The
        # other request's row is now the real one.
        db.rollback()
        existing = _find_by_external_id(
            db, current_user, payload.source, payload.external_id
        )
        if existing:
            return ApplicationUpsertResult(
                application=ApplicationRead.model_validate(existing), action="unchanged"
            )
        raise

    record_status_change(
        db, application, from_status=None, to_status=application.status
    )
    db.commit()
    db.refresh(application)
    return ApplicationUpsertResult(
        application=ApplicationRead.model_validate(application), action="created"
    )


@router.patch("/by-external-id", response_model=ApplicationUpsertResult)
def apply_application_by_external_id(
    payload: ApplicationUpsertByExternalId,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Idempotent "mark applied" for a browser-extension Apply action:
    - a "saved" row for (source, external_id) moves to "applied" + today
    - a row in any other status is left completely untouched - this
      must never downgrade or resurrect a row past the saved stage
    - no row at all creates one directly as "applied" (a bare apply
      with no prior save)
    """
    # Guaranteed non-None by ApplicationUpsertByExternalId's own
    # validator - narrows the inherited str | None annotation back to
    # str for the type checker, same as the runtime guarantee already
    # in effect.
    assert payload.source and payload.external_id
    existing = _find_by_external_id(
        db, current_user, payload.source, payload.external_id
    )

    if existing:
        if existing.status != ApplicationStatus.SAVED:
            return ApplicationUpsertResult(
                application=ApplicationRead.model_validate(existing), action="unchanged"
            )

        previous_status = existing.status
        existing.status = ApplicationStatus.APPLIED
        existing.applied_date = date.today()
        db.add(existing)
        record_status_change(
            db, existing, from_status=previous_status, to_status=existing.status
        )
        db.commit()
        db.refresh(existing)
        return ApplicationUpsertResult(
            application=ApplicationRead.model_validate(existing), action="updated"
        )

    data = payload.model_dump()
    data["status"] = ApplicationStatus.APPLIED
    data["applied_date"] = date.today()
    application = Application(**data, user_id=current_user.id)
    db.add(application)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        existing = _find_by_external_id(
            db, current_user, payload.source, payload.external_id
        )
        if existing:
            return ApplicationUpsertResult(
                application=ApplicationRead.model_validate(existing), action="unchanged"
            )
        raise

    record_status_change(
        db, application, from_status=None, to_status=application.status
    )
    db.commit()
    db.refresh(application)
    return ApplicationUpsertResult(
        application=ApplicationRead.model_validate(application), action="created"
    )


@router.delete("/by-external-id", response_model=ApplicationDeleteByExternalIdResult)
def delete_application_by_external_id(
    source: str = Query(...),
    external_id: str = Query(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Conditional delete for a browser-extension "Unsave" action: only
    removes a row tracked here as "saved" - one already moved past that
    (e.g. "applied") is left untouched entirely, since unsaving on the
    source site says nothing about withdrawing an application. Always
    200, never 404-on-not-found: "no saved row exists for this job" is
    itself a valid outcome of "make sure none does", not an error.
    """
    existing = _find_by_external_id(db, current_user, source, external_id)
    if not existing:
        return ApplicationDeleteByExternalIdResult(action="not_found")
    if existing.status != ApplicationStatus.SAVED:
        return ApplicationDeleteByExternalIdResult(action="kept")

    db.delete(existing)
    db.commit()
    return ApplicationDeleteByExternalIdResult(action="deleted")


@router.get("/{application_id}", response_model=ApplicationRead)
def get_application(
    application_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return _get_owned_application(db, application_id, current_user)


@router.patch("/{application_id}", response_model=ApplicationRead)
def update_application(
    application_id: uuid.UUID,
    payload: ApplicationUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    application = _get_owned_application(db, application_id, current_user)
    updates = payload.model_dump(exclude_unset=True)

    # ApplicationUpdate's own validator only catches a request that sets
    # both salary_min and salary_max inconsistently in the same payload.
    # A request that only touches one side of the range (e.g. just
    # salary_min via PATCH) still needs checking against whatever the
    # *other* side already is on the stored row - the schema alone can't
    # see that. Computed before any setattr() so a rejected update never
    # leaves the session holding a partially-mutated, uncommitted object.
    effective_salary_min = updates.get("salary_min", application.salary_min)
    effective_salary_max = updates.get("salary_max", application.salary_max)
    if (
        effective_salary_min is not None
        and effective_salary_max is not None
        and effective_salary_min > effective_salary_max
    ):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="salary_min cannot be greater than salary_max",
        )

    # Captured before setattr() below overwrites it - this is the only
    # place the "from" side of a transition is available.
    previous_status = application.status

    for field, value in updates.items():
        setattr(application, field, value)

    if "status" in updates and application.status != previous_status:
        record_status_change(
            db,
            application,
            from_status=previous_status,
            to_status=application.status,
        )

    db.add(application)
    db.commit()
    db.refresh(application)
    return application


@router.delete("/{application_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_application(
    application_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    application = _get_owned_application(db, application_id, current_user)
    db.delete(application)
    db.commit()
    return None
