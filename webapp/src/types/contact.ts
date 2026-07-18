import type { ApplicationStatus } from './application'

// Mirrors ContactRead (backend/app/schemas/contact.py). Contacts are
// always created/edited nested under an application (see ContactCreatePayload
// / ContactUpdatePayload below) — but they can also be read via the flat
// cross-application directory endpoint, see ContactWithApplication below.
export interface Contact {
  id: string
  application_id: string
  name: string
  title: string | null
  email: string | null
  linkedin_url: string | null
  created_at: string
  updated_at: string
}

// Mirrors ContactListResponse. No pagination fields — list_contacts()
// returns every contact for the application in one shot (contact counts
// per application are small; unlike Applications there's no list/page_size
// query param on this endpoint).
export interface ContactListResponse {
  items: Contact[]
  total: number
}

// Mirrors ContactCreate, which is just ContactBase — every field the
// backend accepts on create. Only `name` is required.
export interface ContactCreatePayload {
  name: string
  title?: string | null
  email?: string | null
  linkedin_url?: string | null
}

// Mirrors ContactUpdate: identical fields, all optional. The backend uses
// `exclude_unset=True`, so only keys actually present in the request body
// are touched — omit a field here rather than sending `undefined`/`null`
// for "don't change this".
export type ContactUpdatePayload = Partial<ContactCreatePayload>

// --- Cross-application contact directory ---------------------------------
// Mirrors ApplicationSummary / ContactWithApplicationRead /
// ContactWithApplicationListResponse (backend/app/schemas/contact.py),
// returned only by GET /contacts (the flat "all my contacts" directory,
// not the nested per-application endpoints above).

export interface ContactApplicationSummary {
  id: string
  company: string
  position: string
  status: ApplicationStatus
}

export interface ContactWithApplication extends Contact {
  application: ContactApplicationSummary
}

export interface ContactWithApplicationListResponse {
  items: ContactWithApplication[]
  total: number
  page: number
  page_size: number
}

export interface ContactDirectoryParams {
  search?: string
  page?: number
  page_size?: number
}
