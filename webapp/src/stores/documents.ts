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

// The top-level document library: every document the user owns,
// independent of any application (GET/POST /documents,
// GET/PATCH/DELETE/download /documents/{id}) — a document is no longer
// created in the context of one application, and can be attached to zero,
// one, or several (see stores/applicationDocuments.ts for the attach/
// detach/list-attached side of that, used by DocumentsPanel.vue).
interface DocumentsState {
  items: Document[]
  total: number
  page: number
  pageSize: number
  search: string
  fileType: DocumentType | null
  listStatus: RequestStatus
  listError: string | null

  // Separate from mutationStatus: an upload is a multipart request that
  // can take noticeably longer than a JSON PATCH/DELETE, so it gets its
  // own status/error rather than making an in-flight upload look like an
  // edit or delete happening elsewhere.
  uploadStatus: RequestStatus
  uploadError: string | null

  mutationStatus: RequestStatus
  mutationError: string | null

  // Presigned download URLs are minted per click, not stored on the
  // Document itself (the API never returns a permanent file_url — see
  // DocumentRead). `downloadingId` tracks which single row is in flight
  // so the UI can show a per-row spinner instead of a global one.
  downloadingId: string | null
  downloadError: string | null
}

const DEFAULT_PAGE_SIZE = 20

export const useDocumentsStore = defineStore('documents', {
  state: (): DocumentsState => ({
    items: [],
    total: 0,
    page: 1,
    pageSize: DEFAULT_PAGE_SIZE,
    search: '',
    fileType: null,
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
    /**
     * Fetches a page of the document library. Any param not passed falls
     * back to current store state (same convention as fetchInterviews() in
     * stores/interviewDirectory.ts) — pass `search: null`/`file_type: null`
     * explicitly to clear that filter.
     */
    async fetchDocuments(params: DocumentListParams = {}) {
      this.listStatus = 'loading'
      this.listError = null

      const search = params.search !== undefined ? (params.search ?? '') : this.search
      const fileType = params.file_type !== undefined ? params.file_type : this.fileType
      const page = params.page ?? this.page
      const pageSize = params.page_size ?? this.pageSize

      try {
        const { data } = await api.get<DocumentListResponse>('/documents', {
          params: {
            search: search || undefined,
            file_type: fileType || undefined,
            page,
            page_size: pageSize,
          },
        })
        this.items = data.items
        this.total = data.total
        this.page = data.page
        this.pageSize = data.page_size
        this.search = search
        this.fileType = fileType
        this.listStatus = 'idle'
      } catch (err) {
        this.listStatus = 'error'
        this.listError = extractErrorMessage(err)
        throw err
      }
    },

    /** Convenience wrapper: apply a new search term and jump back to page 1. */
    async setSearch(search: string) {
      await this.fetchDocuments({ search, page: 1 })
    },

    /** Convenience wrapper: apply a new file-type filter and jump back to page 1. */
    async setFileTypeFilter(fileType: DocumentType | null) {
      await this.fetchDocuments({ file_type: fileType, page: 1 })
    },

    /**
     * Isolated: returns matching documents directly, without touching
     * `items`/`page`/`search`/`fileType`. Used by
     * components/ai/ResumeDocumentPicker.vue for a live debounced search
     * (default pageSize=10 - autocomplete suggestions, not a real listing)
     * and by the AI Tools views to build a document_id -> file_name label
     * lookup (a larger pageSize, since they want every resume the user
     * has, not just top matches). Reusing fetchDocuments() for either
     * would clobber whatever the actual Document Library view has set,
     * since both are reachable in the same session without a full reload.
     */
    async searchDocuments(
      query: string,
      fileType: DocumentType | null = null,
      pageSize = 10,
    ): Promise<Document[]> {
      const { data } = await api.get<DocumentListResponse>('/documents', {
        params: {
          search: query || undefined,
          file_type: fileType || undefined,
          page: 1,
          page_size: pageSize,
        },
      })
      return data.items
    },

    async uploadDocument(file: File, fileType: DocumentType): Promise<Document> {
      this.uploadStatus = 'loading'
      this.uploadError = null
      const formData = new FormData()
      formData.append('file', file)
      formData.append('file_type', fileType)
      try {
        const { data } = await api.post<Document>('/documents', formData, {
          headers: { 'Content-Type': 'multipart/form-data' },
        })
        this.items = [data, ...this.items]
        this.total += 1
        this.uploadStatus = 'idle'
        return data
      } catch (err) {
        this.uploadStatus = 'error'
        this.uploadError = extractErrorMessage(err)
        throw err
      }
    },

    async updateDocument(documentId: string, payload: DocumentUpdatePayload): Promise<Document> {
      this.mutationStatus = 'loading'
      this.mutationError = null
      try {
        const { data } = await api.patch<Document>(`/documents/${documentId}`, payload)
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

    /** Mints a short-lived presigned R2 URL and opens it in a new tab. */
    async downloadDocument(documentId: string): Promise<void> {
      this.downloadingId = documentId
      this.downloadError = null
      try {
        const { data } = await api.get<DocumentDownloadResponse>(
          `/documents/${documentId}/download`,
        )
        // The presigned URL points straight at R2, not the API — open it
        // directly rather than routing it back through the axios client.
        window.open(data.download_url, '_blank', 'noopener,noreferrer')
      } catch (err) {
        this.downloadError = extractErrorMessage(err)
        throw err
      } finally {
        this.downloadingId = null
      }
    },

    /** Permanently deletes the document (and, server-side, every
     * application it was attached to loses that link — see
     * ApplicationDocument's cascade). Not the same as detaching from one
     * application; see stores/applicationDocuments.ts for that. */
    async deleteDocument(documentId: string): Promise<void> {
      this.mutationStatus = 'loading'
      this.mutationError = null
      try {
        await api.delete(`/documents/${documentId}`)
        this.items = this.items.filter((item) => item.id !== documentId)
        this.total = Math.max(0, this.total - 1)
        if (this.items.length === 0 && this.page > 1) {
          await this.fetchDocuments({ page: this.page - 1 })
        }
        this.mutationStatus = 'idle'
      } catch (err) {
        this.mutationStatus = 'error'
        this.mutationError = extractErrorMessage(err)
        throw err
      }
    },
  },
})
