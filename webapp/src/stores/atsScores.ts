import { defineStore } from 'pinia'
import { api, extractErrorMessage } from '@/lib/api'
import { isAiJobInFlight } from '@/lib/ai-ui'
import type {
  AtsScore,
  AtsScoreCreatePayload,
  AtsScoreListParams,
  AtsScoreListResponse,
} from '@/types/ai'

type RequestStatus = 'idle' | 'loading' | 'error'

// Same polling shape as stores/resumeAnalyses.ts - see that file for the
// full reasoning (cadence, cap, why views must call stopPolling() on unmount).
const POLL_INTERVAL_MS = 3000
const MAX_POLL_ATTEMPTS = 40

interface AtsScoresState {
  items: AtsScore[]
  total: number
  page: number
  pageSize: number
  listStatus: RequestStatus
  listError: string | null

  current: AtsScore | null
  currentStatus: RequestStatus
  currentError: string | null

  createStatus: RequestStatus
  createError: string | null

  pollingHandle: ReturnType<typeof setInterval> | null
  pollingAttempts: number
  pollingTimedOut: boolean
}

const DEFAULT_PAGE_SIZE = 20

export const useAtsScoresStore = defineStore('atsScores', {
  state: (): AtsScoresState => ({
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

    pollingHandle: null,
    pollingAttempts: 0,
    pollingTimedOut: false,
  }),

  getters: {
    totalPages: (state): number => Math.max(1, Math.ceil(state.total / state.pageSize)),
  },

  actions: {
    async fetchAtsScores(params: AtsScoreListParams = {}) {
      this.listStatus = 'loading'
      this.listError = null
      const page = params.page ?? this.page
      const pageSize = params.page_size ?? this.pageSize
      try {
        const { data } = await api.get<AtsScoreListResponse>('/ai/ats-scores', {
          params: {
            resume_analysis_id: params.resume_analysis_id || undefined,
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

    async fetchOne(id: string): Promise<AtsScore> {
      this.currentStatus = 'loading'
      this.currentError = null
      try {
        const { data } = await api.get<AtsScore>(`/ai/ats-scores/${id}`)
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

    async create(payload: AtsScoreCreatePayload): Promise<AtsScore> {
      this.createStatus = 'loading'
      this.createError = null
      try {
        const { data } = await api.post<AtsScore>('/ai/ats-scores', payload)
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
        this.fetchOne(id).catch(() => {})
      }, POLL_INTERVAL_MS)
    },

    stopPolling() {
      if (this.pollingHandle !== null) clearInterval(this.pollingHandle)
      this.pollingHandle = null
      this.pollingAttempts = 0
    },

    /**
     * Isolated, like resumeAnalyses.fetchLatestForDocument() - returns the
     * most recent score for resumeAnalysisId directly, without touching
     * `items`/pagination. The backend's GET /ai/ats-scores filters by
     * resume_analysis_id directly now and already orders by
     * created_at desc, so page_size 1 is enough - no client-side `.find()`
     * needed any more. Used by ResumeAnalysisModal.vue.
     */
    async fetchLatestForResumeAnalysis(resumeAnalysisId: string): Promise<AtsScore | null> {
      const { data } = await api.get<AtsScoreListResponse>('/ai/ats-scores', {
        params: { resume_analysis_id: resumeAnalysisId, page: 1, page_size: 1 },
      })
      return data.items[0] ?? null
    },

    /** Called on unmount of the AI Tools ats-scores view. */
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
      this.stopPolling()
      this.pollingTimedOut = false
    },
  },
})
