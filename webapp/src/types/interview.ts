import type { ApplicationStatus } from './application'

// Mirrors backend/app/models/interview.py::InterviewType / InterviewResult.
export type InterviewType =
  'phone_screen' | 'technical' | 'behavioral' | 'onsite' | 'final' | 'other'

export type InterviewResult = 'pending' | 'passed' | 'failed' | 'cancelled'

// Order matters here: used as the left-to-right/top-to-bottom order for
// select options, mirroring the ApplicationStatus convention.
export const INTERVIEW_TYPES: readonly InterviewType[] = [
  'phone_screen',
  'technical',
  'behavioral',
  'onsite',
  'final',
  'other',
]

export const INTERVIEW_RESULTS: readonly InterviewResult[] = [
  'pending',
  'passed',
  'failed',
  'cancelled',
]

// Mirrors InterviewRead (backend/app/schemas/interview.py).
export interface Interview {
  id: string
  application_id: string
  type: InterviewType
  /** ISO datetime string (backend `datetime`, timezone-aware). */
  scheduled_at: string
  duration_minutes: number | null
  feedback: string | null
  result: InterviewResult
  created_at: string
  updated_at: string
}

// Mirrors InterviewListResponse. Unlike Contacts, this endpoint IS
// paginated (see backend/app/api/v1/endpoints/interviews.py).
export interface InterviewListResponse {
  items: Interview[]
  total: number
  page: number
  page_size: number
}

export interface InterviewListParams {
  page?: number
  page_size?: number
}

// Mirrors InterviewCreate, which is just InterviewBase. `result` is
// optional since the backend defaults it to `pending`.
export interface InterviewCreatePayload {
  type: InterviewType
  scheduled_at: string
  duration_minutes?: number | null
  feedback?: string | null
  result?: InterviewResult
}

// Mirrors InterviewUpdate: identical fields, all optional. The backend
// uses `exclude_unset=True`, so only keys actually present in the request
// body are touched — omit a field here rather than sending `undefined`/
// `null` for "don't change this".
export type InterviewUpdatePayload = Partial<InterviewCreatePayload>

// --- Cross-application interview directory --------------------------------
// Mirrors ApplicationSummary / InterviewWithApplicationRead /
// InterviewWithApplicationListResponse (backend/app/schemas/interview.py),
// returned only by GET /interviews (the flat "all my interviews" directory,
// not the nested per-application endpoints above). Same shape as
// ContactApplicationSummary / ContactWithApplication in types/contact.ts.

export interface InterviewApplicationSummary {
  id: string
  company: string
  position: string
  status: ApplicationStatus
}

export interface InterviewWithApplication extends Interview {
  application: InterviewApplicationSummary
}

export interface InterviewWithApplicationListResponse {
  items: InterviewWithApplication[]
  total: number
  page: number
  page_size: number
}

// Unlike ContactDirectoryParams' `search` (Contact has a name field to
// match against), Interview has no text field — the equivalent filter is
// `result`, matching the backend's `?result=` query param. `null` means
// "clear the filter" (distinct from omitting the key, which means "keep
// whatever's already applied" — see fetchInterviews() in
// stores/interviewDirectory.ts).
export interface InterviewDirectoryParams {
  result?: InterviewResult | null
  page?: number
  page_size?: number
}
