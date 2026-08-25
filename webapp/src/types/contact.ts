// Mirrors ContactRead (backend/app/schemas/contact.py). A contact is a
// top-level, user-owned resource - no application_id here at all, since a
// contact can be attached to zero, one, or several applications (see
// ApplicationContact / stores/applicationContacts.ts).
export interface Contact {
  id: string
  name: string
  title: string | null
  email: string | null
  linkedin_url: string | null
  created_at: string
  updated_at: string
}

// Mirrors ContactListResponse. Paginated, like Documents.
export interface ContactListResponse {
  items: Contact[]
  total: number
  page: number
  page_size: number
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

// Mirrors GET /contacts' query params (app/api/v1/endpoints/contacts.py).
// `search` matches `name` only. As with DocumentListParams' `search`,
// `null` means "clear the filter" (distinct from omitting the key, which
// means "keep whatever's already applied" - see fetchContacts() in
// stores/contacts.ts).
export interface ContactListParams {
  search?: string | null
  page?: number
  page_size?: number
}

// --- Application <-> Contact attachment ------------------------------------
// Mirrors ApplicationContactCreate (backend/app/schemas/contact.py), used
// by stores/applicationContacts.ts to attach an existing contact to an
// application. Listing attached contacts returns plain Contact[]
// (ContactListResponse) - no embedded application, symmetric with the
// plain top-level contact shape above.

export interface ApplicationContactCreatePayload {
  contact_id: string
}
