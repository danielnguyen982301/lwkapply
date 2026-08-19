import { defineStore } from 'pinia'
import { api, extractErrorMessage } from '@/lib/api'
import type {
  Notification,
  NotificationListResponse,
  UnreadCountResponse,
} from '@/types/notification'

type RequestStatus = 'idle' | 'loading' | 'error'

// Delivery is polling, not real-time push (see
// backend/app/api/v1/endpoints/notifications.py's module docstring) — the
// bell badge just re-checks the unread count on this interval rather than
// holding a socket open.
const POLL_INTERVAL_MS = 30_000
const BELL_PAGE_SIZE = 10

interface NotificationsState {
  // The bell dropdown's own short list — not a full paginated "all
  // notifications" view (nothing in the plan calls for one yet), so this
  // only ever holds the single most-recent page.
  items: Notification[]
  total: number
  listStatus: RequestStatus
  listError: string | null

  unreadCount: number
  pollHandle: ReturnType<typeof setInterval> | null

  mutationStatus: RequestStatus
  mutationError: string | null
}

export const useNotificationsStore = defineStore('notifications', {
  state: (): NotificationsState => ({
    items: [],
    total: 0,
    listStatus: 'idle',
    listError: null,

    unreadCount: 0,
    pollHandle: null,

    mutationStatus: 'idle',
    mutationError: null,
  }),

  actions: {
    async fetchNotifications() {
      this.listStatus = 'loading'
      this.listError = null
      try {
        const { data } = await api.get<NotificationListResponse>('/notifications', {
          params: { page: 1, page_size: BELL_PAGE_SIZE },
        })
        this.items = data.items
        this.total = data.total
        this.listStatus = 'idle'
      } catch (err) {
        this.listStatus = 'error'
        this.listError = extractErrorMessage(err)
        throw err
      }
    },

    async fetchUnreadCount() {
      try {
        const { data } = await api.get<UnreadCountResponse>('/notifications/unread-count')
        this.unreadCount = data.unread_count
      } catch {
        // Silent — the badge just doesn't update this tick; the next poll retries.
      }
    },

    async markRead(notificationId: string) {
      try {
        const { data } = await api.post<Notification>(`/notifications/${notificationId}/read`)
        const index = this.items.findIndex((item) => item.id === notificationId)
        const wasUnread = index !== -1 && this.items[index].read_at === null
        if (index !== -1) this.items[index] = data
        if (wasUnread) this.unreadCount = Math.max(0, this.unreadCount - 1)
      } catch (err) {
        this.mutationError = extractErrorMessage(err)
        throw err
      }
    },

    async markAllRead() {
      this.mutationStatus = 'loading'
      this.mutationError = null
      try {
        await api.post('/notifications/read-all')
        const now = new Date().toISOString()
        this.items = this.items.map((item) => (item.read_at ? item : { ...item, read_at: now }))
        this.unreadCount = 0
        this.mutationStatus = 'idle'
      } catch (err) {
        this.mutationStatus = 'error'
        this.mutationError = extractErrorMessage(err)
        throw err
      }
    },

    /** Called once from AppLayout.vue's onMounted — it stays mounted for
     * the whole authenticated session, so one poll loop here covers every
     * page, not just a settings/notifications screen. */
    startPolling() {
      if (this.pollHandle) return
      this.fetchUnreadCount()
      this.pollHandle = setInterval(() => this.fetchUnreadCount(), POLL_INTERVAL_MS)
    },

    stopPolling() {
      if (this.pollHandle) {
        clearInterval(this.pollHandle)
        this.pollHandle = null
      }
    },
  },
})
