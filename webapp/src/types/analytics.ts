// Mirrors backend/app/schemas/analytics.py.
import type { ApplicationStatus } from './application'

export interface SummaryResponse {
  total_applications: number
  active_applications: number
  offers_received: number
  interviews_scheduled: number
  /** null when there are no submitted applications yet. */
  response_rate: number | null
}

export interface FunnelStage {
  status: ApplicationStatus
  count: number
}

export interface FunnelResponse {
  total_applications: number
  /** Snapshot counts in pipeline order (saved -> ... -> accepted). NOT a
   * true conversion funnel - see AnalyticsDashboardView.vue's caption. */
  stages: FunnelStage[]
  /** Applications that exited the pipeline: rejected or withdrawn. */
  off_ramps: FunnelStage[]
}

export interface ActivityBucket {
  /** Calendar month, "YYYY-MM", bucketed in UTC. */
  period: string
  applications_created: number
}

export interface ActivityResponse {
  /** Oldest month first, zero-filled for any month with no applications. */
  buckets: ActivityBucket[]
}

export interface InterviewResultCounts {
  pending: number
  passed: number
  failed: number
  cancelled: number
}

export interface InterviewAnalyticsResponse {
  total_interviews: number
  by_result: InterviewResultCounts
  /** null when no interview has a decided result yet. */
  pass_rate: number | null
}
