import { defineStore } from 'pinia'
import { api, extractErrorMessage } from '@/lib/api'
import { isAiJobInFlight } from '@/lib/ai-ui'
import type {
  ResumeAnalysis,
  ResumeAnalysisCreatePayload,
  ResumeAnalysisListParams,
  ResumeAnalysisListResponse,
  ResumeAnalysisUpdatePayload,
} from '@/types/ai'

type RequestStatus = 'idle' | 'loading' | 'error'

// Polling cadence for a pending/processing analysis - see startPolling().
const POLL_INTERVAL_MS = 3000
const MAX_POLL_ATTEMPTS = 40 // ~2 minutes at the interval above

interface ResumeAnalysesState {
  items: ResumeAnalysis[]
  total: number
  page: number
  pageSize: number
  listStatus: RequestStatus
  listError: string | null

  // The analysis shown in a detail dialog (either just created, or opened
  // from the list) - not part of `items`' pagination.
  current: ResumeAnalysis | null
  currentStatus: RequestStatus
  currentError: string | null

  createStatus: RequestStatus
  createError: string | null

  // Renaming analysis_name - separate from createStatus/currentStatus,
  // same reasoning as stores/documents.ts's mutationStatus/mutationError
  // for its own single-field update (file_type).
  mutationStatus: RequestStatus
  mutationError: string | null

  // Only one in-flight poll at a time per store - starting a new one
  // clears any previous interval first. Views must call stopPolling() in
  // onUnmounted so a slow/background poll can't leak into a screen the
  // user has left, same reasoning stores/documents.ts's reset()-on-unmount
  // already follows for its own state.
  pollingHandle: ReturnType<typeof setInterval> | null
  pollingAttempts: number
  pollingTimedOut: boolean
}

const DEFAULT_PAGE_SIZE = 20

