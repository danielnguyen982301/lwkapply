import { defineStore } from 'pinia'
import { api, extractErrorMessage } from '@/lib/api'
import type {
  Document,
  DocumentDownloadResponse,
  DocumentListParams,
  DocumentListResponse,
  DocumentType,
  DocumentUpdatePayload,
} from '@/types/document'

type RequestStatus = 'idle' | 'loading' | 'error'

interface DocumentsState {
  // Same application-scoping pattern as Contacts/Interviews.
  applicationId: string | null
  items: Document[]
  total: number
  page: number
  pageSize: number
  listStatus: RequestStatus
  listError: string | null

  // Separate from mutationStatus: an upload is a multipart request that
  // can take noticeably longer than a JSON PATCH/DELETE, so it gets its
  // own status/error rather than making an in-flight upload look like an
  // edit or delete happening elsewhere in the panel.
  uploadStatus: RequestStatus
  uploadError: string | null

  mutationStatus: RequestStatus
  mutationError: string | null

  // Presigned download URLs are minted per click, not stored on the
  // Document itself (the API never returns a permanent file_url — see
  // DocumentRead). `downloadingId` tracks which single row is in flight
  // so the panel can show a per-row spinner instead of a global one.
  downloadingId: string | null
  downloadError: string | null
}

const DEFAULT_PAGE_SIZE = 20

export const useDocumentsStore = defineStore('documents', {
  state: (): DocumentsState => ({
    applicationId: null,
    items: [],
    total: 0,
    page: 1,
    pageSize: DEFAULT_PAGE_SIZE,
    listStatus: 'idle',
    listError: null,

    uploadStatus: 'idle',
    uploadError: null,

    mutationStatus: 'idle',
    mutationError: null,

    downloadingId: null,
    downloadError: null,
  }),

  getters: {
    totalPages: (state): number => Math.max(1, Math.ceil(state.total / state.pageSize)),
  },

  actions: {
    async fetchDocuments(applicationId: string, params: DocumentListParams = {}) {
      this.listStatus = 'loading'
      this.listError = null
      const page = params.page ?? (this.applicationId === applicationId ? this.page : 1)
      const pageSize = params.page_size ?? this.pageSize
      try {
        const { data } = await api.get<DocumentListResponse>(
          `/applications/${applicationId}/documents`,
          { params: { page, page_size: pageSize } },
        )
        this.applicationId = applicationId
        this.items = data.items
        this.total = data.total
        this.page = data.page
        this.pageSize = data.page_size
        this.listStatus = 'idle'
      } catch (err) {
        this.listStatus = 'error'
        this.listError = extractErrorMessage(err)
        throw err
      }
    },

    async uploadDocument(
      applicationId: string,
      file: File,
      fileType: DocumentType,
    ): Promise<Document> {
      this.uploadStatus = 'loading'
      this.uploadError = null
      const formData = new FormData()
      formData.append('file', file)
      formData.append('file_type', fileType)
      try {
        const { data } = await api.post<Document>(
          `/applications/${applicationId}/documents`,
          formData,
          { headers: { 'Content-Type': 'multipart/form-data' } },
        )
        if (this.applicationId === applicationId) {
          this.items = [data, ...this.items]
          this.total += 1
        }
        this.uploadStatus = 'idle'
        return data
      } catch (err) {
        this.uploadStatus = 'error'
        this.uploadError = extractErrorMessage(err)
        throw err
      }
    },

    async updateDocument(
      applicationId: string,
      documentId: string,
      payload: DocumentUpdatePayload,
    ): Promise<Document> {
      this.mutationStatus = 'loading'
      this.mutationError = null
      try {
        const { data } = await api.patch<Document>(
          `/applications/${applicationId}/documents/${documentId}`,
          payload,
        )
        const index = this.items.findIndex((item) => item.id === documentId)
        if (index !== -1) this.items[index] = data
        this.mutationStatus = 'idle'
        return data
      } catch (err) {
        this.mutationStatus = 'error'
        this.mutationError = extractErrorMessage(err)
        throw err
      }
    },

    /** Mints a short-lived presigned S3 URL and opens it in a new tab. */
    async downloadDocument(applicationId: string, documentId: string): Promise<void> {
      this.downloadingId = documentId
      this.downloadError = null
      try {
        const { data } = await api.get<DocumentDownloadResponse>(
          `/applications/${applicationId}/documents/${documentId}/download`,
        )
        // The presigned URL points straight at S3, not the API — open it
        // directly rather than routing it back through the axios client.
        window.open(data.download_url, '_blank', 'noopener,noreferrer')
      } catch (err) {
        this.downloadError = extractErrorMessage(err)
        throw err
      } finally {
        this.downloadingId = null
      }
    },

    async deleteDocument(applicationId: string, documentId: string): Promise<void> {
      this.mutationStatus = 'loading'
      this.mutationError = null
      try {
        await api.delete(`/applications/${applicationId}/documents/${documentId}`)
        this.items = this.items.filter((item) => item.id !== documentId)
        this.total = Math.max(0, this.total - 1)
        if (this.items.length === 0 && this.page > 1) {
          await this.fetchDocuments(applicationId, { page: this.page - 1 })
        }
        this.mutationStatus = 'idle'
      } catch (err) {
        this.mutationStatus = 'error'
        this.mutationError = extractErrorMessage(err)
        throw err
      }
    },

    /** Called on unmount of the Documents panel so switching applications never briefly shows stale documents. */
    reset() {
      this.applicationId = null
      this.items = []
      this.total = 0
      this.page = 1
      this.pageSize = DEFAULT_PAGE_SIZE
      this.listStatus = 'idle'
      this.listError = null
      this.uploadStatus = 'idle'
      this.uploadError = null
      this.mutationStatus = 'idle'
      this.mutationError = null
      this.downloadingId = null
      this.downloadError = null
    },
  },
})
