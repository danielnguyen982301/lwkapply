// Mirrors backend/app/models/document.py::DocumentType.
export type DocumentType = 'resume' | 'cover_letter' | 'other'

export const DOCUMENT_TYPES: readonly DocumentType[] = ['resume', 'cover_letter', 'other']

// Mirrors DocumentRead (backend/app/schemas/document.py). A document is a
// top-level, user-owned resource — no application_id here at all, since a
// document can be attached to zero, one, or several applications (see
// ApplicationDocument / stores/applicationDocuments.ts). Deliberately no
// file_url — the API never returns the permanent S3 key; call
// downloadDocument() (stores/documents.ts) to mint a short-lived presigned
// URL instead.
export interface Document {
  id: string
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

// Mirrors GET /documents' query params (app/api/v1/endpoints/documents.py).
// `search` matches file_name only (no more parent-application/company
// match — a document no longer has a single parent application). As with
// InterviewDirectoryParams' `result`, `null` means "clear the filter"
// (distinct from omitting the key, which means "keep whatever's already
// applied" — see fetchDocuments() in stores/documents.ts).
export interface DocumentListParams {
  search?: string | null
  file_type?: DocumentType | null
  page?: number
  page_size?: number
}

// --- Application <-> Document attachment ------------------------------------
// Mirrors ApplicationDocumentCreate (backend/app/schemas/document.py),
// used by stores/applicationDocuments.ts to attach an existing document to
// an application. Listing attached documents returns plain Document[]
// (DocumentListResponse) — no embedded application, symmetric with the
// plain top-level document shapes above.

export interface ApplicationDocumentCreatePayload {
  document_id: string
}
