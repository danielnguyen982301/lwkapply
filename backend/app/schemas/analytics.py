"""
Response schemas for GET /analytics/* (app/api/v1/endpoints/analytics.py).

Every endpoint reads Application.status / Interview.result as a
current-state snapshot, not application_status_history - see that
model's own module docstring for why. None of these metrics look
backward in time beyond what's true right now, so none of them can be
fooled by a user toggling a status back and forth by mistake.
"""

from pydantic import BaseModel, Field

from app.models.application import ApplicationStatus


class SummaryResponse(BaseModel):
    total_applications: int
    active_applications: int = Field(
        description="Applications not in a terminal off-ramp status (rejected/withdrawn). Includes 'accepted'."
    )
    offers_received: int = Field(
        description="Applications currently at 'offer' or 'accepted' - an offer that was later accepted still counts."
    )
    interviews_scheduled: int = Field(
        description="Interviews with result='pending' across all of the user's applications, regardless of scheduled_at."
    )
    response_rate: float | None = Field(
        default=None,
        description=(
            "Share of submitted applications (status != 'saved') that "
            "progressed beyond 'applied' - a proxy for employer "
            "response, since the data model doesn't distinguish an "
            "explicit rejection response from silence followed by the "
            "user manually marking an application rejected/withdrawn. "
            "Null if there are no submitted applications yet."
        ),
    )


class FunnelStage(BaseModel):
    status: ApplicationStatus
    count: int


class FunnelResponse(BaseModel):
    total_applications: int
    stages: list[FunnelStage] = Field(
        description=(
            "Current-status snapshot counts in funnel order (saved -> "
            "applied -> phone_screen -> interviewing -> offer -> "
            "accepted). NOT a true conversion funnel: an application "
            "that reached 'interviewing' and was later rejected counts "
            "under 'rejected' in off_ramps here, not 'interviewing'. "
            "See application_status_history.py's module docstring for "
            "why a history-based funnel isn't built yet."
        )
    )
    off_ramps: list[FunnelStage] = Field(
        description="Applications that exited the pipeline: rejected or withdrawn."
    )


class ActivityBucket(BaseModel):
    period: str = Field(description="Calendar month as 'YYYY-MM', bucketed in UTC.")
    applications_created: int


class ActivityResponse(BaseModel):
    buckets: list[ActivityBucket] = Field(
        description="Oldest month first, zero-filled for any month with no applications created."
    )


class InterviewResultCounts(BaseModel):
    pending: int
    passed: int
    failed: int
    cancelled: int


class InterviewAnalyticsResponse(BaseModel):
    total_interviews: int
    by_result: InterviewResultCounts
    pass_rate: float | None = Field(
        default=None,
        description=(
            "passed / (passed + failed), excluding pending/cancelled "
            "from both sides. Null if no interview has a decided "
            "result yet."
        ),
    )