export const useResumeAnalysesStore = defineStore('resumeAnalyses', {
  state: (): ResumeAnalysesState => ({
    items: [],
    total: 0,
    page: 1,
    pageSize: DEFAULT_PAGE_SIZE,
    listStatus: 'idle',
    listError: null,

    current: null,
    currentStatus: 'idle',
    currentError: null,

    createStatus: 'idle',
    createError: null,

    mutationStatus: 'idle',
    mutationError: null,

    pollingHandle: null,
    pollingAttempts: 0,
    pollingTimedOut: false,
  }),

  getters: {
    totalPages: (state): number => Math.max(1, Math.ceil(state.total / state.pageSize)),
  },

  actions: {
    async fetchResumeAnalyses(params: ResumeAnalysisListParams = {}) {
      this.listStatus = 'loading'
      this.listError = null
      const page = params.page ?? this.page
      const pageSize = params.page_size ?? this.pageSize
      try {
        const { data } = await api.get<ResumeAnalysisListResponse>('/ai/resume-analyses', {
          params: {
            document_id: params.document_id || undefined,
            page,
            page_size: pageSize,
          },
        })
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

    async fetchOne(id: string): Promise<ResumeAnalysis> {
      this.currentStatus = 'loading'
      this.currentError = null
      try {
        const { data } = await api.get<ResumeAnalysis>(`/ai/resume-analyses/${id}`)
        this.current = data
        this.currentStatus = 'idle'
        if (!isAiJobInFlight(data.status)) this.stopPolling()
        return data
      } catch (err) {
        this.currentStatus = 'error'
        this.currentError = extractErrorMessage(err)
        throw err
      }
    },

    async create(payload: ResumeAnalysisCreatePayload): Promise<ResumeAnalysis> {
      this.createStatus = 'loading'
      this.createError = null
      try {
        const { data } = await api.post<ResumeAnalysis>('/ai/resume-analyses', payload)
        this.current = data
        this.createStatus = 'idle'
        if (isAiJobInFlight(data.status)) this.startPolling(data.id)
        return data
      } catch (err) {
        this.createStatus = 'error'
        this.createError = extractErrorMessage(err)
        throw err
      }
    },

    /** Patches items[] in place, same as stores/documents.ts's
     * updateDocument() - ResumeAnalysesView.vue's table reads straight off
     * `items`, so the row's label updates immediately without a full
     * re-fetch. */
    async updateAnalysisName(
      id: string,
      payload: ResumeAnalysisUpdatePayload,
    ): Promise<ResumeAnalysis> {
      this.mutationStatus = 'loading'
      this.mutationError = null
      try {
        const { data } = await api.patch<ResumeAnalysis>(`/ai/resume-analyses/${id}`, payload)
        const index = this.items.findIndex((item) => item.id === id)
        if (index !== -1) this.items[index] = data
        this.mutationStatus = 'idle'
        return data
      } catch (err) {
        this.mutationStatus = 'error'
        this.mutationError = extractErrorMessage(err)
        throw err
      }
    },

    startPolling(id: string) {
      this.stopPolling()
      this.pollingAttempts = 0
      this.pollingTimedOut = false
      this.pollingHandle = setInterval(() => {
        this.pollingAttempts += 1
        if (this.pollingAttempts > MAX_POLL_ATTEMPTS) {
          this.stopPolling()
          this.pollingTimedOut = true
          return
        }
        // A transient fetch failure shouldn't kill the whole poll loop -
        // currentError is already set for display by fetchOne(); just
        // retry on the next tick.
        this.fetchOne(id).catch(() => {})
      }, POLL_INTERVAL_MS)
    },

    stopPolling() {
      if (this.pollingHandle !== null) clearInterval(this.pollingHandle)
      this.pollingHandle = null
      this.pollingAttempts = 0
    },

    /**
     * Isolated: returns the most recent analysis for `documentId` directly,
     * without touching `items`/pagination. Used by ResumeAnalysisModal.vue
     * (opened from an application's Documents panel, a completely
     * different route/view than the AI Tools tab this store's `items`
     * otherwise backs) - keeping this separate means the modal can never
     * clobber, or be clobbered by, the AI Tools list's own state.
     */
    async fetchLatestForDocument(documentId: string): Promise<ResumeAnalysis | null> {
      const { data } = await api.get<ResumeAnalysisListResponse>('/ai/resume-analyses', {
        params: { document_id: documentId, page: 1, page_size: 1 },
      })
      return data.items[0] ?? null
    },

    /**
     * Isolated, like fetchLatestForDocument() above - live-searched variant
     * used by NewAtsScoreDialog.vue's Resume AutoComplete (same
     * debounced-search pattern as stores/documents.ts's searchDocuments()
     * and stores/applications.ts's searchApplications()). Server-side
     * status=completed + analysis_name search (GET /ai/resume-analyses'
     * `status`/`search` params), not a preloaded page capped at some size -
     * a user with more completed analyses than that cap could previously
     * never find the rest.
     */
    async searchCompletedForPicker(query: string, pageSize = 10): Promise<ResumeAnalysis[]> {
      const { data } = await api.get<ResumeAnalysisListResponse>('/ai/resume-analyses', {
        params: {
          status: 'completed',
          search: query || undefined,
          page: 1,
          page_size: pageSize,
        },
      })
      return data.items
    },

    /**
     * Isolated, like fetchApplicationById() (stores/applications.ts) -
     * returns one analysis directly without touching `current`/polling
     * state. Used by NewAtsScoreDialog.vue to preload the analysis behind
     * a prefilled ?resume_analysis_id=... (arriving from
     * ResumeAnalysesView.vue's "Score against a job" button) into the
     * Resume AutoComplete without disturbing the AI Tools list's own state.
     */
    async fetchResumeAnalysisById(id: string): Promise<ResumeAnalysis> {
      const { data } = await api.get<ResumeAnalysis>(`/ai/resume-analyses/${id}`)
      return data
    },

    /** Called on unmount of the AI Tools resume-analyses view. */
    reset() {
      this.items = []
      this.total = 0
      this.page = 1
      this.pageSize = DEFAULT_PAGE_SIZE
      this.listStatus = 'idle'
      this.listError = null
      this.current = null
      this.currentStatus = 'idle'
      this.currentError = null
      this.createStatus = 'idle'
      this.createError = null
      this.mutationStatus = 'idle'
      this.mutationError = null
      this.stopPolling()
      this.pollingTimedOut = false
    },
  },
})
