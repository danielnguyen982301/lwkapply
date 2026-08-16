import { defineStore } from 'pinia'
import { api, extractErrorMessage } from '@/lib/api'
import type { Document, DocumentListResponse } from '@/types/document'

type RequestStatus = 'idle' | 'loading' | 'error'

// Application <-> Document attachment (many-to-many —
// app/models/application_document.py): GET/POST/DELETE
// /applications/{application_id}/documents. Deliberately a separate store
// from stores/documents.ts: this one is scoped to one application's
// *attached* documents (used by DocumentsPanel.vue), the other is the
// user's whole document library (used by DocumentDirectoryView.vue and
// the AI Tools pickers). Attaching/detaching here never uploads or
// deletes the underlying document — see stores/documents.ts for that.
interface ApplicationDocumentsState {
  applicationId: string | null
  items: Document[]
  total: number
  page: number
  pageSize: number
  listStatus: RequestStatus
  listError: string | null

  attachStatus: RequestStatus
  attachError: string | null

  detachingId: string | null
  detachError: string | null
}

const DEFAULT_PAGE_SIZE = 20

export const useApplicationDocumentsStore = defineStore('applicationDocuments', {
  state: (): ApplicationDocumentsState => ({
    applicationId: null,
    items: [],
    total: 0,
    page: 1,
    pageSize: DEFAULT_PAGE_SIZE,
    listStatus: 'idle',
    listError: null,

    attachStatus: 'idle',
    attachError: null,

    detachingId: null,
    detachError: null,
  }),

  getters: {
    totalPages: (state): number => Math.max(1, Math.ceil(state.total / state.pageSize)),
  },

  actions: {
    async fetchAttached(applicationId: string, params: { page?: number } = {}) {
      this.listStatus = 'loading'
      this.listError = null
      const page = params.page ?? (this.applicationId === applicationId ? this.page : 1)
      try {
        const { data } = await api.get<DocumentListResponse>(
          `/applications/${applicationId}/documents`,
          { params: { page, page_size: this.pageSize } },
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

    async attach(applicationId: string, documentId: string): Promise<Document> {
      this.attachStatus = 'loading'
      this.attachError = null
      try {
        const { data } = await api.post<Document>(`/applications/${applicationId}/documents`, {
          document_id: documentId,
        })
        if (this.applicationId === applicationId) {
          this.items = [data, ...this.items]
          this.total += 1
        }
        this.attachStatus = 'idle'
        return data
      } catch (err) {
        this.attachStatus = 'error'
        this.attachError = extractErrorMessage(err)
        throw err
      }
    },

    /** Removes the link only — the document itself, and any other
     * application it's attached to, is untouched. */
    async detach(applicationId: string, documentId: string): Promise<void> {
      this.detachingId = documentId
      this.detachError = null
      try {
        await api.delete(`/applications/${applicationId}/documents/${documentId}`)
        this.items = this.items.filter((item) => item.id !== documentId)
        this.total = Math.max(0, this.total - 1)
        if (this.items.length === 0 && this.page > 1) {
          await this.fetchAttached(applicationId, { page: this.page - 1 })
        }
      } catch (err) {
        this.detachError = extractErrorMessage(err)
        throw err
      } finally {
        this.detachingId = null
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
      this.attachStatus = 'idle'
      this.attachError = null
      this.detachingId = null
      this.detachError = null
    },
  },
})
