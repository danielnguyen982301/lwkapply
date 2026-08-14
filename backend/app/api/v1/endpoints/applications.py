"""
Application (job application) CRUD + search/filter endpoints.

All queries are scoped to `current_user` - a user can never read or
mutate another user's applications. This is enforced at the query
level (not just in the response) to avoid IDOR vulnerabilities.
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.application import Application, ApplicationStatus
from app.models.user import User
from app.schemas.application import (
    ApplicationCreate,
    ApplicationListResponse,
    ApplicationRead,
    ApplicationUpdate,
)
from app.services.application_history import record_status_change

router = APIRouter()


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


@router.get("", response_model=ApplicationListResponse)
def list_applications(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
    status_filter: ApplicationStatus | None = Query(default=None, alias="status"),
    search: str | None = Query(default=None, description="Search company/position"),
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
            or_(Application.company.ilike(pattern), Application.position.ilike(pattern))
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
    db.flush()
    record_status_change(
        db, application, from_status=None, to_status=application.status
    )
    db.commit()
    db.refresh(application)
    return application


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
