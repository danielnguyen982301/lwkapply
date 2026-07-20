import { defineStore } from 'pinia'
import { api, extractErrorMessage } from '@/lib/api'
import type {
  Interview,
  InterviewCreatePayload,
  InterviewListParams,
  InterviewListResponse,
  InterviewUpdatePayload,
} from '@/types/interview'

type RequestStatus = 'idle' | 'loading' | 'error'

interface InterviewsState {
  // Like the Contacts store, Interviews are always viewed in the context
  // of a single application (a panel on the Application detail page).
  // `applicationId` records which application `items` belongs to, so a
  // stale response for a previous application can't clobber the panel
  // after the user has already navigated to a different one.
  applicationId: string | null
  items: Interview[]
  total: number
  page: number
  pageSize: number
  listStatus: RequestStatus
  listError: string | null

  mutationStatus: RequestStatus
  mutationError: string | null
}

const DEFAULT_PAGE_SIZE = 20

export const useInterviewsStore = defineStore('interviews', {
  state: (): InterviewsState => ({
    applicationId: null,
    items: [],
    total: 0,
    page: 1,
    pageSize: DEFAULT_PAGE_SIZE,
    listStatus: 'idle',
    listError: null,

    mutationStatus: 'idle',
    mutationError: null,
  }),

  getters: {
    totalPages: (state): number => Math.max(1, Math.ceil(state.total / state.pageSize)),
  },

  actions: {
    async fetchInterviews(applicationId: string, params: InterviewListParams = {}) {
      this.listStatus = 'loading'
      this.listError = null
      const page = params.page ?? (this.applicationId === applicationId ? this.page : 1)
      const pageSize = params.page_size ?? this.pageSize
      try {
        const { data } = await api.get<InterviewListResponse>(
          `/applications/${applicationId}/interviews`,
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

    async createInterview(
      applicationId: string,
      payload: InterviewCreatePayload,
    ): Promise<Interview> {
      this.mutationStatus = 'loading'
      this.mutationError = null
      try {
        const { data } = await api.post<Interview>(
          `/applications/${applicationId}/interviews`,
          payload,
        )
        // The list is server-sorted by scheduled_at ascending, so a new
        // interview's position can't be guessed client-side — refetch the
        // current page rather than splice it in somewhere possibly wrong.
        if (this.applicationId === applicationId) {
          await this.fetchInterviews(applicationId, { page: this.page })
        }
        this.mutationStatus = 'idle'
        return data
      } catch (err) {
        this.mutationStatus = 'error'
        this.mutationError = extractErrorMessage(err)
        throw err
      }
    },

    async updateInterview(
      applicationId: string,
      interviewId: string,
      payload: InterviewUpdatePayload,
    ): Promise<Interview> {
      this.mutationStatus = 'loading'
      this.mutationError = null
      try {
        const { data } = await api.patch<Interview>(
          `/applications/${applicationId}/interviews/${interviewId}`,
          payload,
        )
        // scheduled_at may have changed, which can change sort order too —
        // refetch for the same reason as create, rather than patch in place.
        if (this.applicationId === applicationId) {
          await this.fetchInterviews(applicationId, { page: this.page })
        }
        this.mutationStatus = 'idle'
        return data
      } catch (err) {
        this.mutationStatus = 'error'
        this.mutationError = extractErrorMessage(err)
        throw err
      }
    },

    async deleteInterview(applicationId: string, interviewId: string): Promise<void> {
      this.mutationStatus = 'loading'
      this.mutationError = null
      try {
        await api.delete(`/applications/${applicationId}/interviews/${interviewId}`)
        this.items = this.items.filter((item) => item.id !== interviewId)
        this.total = Math.max(0, this.total - 1)
        // Deleting the last item on a page beyond the first would otherwise
        // leave the panel showing an empty page with results still above it.
        if (this.items.length === 0 && this.page > 1) {
          await this.fetchInterviews(applicationId, { page: this.page - 1 })
        }
        this.mutationStatus = 'idle'
      } catch (err) {
        this.mutationStatus = 'error'
        this.mutationError = extractErrorMessage(err)
        throw err
      }
    },

    /** Called on unmount of the Interviews panel so switching applications never briefly shows stale interviews. */
    reset() {
      this.applicationId = null
      this.items = []
      this.total = 0
      this.page = 1
      this.pageSize = DEFAULT_PAGE_SIZE
      this.listStatus = 'idle'
      this.listError = null
      this.mutationStatus = 'idle'
      this.mutationError = null
    },
  },
})
