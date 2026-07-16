// Mirrors backend/app/models/application.py::ApplicationStatus.
// Kept as a plain string-literal union (not a TS enum) so it serializes
// identically to the JSON the API sends/expects — no extra mapping layer.
export type ApplicationStatus =
  | 'saved'
  | 'applied'
  | 'phone_screen'
  | 'interviewing'
  | 'offer'
  | 'rejected'
  | 'withdrawn'
  | 'accepted'

// Order matters here: this is the left-to-right column order the Kanban
// board (Phase 2, later step) will use, and a sensible top-to-bottom order
// for a <select> filter too.
export const APPLICATION_STATUSES: readonly ApplicationStatus[] = [
  'saved',
  'applied',
  'phone_screen',
  'interviewing',
  'offer',
  'accepted',
  'rejected',
  'withdrawn',
]

export const APPLICATION_STATUS_LABELS: Record<ApplicationStatus, string> = {
  saved: 'Saved',
  applied: 'Applied',
  phone_screen: 'Phone Screen',
  interviewing: 'Interviewing',
  offer: 'Offer',
  accepted: 'Accepted',
  rejected: 'Rejected',
  withdrawn: 'Withdrawn',
}

// Mirrors ApplicationRead (backend/app/schemas/application.py).
export interface Application {
  id: string
  user_id: string
  company: string
  position: string
  location: string | null
  status: ApplicationStatus
  salary_min: number | null
  salary_max: number | null
  /** ISO date string, e.g. "2026-07-16" (backend `date`, not `datetime`). */
  applied_date: string | null
  job_url: string | null
  notes: string | null
  created_at: string
  updated_at: string
}

// Mirrors ApplicationListResponse.
export interface ApplicationListResponse {
  items: Application[]
  total: number
  page: number
  page_size: number
}

// Query params accepted by GET /applications (backend uses `status` as the
// query alias, `status_filter` is just the Python-side param name).
//
// `status` is `ApplicationStatus | null | undefined`, not just optional:
// - `undefined` (key omitted) => "don't change this filter"
// - `null`                    => "explicitly clear this filter"
// This distinction matters for partial updates like `fetchApplications({ page: 2 })`,
// which should keep whatever status filter is already active rather than
// wiping it.
export interface ApplicationListParams {
  status?: ApplicationStatus | null
  search?: string
  page?: number
  page_size?: number
}

// Mirrors ApplicationCreate, which is just ApplicationBase — every field
// the backend accepts on create. `status` is optional since the backend
// defaults it to `saved`.
export interface ApplicationCreatePayload {
  company: string
  position: string
  location?: string | null
  status?: ApplicationStatus
  salary_min?: number | null
  salary_max?: number | null
  applied_date?: string | null
  job_url?: string | null
  notes?: string | null
}

// Mirrors ApplicationUpdate: identical fields, all optional. The backend
// uses `exclude_unset=True`, so only keys actually present in the request
// body are touched — omit a field here rather than sending `undefined`/
// `null` for "don't change this".
export type ApplicationUpdatePayload = Partial<ApplicationCreatePayload>
