"""
In-app notification feed - top-level, user-owned, read-mostly resource
(same shape as app/api/v1/endpoints/documents.py). The only producer today
is app/tasks/reminders.py's send_due_reminders, which creates a row per
due IN_APP-channel InterviewReminder; this module only ever reads/marks
rows as read, it never creates them.

Delivery to the browser is polling (GET /notifications/unread-count on an
interval), not real-time push - see the account-settings/notifications
planning notes. That's a frontend concern; nothing here changes because of it.
"""

import uuid
from datetime import datetime, timezone as dt_timezone

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.notification import Notification
from app.models.user import User
from app.schemas.notification import (
    NotificationListResponse,
    NotificationRead,
    UnreadCountResponse,
)

router = APIRouter()


def _get_owned_notification(
    db: Session, notification_id: uuid.UUID, user: User
) -> Notification:
    notification = (
        db.execute(
            select(Notification).where(
                Notification.id == notification_id, Notification.user_id == user.id
            )
        )
        .scalars()
        .first()
    )
    if not notification:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Notification not found"
        )
    return notification


@router.get("", response_model=NotificationListResponse)
def list_notifications(
    unread_only: bool = False,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
):
    stmt = select(Notification).where(Notification.user_id == current_user.id)
    if unread_only:
        stmt = stmt.where(Notification.read_at.is_(None))

    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    items = (
        db.execute(
            stmt.order_by(Notification.created_at.desc())
            .offset((page - 1) * page_size)
            .limit(page_size)
        )
        .scalars()
        .all()
    )

    return NotificationListResponse(
        items=[NotificationRead.model_validate(item) for item in items],
        total=total,
        page=page,
        page_size=page_size,
    )


@router.get("/unread-count", response_model=UnreadCountResponse)
def get_unread_count(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # A cheap, dedicated query - for the bell badge to poll without
    # pulling the full list every time.
    count = db.scalar(
        select(func.count()).where(
            Notification.user_id == current_user.id, Notification.read_at.is_(None)
        )
    )
    return UnreadCountResponse(unread_count=count or 0)


@router.post("/{notification_id}/read", response_model=NotificationRead)
def mark_notification_read(
    notification_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    notification = _get_owned_notification(db, notification_id, current_user)
    if notification.read_at is None:
        notification.read_at = datetime.now(dt_timezone.utc)
        db.add(notification)
        db.commit()
        db.refresh(notification)
    return notification


@router.post("/read-all", status_code=status.HTTP_204_NO_CONTENT)
def mark_all_notifications_read(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # Bulk update() construct, not a loop of loaded instances - same
    # reasoning users.py::delete_device_token already uses for its bulk
    # delete().
    db.execute(
        update(Notification)
        .where(Notification.user_id == current_user.id, Notification.read_at.is_(None))
        .values(read_at=datetime.now(dt_timezone.utc))
    )
    db.commit()
    return None
