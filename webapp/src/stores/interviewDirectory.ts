import { defineStore } from 'pinia'
import { api, extractErrorMessage } from '@/lib/api'
import type {
  InterviewDirectoryParams,
  InterviewResult,
  InterviewWithApplication,
  InterviewWithApplicationListResponse,
} from '@/types/interview'

type RequestStatus = 'idle' | 'loading' | 'error'

// Deliberately a separate store from stores/interviews.ts, not an
// extension of it: that store is scoped to one application's interviews
// (used by InterviewsPanel.vue, has create/update/delete) while this one
// is a read-only, paginated, cross-application listing (used by the
// "Interviews" nav item) — different shape, different endpoint, different
// lifecycle. Mirrors stores/contactDirectory.ts, with `result` in place of
// Contacts' `search` (Interview has no name-like text field to match on).
interface InterviewDirectoryState {
  items: InterviewWithApplication[]
  total: number
  page: number
  pageSize: number
  result: InterviewResult | null
  listStatus: RequestStatus
  listError: string | null
}

export const useInterviewDirectoryStore = defineStore('interviewDirectory', {
  state: (): InterviewDirectoryState => ({
    items: [],
    total: 0,
    page: 1,
    pageSize: 20,
    result: null,
    listStatus: 'idle',
    listError: null,
  }),

  getters: {
    totalPages: (state): number => Math.max(1, Math.ceil(state.total / state.pageSize)),
  },

  actions: {
    /**
     * Fetches a page of the interview directory. Any param not passed
     * falls back to current store state (same convention as
     * fetchContacts() in stores/contactDirectory.ts) — pass `result: null`
     * explicitly to clear the filter.
     */
    async fetchInterviews(params: InterviewDirectoryParams = {}) {
      this.listStatus = 'loading'
      this.listError = null

      const result = params.result !== undefined ? params.result : this.result
      const page = params.page ?? this.page
      const pageSize = params.page_size ?? this.pageSize

      try {
        const { data } = await api.get<InterviewWithApplicationListResponse>('/interviews', {
          params: {
            result: result || undefined,
            page,
            page_size: pageSize,
          },
        })
        this.items = data.items
        this.total = data.total
        this.page = data.page
        this.pageSize = data.page_size
        this.result = result
        this.listStatus = 'idle'
      } catch (err) {
        this.listStatus = 'error'
        this.listError = extractErrorMessage(err)
        throw err
      }
    },

    /** Convenience wrapper: apply a new result filter and jump back to page 1. */
    async setResultFilter(result: InterviewResult | null) {
      await this.fetchInterviews({ result, page: 1 })
    },
  },
})
