// Mirrors ContactRead (backend/app/schemas/contact.py). Contacts are
// always nested under an application — there is no standalone /contacts
// endpoint — so every read includes the parent `application_id`.
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
