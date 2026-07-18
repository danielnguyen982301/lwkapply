import { defineStore } from 'pinia'
import { api, extractErrorMessage } from '@/lib/api'
import type {
  ContactDirectoryParams,
  ContactWithApplication,
  ContactWithApplicationListResponse,
} from '@/types/contact'

type RequestStatus = 'idle' | 'loading' | 'error'

// Deliberately a separate store from stores/contacts.ts, not an extension
// of it: that store is scoped to one application's contacts (used by
// ContactsPanel.vue, has create/update/delete) while this one is a
// read-only, paginated, cross-application listing (used by the "Contacts"
// nav item) — different shape, different endpoint, different lifecycle.
interface ContactDirectoryState {
  items: ContactWithApplication[]
  total: number
  page: number
  pageSize: number
  search: string
  listStatus: RequestStatus
  listError: string | null
}

export const useContactDirectoryStore = defineStore('contactDirectory', {
  state: (): ContactDirectoryState => ({
    items: [],
    total: 0,
    page: 1,
    pageSize: 20,
    search: '',
    listStatus: 'idle',
    listError: null,
  }),

  getters: {
    totalPages: (state): number => Math.max(1, Math.ceil(state.total / state.pageSize)),
  },

  actions: {
    /**
     * Fetches a page of the contact directory. Any param not passed falls
     * back to current store state (same convention as
     * fetchApplications() in stores/applications.ts) — pass `search: ''`
     * explicitly to clear the search.
     */
    async fetchContacts(params: Partial<ContactDirectoryParams> = {}) {
      this.listStatus = 'loading'
      this.listError = null

      const search = params.search !== undefined ? params.search : this.search
      const page = params.page ?? this.page
      const pageSize = params.page_size ?? this.pageSize

      try {
        const { data } = await api.get<ContactWithApplicationListResponse>('/contacts', {
          params: {
            search: search || undefined,
            page,
            page_size: pageSize,
          },
        })
        this.items = data.items
        this.total = data.total
        this.page = data.page
        this.pageSize = data.page_size
        this.search = search
        this.listStatus = 'idle'
      } catch (err) {
        this.listStatus = 'error'
        this.listError = extractErrorMessage(err)
        throw err
      }
    },

    /** Convenience wrapper: apply a new search term and jump back to page 1. */
    async setSearch(search: string) {
      await this.fetchContacts({ search, page: 1 })
    },
  },
})
