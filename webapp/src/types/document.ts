import type { ApplicationStatus } from './application'

// Mirrors backend/app/models/document.py::DocumentType.
export type DocumentType = 'resume' | 'cover_letter' | 'other'

export const DOCUMENT_TYPES: readonly DocumentType[] = ['resume', 'cover_letter', 'other']

// Mirrors DocumentRead (backend/app/schemas/document.py). Deliberately no
// file_url — the API never returns the permanent S3 key; call
// downloadDocument() (documentsStore) to mint a short-lived presigned URL
// instead.
export interface Document {
  id: string
  application_id: string
  file_name: string
  file_type: DocumentType
  created_at: string
  updated_at: string
}

// Mirrors DocumentListResponse. Paginated, like Interviews (unlike
// Contacts' nested list).
export interface DocumentListResponse {
  items: Document[]
  total: number
  page: number
  page_size: number
}

export interface DocumentListParams {
  page?: number
  page_size?: number
}

// Mirrors DocumentUpdate: only file_type is user-editable after upload —
// file_name/file_url are set once at upload time and aren't client-writable.
export interface DocumentUpdatePayload {
  file_type: DocumentType
}

// Mirrors DocumentDownloadResponse (GET .../download).
export interface DocumentDownloadResponse {
  download_url: string
  expires_in_seconds: number
}

// --- Cross-application document directory ----------------------------------
// Mirrors ApplicationSummary / DocumentWithApplicationRead /
// DocumentWithApplicationListResponse (backend/app/schemas/document.py),
// returned only by GET /documents (the flat "all my documents" directory,
// not the nested per-application endpoints above). Same shape as
// ContactApplicationSummary/InterviewApplicationSummary in
// types/contact.ts / types/interview.ts.

export interface DocumentApplicationSummary {
  id: string
  company: string
  position: string
  status: ApplicationStatus
}

export interface DocumentWithApplication extends Document {
  application: DocumentApplicationSummary
}

export interface DocumentWithApplicationListResponse {
  items: DocumentWithApplication[]
  total: number
  page: number
  page_size: number
}

// Unlike Contacts (search only) or Interviews (result only), Document has
// both a name-like field (file_name) and an enum (file_type), so this
// directory supports both filters at once — matching the backend's
// `?search=` and `?file_type=` query params, which combine with AND. As
// with InterviewDirectoryParams' `result`, `null` means "clear the
// filter" (distinct from omitting the key, which means "keep whatever's
// already applied" — see fetchDocuments() in stores/documentDirectory.ts).
export interface DocumentDirectoryParams {
  search?: string | null
  file_type?: DocumentType | null
  page?: number
  page_size?: number
}
