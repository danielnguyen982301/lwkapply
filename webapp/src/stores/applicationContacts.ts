import { defineStore } from 'pinia'
import { api, extractErrorMessage } from '@/lib/api'
import type { Contact, ContactListResponse } from '@/types/contact'

type RequestStatus = 'idle' | 'loading' | 'error'

// Application <-> Contact attachment (many-to-many —
// app/models/application_contact.py): GET/POST/DELETE
// /applications/{application_id}/contacts. Deliberately a separate store
// from stores/contacts.ts: this one is scoped to one application's
// *attached* contacts (used by ContactsPanel.vue), the other is the
// user's whole contact directory (used by ContactDirectoryView.vue and
// ContactAttachDialog.vue's search). Attaching/detaching here never
// creates or deletes the underlying contact - see stores/contacts.ts for
// that.
interface ApplicationContactsState {
  applicationId: string | null
  items: Contact[]
  total: number
  page: number
  pageSize: number
  listStatus: RequestStatus
  listError: string | null

  attachStatus: RequestStatus
  attachError: string | null

  detachingId: string | null
  detachError: string | null
}

const DEFAULT_PAGE_SIZE = 20

export const useApplicationContactsStore = defineStore('applicationContacts', {
  state: (): ApplicationContactsState => ({
    applicationId: null,
    items: [],
    total: 0,
    page: 1,
    pageSize: DEFAULT_PAGE_SIZE,
    listStatus: 'idle',
    listError: null,

    attachStatus: 'idle',
    attachError: null,

    detachingId: null,
    detachError: null,
  }),

  getters: {
    totalPages: (state): number => Math.max(1, Math.ceil(state.total / state.pageSize)),
  },

  actions: {
    async fetchAttached(applicationId: string, params: { page?: number } = {}) {
      this.listStatus = 'loading'
      this.listError = null
      const page = params.page ?? (this.applicationId === applicationId ? this.page : 1)
      try {
        const { data } = await api.get<ContactListResponse>(
          `/applications/${applicationId}/contacts`,
          { params: { page, page_size: this.pageSize } },
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

    async attach(applicationId: string, contactId: string): Promise<Contact> {
      this.attachStatus = 'loading'
      this.attachError = null
      try {
        const { data } = await api.post<Contact>(`/applications/${applicationId}/contacts`, {
          contact_id: contactId,
        })
        if (this.applicationId === applicationId) {
          this.items = [data, ...this.items]
          this.total += 1
        }
        this.attachStatus = 'idle'
        return data
      } catch (err) {
        this.attachStatus = 'error'
        this.attachError = extractErrorMessage(err)
        throw err
      }
    },

    /** Removes the link only - the contact itself, and any other
     * application it's attached to, is untouched. */
    async detach(applicationId: string, contactId: string): Promise<void> {
      this.detachingId = contactId
      this.detachError = null
      try {
        await api.delete(`/applications/${applicationId}/contacts/${contactId}`)
        this.items = this.items.filter((item) => item.id !== contactId)
        this.total = Math.max(0, this.total - 1)
        if (this.items.length === 0 && this.page > 1) {
          await this.fetchAttached(applicationId, { page: this.page - 1 })
        }
      } catch (err) {
        this.detachError = extractErrorMessage(err)
        throw err
      } finally {
        this.detachingId = null
      }
    },

    /** Called on unmount of the Contacts panel so switching applications never briefly shows stale contacts. */
    reset() {
      this.applicationId = null
      this.items = []
      this.total = 0
      this.page = 1
      this.pageSize = DEFAULT_PAGE_SIZE
      this.listStatus = 'idle'
      this.listError = null
      this.attachStatus = 'idle'
      this.attachError = null
      this.detachingId = null
      this.detachError = null
    },
  },
})
