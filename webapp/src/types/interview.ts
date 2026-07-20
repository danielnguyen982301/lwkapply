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
