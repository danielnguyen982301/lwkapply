"""
Read-only analytics endpoints: GET /analytics/summary, /funnel,
/activity, /interviews.

Every query here is scoped to current_user - a user only ever sees
aggregates over their own applications/interviews, same ownership
pattern as every other endpoint (Applications direct on user_id;
Interviews via a join through Application.user_id, mirroring
interviews.py's directory_router).

All metrics are computed in real time from current rows on every
request - no precomputation, no cache. Per-user data volumes here
(applications numbering in the hundreds at most, not millions) make
that the right tradeoff: a handful of indexed COUNT/GROUP BY queries
run in single-digit milliseconds, and real-time avoids the staleness a
precomputed/cached rollup would introduce. Revisit only if a dashboard
load is actually observed to be slow in practice.

None of these endpoints read application_status_history - see that
model's own module docstring, and app/schemas/analytics.py's, for why
the funnel here is a current-state snapshot, not a true (history-based)
funnel.
"""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.application import Application, ApplicationStatus
from app.models.interview import Interview, InterviewResult
from app.models.user import User
from app.schemas.analytics import (
    ActivityBucket,
    ActivityResponse,
    FunnelResponse,
    FunnelStage,
    InterviewAnalyticsResponse,
    InterviewResultCounts,
    SummaryResponse,
)

router = APIRouter()

# Terminal statuses an application can't move on from - used by the
# summary's "active" count and the funnel's off-ramp split. ACCEPTED is
# deliberately NOT here: it's a successful terminal state, not an
# off-ramp, and stays visible in the same funnel-stage list as the rest
# of the pipeline rather than being folded in with rejections.
_OFF_RAMP_STATUSES = (ApplicationStatus.REJECTED, ApplicationStatus.WITHDRAWN)

# Funnel stage order for FunnelResponse.stages - deliberately excludes
# the off-ramp statuses above (those go in `off_ramps` instead), so the
# funnel reads top-to-bottom as a progression, not a flat status dump.
_FUNNEL_STAGE_ORDER = (
    ApplicationStatus.SAVED,
    ApplicationStatus.APPLIED,
    ApplicationStatus.PHONE_SCREEN,
    ApplicationStatus.INTERVIEWING,
    ApplicationStatus.OFFER,
    ApplicationStatus.ACCEPTED,
)


def _first_of_month(dt: datetime) -> datetime:
    return dt.replace(hour=0, minute=0, second=0, microsecond=0, day=1)


def _add_months(dt: datetime, n: int) -> datetime:
    """First-of-month `n` months after `dt` (n may be negative). Pure
    calendar arithmetic, no external dependency - avoids pulling in
    python-dateutil for one function."""
    month_index = dt.month - 1 + n
    year = dt.year + month_index // 12
    month = month_index % 12 + 1
    return dt.replace(
        year=year, month=month, day=1, hour=0, minute=0, second=0, microsecond=0
    )


@router.get("/summary", response_model=SummaryResponse)
def get_summary(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    base_query = db.query(Application).filter(Application.user_id == current_user.id)

    total_applications = base_query.count()
    active_applications = base_query.filter(
        ~Application.status.in_(_OFF_RAMP_STATUSES)
    ).count()
    offers_received = base_query.filter(
        Application.status.in_((ApplicationStatus.OFFER, ApplicationStatus.ACCEPTED))
    ).count()

    interviews_scheduled = (
        db.query(Interview)
        .join(Application, Interview.application_id == Application.id)
        .filter(
            Application.user_id == current_user.id,
            Interview.result == InterviewResult.PENDING,
        )
        .count()
    )

    applications_submitted = base_query.filter(
        Application.status != ApplicationStatus.SAVED
    ).count()
    responded = base_query.filter(
        ~Application.status.in_((ApplicationStatus.SAVED, ApplicationStatus.APPLIED))
    ).count()
    response_rate = (
        responded / applications_submitted if applications_submitted > 0 else None
    )

    return SummaryResponse(
        total_applications=total_applications,
        active_applications=active_applications,
        offers_received=offers_received,
        interviews_scheduled=interviews_scheduled,
        response_rate=response_rate,
    )


@router.get("/funnel", response_model=FunnelResponse)
def get_funnel(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    rows = (
        db.query(Application.status, func.count(Application.id))
        .filter(Application.user_id == current_user.id)
        .group_by(Application.status)
        .all()
    )
    counts = {status: count for status, count in rows}

    stages = [
        FunnelStage(status=s, count=counts.get(s, 0)) for s in _FUNNEL_STAGE_ORDER
    ]
    off_ramps = [
        FunnelStage(status=s, count=counts.get(s, 0)) for s in _OFF_RAMP_STATUSES
    ]

    return FunnelResponse(
        total_applications=sum(counts.values()), stages=stages, off_ramps=off_ramps
    )


@router.get("/activity", response_model=ActivityResponse)
def get_activity(
    months: int = Query(
        default=6,
        ge=1,
        le=24,
        description="Number of calendar months to include, ending with the current one.",
    ),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    now = datetime.now(timezone.utc)
    range_start = _add_months(_first_of_month(now), -(months - 1))

    bucket_expr = func.date_trunc("month", Application.created_at)
    rows = (
        db.query(bucket_expr.label("bucket"), func.count(Application.id))
        .filter(
            Application.user_id == current_user.id,
            Application.created_at >= range_start,
        )
        .group_by(bucket_expr)
        .all()
    )
    counts_by_period = {bucket.strftime("%Y-%m"): count for bucket, count in rows}

    buckets = []
    cursor = range_start
    for _ in range(months):
        period = cursor.strftime("%Y-%m")
        buckets.append(
            ActivityBucket(
                period=period, applications_created=counts_by_period.get(period, 0)
            )
        )
        cursor = _add_months(cursor, 1)

    return ActivityResponse(buckets=buckets)


@router.get("/interviews", response_model=InterviewAnalyticsResponse)
def get_interview_analytics(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    rows = (
        db.query(Interview.result, func.count(Interview.id))
        .join(Application, Interview.application_id == Application.id)
        .filter(Application.user_id == current_user.id)
        .group_by(Interview.result)
        .all()
    )
    counts = {result: count for result, count in rows}

    by_result = InterviewResultCounts(
        pending=counts.get(InterviewResult.PENDING, 0),
        passed=counts.get(InterviewResult.PASSED, 0),
        failed=counts.get(InterviewResult.FAILED, 0),
        cancelled=counts.get(InterviewResult.CANCELLED, 0),
    )
    decided = by_result.passed + by_result.failed
    pass_rate = by_result.passed / decided if decided > 0 else None

    return InterviewAnalyticsResponse(
        total_interviews=sum(counts.values()),
        by_result=by_result,
        pass_rate=pass_rate,
    )
