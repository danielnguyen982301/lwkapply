import { defineStore } from 'pinia'
import { api, extractErrorMessage } from '@/lib/api'
import type {
  Application,
  ApplicationCreatePayload,
  ApplicationListParams,
  ApplicationListResponse,
  ApplicationStatus,
  ApplicationUpdatePayload,
} from '@/types/application'

type RequestStatus = 'idle' | 'loading' | 'error'

interface ApplicationsState {
  // --- list state (Application List view, Kanban board) ---
  items: Application[]
  total: number
  page: number
  pageSize: number
  filters: { status: ApplicationStatus | null; search: string }
  listStatus: RequestStatus
  listError: string | null

  // --- single-application state (Application Details view) ---
  current: Application | null
  currentStatus: RequestStatus
  currentError: string | null

  // --- board state (Kanban view) — deliberately separate from the
  // paginated `items`/`page`/`pageSize` above. The board wants every
  // application in one shot, grouped client-side by status; reusing the
  // list's pagination fields would mean switching between List and Board
  // clobbers whichever page size the other view had set. ---
  boardItems: Application[]
  boardTotal: number
  boardStatus: RequestStatus
  boardError: string | null

  // --- create/update/delete state (shared by any form/action UI) ---
  mutationStatus: RequestStatus
  mutationError: string | null
}

/** Cap for the board's single-page fetch — see fetchBoard() for why. */
const BOARD_PAGE_SIZE = 100

export const useApplicationsStore = defineStore('applications', {
  state: (): ApplicationsState => ({
    items: [],
    total: 0,
    page: 1,
    pageSize: 20,
    filters: { status: null, search: '' },
    listStatus: 'idle',
    listError: null,

    current: null,
    currentStatus: 'idle',
    currentError: null,

    boardItems: [],
    boardTotal: 0,
    boardStatus: 'idle',
    boardError: null,

    mutationStatus: 'idle',
    mutationError: null,
  }),

  getters: {
    totalPages: (state): number => Math.max(1, Math.ceil(state.total / state.pageSize)),
    hasNextPage: (state): boolean => state.page * state.pageSize < state.total,
    hasPreviousPage: (state): boolean => state.page > 1,
    /** True if the board's single-page fetch didn't cover every application. */
    boardTruncated: (state): boolean => state.boardTotal > state.boardItems.length,
  },

  actions: {
    /**
     * Fetches a page of applications. Any param not passed falls back to
     * the current store state, so e.g. `fetchApplications({ page: 2 })`
     * keeps the active status/search filters. Pass `status: null` or
     * `search: ''` explicitly to clear a filter.
     */
    async fetchApplications(params: Partial<ApplicationListParams> = {}) {
      this.listStatus = 'loading'
      this.listError = null

      const status = params.status !== undefined ? params.status : this.filters.status
      const search = params.search !== undefined ? params.search : this.filters.search
      const page = params.page ?? this.page
      const pageSize = params.page_size ?? this.pageSize

      try {
        const { data } = await api.get<ApplicationListResponse>('/applications', {
          params: {
            status: status ?? undefined,
            search: search || undefined,
            page,
            page_size: pageSize,
          },
        })
        this.items = data.items
        this.total = data.total
        this.page = data.page
        this.pageSize = data.page_size
        this.filters = { status, search }
        this.listStatus = 'idle'
      } catch (err) {
        this.listStatus = 'error'
        this.listError = extractErrorMessage(err)
        throw err
      }
    },

    /** Convenience wrapper: apply new filters and jump back to page 1. */
    async setFilters(filters: Pick<ApplicationListParams, 'status' | 'search'>) {
      await this.fetchApplications({ ...filters, page: 1 })
    },

    /**
     * Fetches every application in one page for the Kanban board, grouped
     * client-side by status. `BOARD_PAGE_SIZE` is a pragmatic cap, not a
     * real solution for accounts with very large numbers of applications —
     * `boardTruncated` tells the view whether it under-fetched, so the UI
     * can say so rather than silently hiding applications. If this
     * regularly gets hit in practice, the real fix is a dedicated
     * non-paginated board endpoint or per-column pagination, not a bigger
     * hardcoded number here.
     */
    async fetchBoard() {
      this.boardStatus = 'loading'
      this.boardError = null
      try {
        const { data } = await api.get<ApplicationListResponse>('/applications', {
          params: { page: 1, page_size: BOARD_PAGE_SIZE },
        })
        this.boardItems = data.items
        this.boardTotal = data.total
        this.boardStatus = 'idle'
      } catch (err) {
        this.boardStatus = 'error'
        this.boardError = extractErrorMessage(err)
        throw err
      }
    },

    async fetchApplication(id: string) {
      this.currentStatus = 'loading'
      this.currentError = null
      try {
        const { data } = await api.get<Application>(`/applications/${id}`)
        this.current = data
        this.currentStatus = 'idle'
        return data
      } catch (err) {
        this.currentStatus = 'error'
        this.currentError = extractErrorMessage(err)
        throw err
      }
    },

    async createApplication(payload: ApplicationCreatePayload): Promise<Application> {
      this.mutationStatus = 'loading'
      this.mutationError = null
      try {
        const { data } = await api.post<Application>('/applications', payload)
        // Only splice into the current list if we're looking at the first
        // page with no filters that would exclude it — otherwise leave the
        // list alone and let the next fetchApplications() pick it up.
        if (this.page === 1 && !this.filters.status && !this.filters.search) {
          this.items = [data, ...this.items].slice(0, this.pageSize)
        }
        this.total += 1
        this.mutationStatus = 'idle'
        return data
      } catch (err) {
        this.mutationStatus = 'error'
        this.mutationError = extractErrorMessage(err)
        throw err
      }
    },

    async updateApplication(id: string, payload: ApplicationUpdatePayload): Promise<Application> {
      this.mutationStatus = 'loading'
      this.mutationError = null
      try {
        const { data } = await api.patch<Application>(`/applications/${id}`, payload)
        const index = this.items.findIndex((item) => item.id === id)
        if (index !== -1) this.items[index] = data
        if (this.current?.id === id) this.current = data
        const boardIndex = this.boardItems.findIndex((item) => item.id === id)
        if (boardIndex !== -1) this.boardItems[boardIndex] = data
        this.mutationStatus = 'idle'
        return data
      } catch (err) {
        this.mutationStatus = 'error'
        this.mutationError = extractErrorMessage(err)
        throw err
      }
    },

    async deleteApplication(id: string): Promise<void> {
      this.mutationStatus = 'loading'
      this.mutationError = null
      try {
        await api.delete(`/applications/${id}`)
        this.items = this.items.filter((item) => item.id !== id)
        this.boardItems = this.boardItems.filter((item) => item.id !== id)
        if (this.boardTotal > 0 && this.boardItems.length < this.boardTotal) {
          this.boardTotal -= 1
        }
        this.total = Math.max(0, this.total - 1)
        if (this.current?.id === id) this.current = null
        this.mutationStatus = 'idle'
      } catch (err) {
        this.mutationStatus = 'error'
        this.mutationError = extractErrorMessage(err)
        throw err
      }
    },
  },
})
