import { defineStore } from 'pinia'
import { api, extractErrorMessage } from '@/lib/api'
import type {
  ActivityResponse,
  FunnelResponse,
  InterviewAnalyticsResponse,
  SummaryResponse,
} from '@/types/analytics'

type RequestStatus = 'idle' | 'loading' | 'error'

interface AnalyticsState {
  summary: SummaryResponse | null
  summaryStatus: RequestStatus
  summaryError: string | null

  funnel: FunnelResponse | null
  funnelStatus: RequestStatus
  funnelError: string | null

  activity: ActivityResponse | null
  activityMonths: number
  activityStatus: RequestStatus
  activityError: string | null

  interviews: InterviewAnalyticsResponse | null
  interviewsStatus: RequestStatus
  interviewsError: string | null
}

// One store for all four GET /analytics/* endpoints, not four separate
// ones - unlike applicationContacts.ts vs contacts.ts (genuinely different
// resources, shapes, and lifecycles), these four are only ever read
// together by one view (AnalyticsDashboardView.vue), so a single store
// keeps that relationship visible instead of four near-identical copies
// of the same loading/error scaffolding.
export const useAnalyticsStore = defineStore('analytics', {
  state: (): AnalyticsState => ({
    summary: null,
    summaryStatus: 'idle',
    summaryError: null,

    funnel: null,
    funnelStatus: 'idle',
    funnelError: null,

    activity: null,
    activityMonths: 6,
    activityStatus: 'idle',
    activityError: null,

    interviews: null,
    interviewsStatus: 'idle',
    interviewsError: null,
  }),

  actions: {
    async fetchSummary() {
      this.summaryStatus = 'loading'
      this.summaryError = null
      try {
        const { data } = await api.get<SummaryResponse>('/analytics/summary')
        this.summary = data
        this.summaryStatus = 'idle'
      } catch (err) {
        this.summaryStatus = 'error'
        this.summaryError = extractErrorMessage(err)
        throw err
      }
    },

    async fetchFunnel() {
      this.funnelStatus = 'loading'
      this.funnelError = null
      try {
        const { data } = await api.get<FunnelResponse>('/analytics/funnel')
        this.funnel = data
        this.funnelStatus = 'idle'
      } catch (err) {
        this.funnelStatus = 'error'
        this.funnelError = extractErrorMessage(err)
        throw err
      }
    },

    /**
     * `months` defaults to whatever's already in state (initially 6) -
     * pass it explicitly to change the window. Same "omit = keep current
     * value" convention as fetchContacts()'s `search` param in
     * stores/contacts.ts.
     */
    async fetchActivity(months?: number) {
      const requestedMonths = months ?? this.activityMonths
      this.activityStatus = 'loading'
      this.activityError = null
      try {
        const { data } = await api.get<ActivityResponse>('/analytics/activity', {
          params: { months: requestedMonths },
        })
        this.activity = data
        this.activityMonths = requestedMonths
        this.activityStatus = 'idle'
      } catch (err) {
        this.activityStatus = 'error'
        this.activityError = extractErrorMessage(err)
        throw err
      }
    },

    async fetchInterviews() {
      this.interviewsStatus = 'loading'
      this.interviewsError = null
      try {
        const { data } = await api.get<InterviewAnalyticsResponse>('/analytics/interviews')
        this.interviews = data
        this.interviewsStatus = 'idle'
      } catch (err) {
        this.interviewsStatus = 'error'
        this.interviewsError = extractErrorMessage(err)
        throw err
      }
    },

    /**
     * Fires all four independently rather than sequentially - one slow
     * or failing endpoint shouldn't hold up the other three sections
     * from rendering. Each individual fetcher already catches and
     * records its own error, so allSettled() is enough here; nothing
     * needs to propagate back to the caller.
     */
    async fetchAll() {
      await Promise.allSettled([
        this.fetchSummary(),
        this.fetchFunnel(),
        this.fetchActivity(),
        this.fetchInterviews(),
      ])
    },
  },
})
