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
