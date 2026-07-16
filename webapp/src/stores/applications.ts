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

  // --- create/update/delete state (shared by any form/action UI) ---
  mutationStatus: RequestStatus
  mutationError: string | null
}

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

    mutationStatus: 'idle',
    mutationError: null,
  }),

  getters: {
    totalPages: (state): number => Math.max(1, Math.ceil(state.total / state.pageSize)),
    hasNextPage: (state): boolean => state.page * state.pageSize < state.total,
    hasPreviousPage: (state): boolean => state.page > 1,
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
