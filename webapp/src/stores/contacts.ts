import { defineStore } from 'pinia'
import { api, extractErrorMessage } from '@/lib/api'
import type {
  Contact,
  ContactCreatePayload,
  ContactListParams,
  ContactListResponse,
  ContactUpdatePayload,
} from '@/types/contact'

type RequestStatus = 'idle' | 'loading' | 'error'

// The top-level contact directory: every contact the user owns,
// independent of any application (GET/POST /contacts, GET/PATCH/DELETE
// /contacts/{id}) - a contact is no longer created in the context of one
// application, and can be attached to zero, one, or several (see
// stores/applicationContacts.ts for the attach/detach/list-attached side
// of that, used by ContactsPanel.vue).
interface ContactsState {
  items: Contact[]
  total: number
  page: number
  pageSize: number
  search: string
  listStatus: RequestStatus
  listError: string | null

  mutationStatus: RequestStatus
  mutationError: string | null
}

const DEFAULT_PAGE_SIZE = 20

export const useContactsStore = defineStore('contacts', {
  state: (): ContactsState => ({
    items: [],
    total: 0,
    page: 1,
    pageSize: DEFAULT_PAGE_SIZE,
    search: '',
    listStatus: 'idle',
    listError: null,

    mutationStatus: 'idle',
    mutationError: null,
  }),

  getters: {
    totalPages: (state): number => Math.max(1, Math.ceil(state.total / state.pageSize)),
  },

  actions: {
    /**
     * Fetches a page of the contact directory. Any param not passed falls
     * back to current store state (same convention as fetchDocuments() in
     * stores/documents.ts) - pass `search: null` explicitly to clear it.
     */
    async fetchContacts(params: ContactListParams = {}) {
      this.listStatus = 'loading'
      this.listError = null

      const search = params.search !== undefined ? (params.search ?? '') : this.search
      const page = params.page ?? this.page
      const pageSize = params.page_size ?? this.pageSize

      try {
        const { data } = await api.get<ContactListResponse>('/contacts', {
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

    /**
     * Isolated: returns matching contacts directly, without touching
     * `items`/`page`/`search`. Used by
     * components/contacts/ContactAttachDialog.vue for a live debounced
     * search (default pageSize=10 - autocomplete suggestions, not a real
     * listing). Reusing fetchContacts() would clobber whatever the actual
     * Contacts directory view has set, since both are reachable in the
     * same session without a full reload.
     */
    async searchContacts(query: string, pageSize = 10): Promise<Contact[]> {
      const { data } = await api.get<ContactListResponse>('/contacts', {
        params: {
          search: query || undefined,
          page: 1,
          page_size: pageSize,
        },
      })
      return data.items
    },

    async createContact(payload: ContactCreatePayload): Promise<Contact> {
      this.mutationStatus = 'loading'
      this.mutationError = null
      try {
        const { data } = await api.post<Contact>('/contacts', payload)
        this.items = [data, ...this.items]
        this.total += 1
        this.mutationStatus = 'idle'
        return data
      } catch (err) {
        this.mutationStatus = 'error'
        this.mutationError = extractErrorMessage(err)
        throw err
      }
    },

    async updateContact(contactId: string, payload: ContactUpdatePayload): Promise<Contact> {
      this.mutationStatus = 'loading'
      this.mutationError = null
      try {
        const { data } = await api.patch<Contact>(`/contacts/${contactId}`, payload)
        const index = this.items.findIndex((item) => item.id === contactId)
        if (index !== -1) this.items[index] = data
        this.mutationStatus = 'idle'
        return data
      } catch (err) {
        this.mutationStatus = 'error'
        this.mutationError = extractErrorMessage(err)
        throw err
      }
    },

    /** Permanently deletes the contact (and, server-side, every
     * application it was attached to loses that link - see
     * ApplicationContact's cascade). Not the same as detaching from one
     * application; see stores/applicationContacts.ts for that. */
    async deleteContact(contactId: string): Promise<void> {
      this.mutationStatus = 'loading'
      this.mutationError = null
      try {
        await api.delete(`/contacts/${contactId}`)
        this.items = this.items.filter((item) => item.id !== contactId)
        this.total = Math.max(0, this.total - 1)
        if (this.items.length === 0 && this.page > 1) {
          await this.fetchContacts({ page: this.page - 1 })
        }
        this.mutationStatus = 'idle'
      } catch (err) {
        this.mutationStatus = 'error'
        this.mutationError = extractErrorMessage(err)
        throw err
      }
    },
  },
})
