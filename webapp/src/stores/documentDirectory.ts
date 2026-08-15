import { defineStore } from 'pinia'
import { api, extractErrorMessage } from '@/lib/api'
import type {
  DocumentDirectoryParams,
  DocumentType,
  DocumentWithApplication,
  DocumentWithApplicationListResponse,
} from '@/types/document'

type RequestStatus = 'idle' | 'loading' | 'error'

// Deliberately a separate store from stores/documents.ts, not an
// extension of it: that store is scoped to one application's documents
// (used by DocumentsPanel.vue, has upload/update/delete/download) while
// this one is a read-only, paginated, cross-application listing (used by
// the "Documents" nav item) — different shape, different endpoint,
// different lifecycle. Mirrors stores/contactDirectory.ts /
// stores/interviewDirectory.ts, but tracks both `search` (like Contacts)
// and `fileType` (like Interviews' `result`) since Document has both a
// name-like field and an enum to filter on.
interface DocumentDirectoryState {
  items: DocumentWithApplication[]
  total: number
  page: number
  pageSize: number
  search: string
  fileType: DocumentType | null
  listStatus: RequestStatus
  listError: string | null
}

export const useDocumentDirectoryStore = defineStore('documentDirectory', {
  state: (): DocumentDirectoryState => ({
    items: [],
    total: 0,
    page: 1,
    pageSize: 20,
    search: '',
    fileType: null,
    listStatus: 'idle',
    listError: null,
  }),

  getters: {
    totalPages: (state): number => Math.max(1, Math.ceil(state.total / state.pageSize)),
  },

  actions: {
    /**
     * Fetches a page of the document directory. Any param not passed
     * falls back to current store state (same convention as
     * fetchInterviews() in stores/interviewDirectory.ts) — pass
     * `search: null`/`file_type: null` explicitly to clear that filter.
     */
    async fetchDocuments(params: DocumentDirectoryParams = {}) {
      this.listStatus = 'loading'
      this.listError = null

      const search = params.search !== undefined ? (params.search ?? '') : this.search
      const fileType = params.file_type !== undefined ? params.file_type : this.fileType
      const page = params.page ?? this.page
      const pageSize = params.page_size ?? this.pageSize

      try {
        const { data } = await api.get<DocumentWithApplicationListResponse>('/documents', {
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

    /**
     * Isolated: returns matching resume documents directly, without
     * touching `items`/`page`/`search`/`fileType`. Used by
     * components/ai/ResumeDocumentPicker.vue for a live debounced search
     * (default pageSize=10 - autocomplete suggestions, not a real listing)
     * and by ResumeAnalysesView.vue to build its document_id -> file_name
     * label lookup (a larger pageSize, since it wants every resume the
     * user has, not just top matches). Reusing fetchDocuments() for either
     * would clobber whatever the actual Documents directory view has set,
     * since both are reachable in the same session without a full reload.
     */
    async searchResumeDocuments(query: string, pageSize = 10): Promise<DocumentWithApplication[]> {
      const { data } = await api.get<DocumentWithApplicationListResponse>('/documents', {
        params: { search: query || undefined, file_type: 'resume', page: 1, page_size: pageSize },
      })
      return data.items
    },

    /** Convenience wrapper: apply a new file-type filter and jump back to page 1. */
    async setFileTypeFilter(fileType: DocumentType | null) {
      await this.fetchDocuments({ file_type: fileType, page: 1 })
    },
  },
})
