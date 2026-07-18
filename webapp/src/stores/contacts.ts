import { defineStore } from 'pinia'
import { api, extractErrorMessage } from '@/lib/api'
import type {
  Contact,
  ContactCreatePayload,
  ContactListResponse,
  ContactUpdatePayload,
} from '@/types/contact'

type RequestStatus = 'idle' | 'loading' | 'error'

interface ContactsState {
  // Contacts are always viewed in the context of a single application (the
  // Contacts panel on the Application detail page), so — unlike the
  // Applications store — there's just one list, not list/board/current
  // variants. `applicationId` records which application `items` belongs
  // to, so a stale response from a fetch for a previous application can't
  // clobber the panel after the user has already navigated to a new one.
  applicationId: string | null
  items: Contact[]
  total: number
  listStatus: RequestStatus
  listError: string | null

  mutationStatus: RequestStatus
  mutationError: string | null
}

export const useContactsStore = defineStore('contacts', {
  state: (): ContactsState => ({
    applicationId: null,
    items: [],
    total: 0,
    listStatus: 'idle',
    listError: null,

    mutationStatus: 'idle',
    mutationError: null,
  }),

  actions: {
    async fetchContacts(applicationId: string) {
      this.listStatus = 'loading'
      this.listError = null
      try {
        const { data } = await api.get<ContactListResponse>(
          `/applications/${applicationId}/contacts`,
        )
        this.applicationId = applicationId
        this.items = data.items
        this.total = data.total
        this.listStatus = 'idle'
      } catch (err) {
        this.listStatus = 'error'
        this.listError = extractErrorMessage(err)
        throw err
      }
    },

    async createContact(applicationId: string, payload: ContactCreatePayload): Promise<Contact> {
      this.mutationStatus = 'loading'
      this.mutationError = null
      try {
        const { data } = await api.post<Contact>(`/applications/${applicationId}/contacts`, payload)
        if (this.applicationId === applicationId) {
          this.items = [data, ...this.items]
          this.total += 1
        }
        this.mutationStatus = 'idle'
        return data
      } catch (err) {
        this.mutationStatus = 'error'
        this.mutationError = extractErrorMessage(err)
        throw err
      }
    },

    async updateContact(
      applicationId: string,
      contactId: string,
      payload: ContactUpdatePayload,
    ): Promise<Contact> {
      this.mutationStatus = 'loading'
      this.mutationError = null
      try {
        const { data } = await api.patch<Contact>(
          `/applications/${applicationId}/contacts/${contactId}`,
          payload,
        )
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

    async deleteContact(applicationId: string, contactId: string): Promise<void> {
      this.mutationStatus = 'loading'
      this.mutationError = null
      try {
        await api.delete(`/applications/${applicationId}/contacts/${contactId}`)
        this.items = this.items.filter((item) => item.id !== contactId)
        this.total = Math.max(0, this.total - 1)
        this.mutationStatus = 'idle'
      } catch (err) {
        this.mutationStatus = 'error'
        this.mutationError = extractErrorMessage(err)
        throw err
      }
    },

    /** Called on unmount of the Contacts panel so switching applications never briefly shows stale contacts. */
    reset() {
      this.applicationId = null
      this.items = []
      this.total = 0
      this.listStatus = 'idle'
      this.listError = null
      this.mutationStatus = 'idle'
      this.mutationError = null
    },
  },
})
