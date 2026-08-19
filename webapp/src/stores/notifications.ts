import { defineStore } from 'pinia'
import { api, extractErrorMessage } from '@/lib/api'
import type {
  Notification,
  NotificationListResponse,
  NotificationStatusFilter,
  UnreadCountResponse,
} from '@/types/notification'

type RequestStatus = 'idle' | 'loading' | 'error'

// Delivery is polling, not real-time push (see
// backend/app/api/v1/endpoints/notifications.py's module docstring) — the
// bell badge just re-checks the unread count on this interval rather than
// holding a socket open.
const POLL_INTERVAL_MS = 30_000
const PAGE_SIZE = 15

interface NotificationsState {
  // The bell popover's two tabs (GET /notifications?status=unread|read) —
  // no "all" tab, so there's exactly one items/page/total set at a time,
  // reset on every tab switch rather than keeping both lists warm.
  activeStatus: NotificationStatusFilter
  items: Notification[]
  page: number
  total: number
  listStatus: RequestStatus
  listError: string | null

  // Separate from listStatus so infinite-scroll's "fetch the next page"
  // doesn't fight with a tab switch's "replace everything" for the same
  // loading flag.
  loadMoreStatus: RequestStatus
  loadMoreError: string | null

  unreadCount: number
  pollHandle: ReturnType<typeof setInterval> | null

  mutationStatus: RequestStatus
  mutationError: string | null
}

export const useNotificationsStore = defineStore('notifications', {
  state: (): NotificationsState => ({
    activeStatus: 'unread',
    items: [],
    page: 1,
    total: 0,
    listStatus: 'idle',
    listError: null,

    loadMoreStatus: 'idle',
    loadMoreError: null,

    unreadCount: 0,
    pollHandle: null,

    mutationStatus: 'idle',
    mutationError: null,
  }),

  getters: {
    hasMore: (state) => state.items.length < state.total,
  },

  actions: {
    /** Replaces `items` with page 1 of the given (or current) status —
     * used both for the initial popover-open fetch and for switching
     * tabs. */
    async fetchNotifications(status?: NotificationStatusFilter) {
      this.activeStatus = status ?? this.activeStatus
      this.listStatus = 'loading'
      this.listError = null
      try {
        const { data } = await api.get<NotificationListResponse>('/notifications', {
          params: { status: this.activeStatus, page: 1, page_size: PAGE_SIZE },
        })
        this.items = data.items
        this.total = data.total
        this.page = data.page
        this.listStatus = 'idle'
      } catch (err) {
        this.listStatus = 'error'
        this.listError = extractErrorMessage(err)
        throw err
      }
    },

    /** Infinite scroll: appends the next page for the current tab. */
    async loadMore() {
      if (this.loadMoreStatus === 'loading' || !this.hasMore) return
      this.loadMoreStatus = 'loading'
      this.loadMoreError = null
      try {
        const nextPage = this.page + 1
        const { data } = await api.get<NotificationListResponse>('/notifications', {
          params: { status: this.activeStatus, page: nextPage, page_size: PAGE_SIZE },
        })
        this.items = [...this.items, ...data.items]
        this.total = data.total
        this.page = data.page
        this.loadMoreStatus = 'idle'
      } catch (err) {
        this.loadMoreStatus = 'error'
        this.loadMoreError = extractErrorMessage(err)
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
        if (index !== -1) {
          if (this.activeStatus === 'unread') {
            // No longer belongs in this tab's filter — drop it rather than
            // patch it in place. (Offset pagination against a list that's
            // shrinking underneath it can in rare cases skip/repeat an item
            // on the next loadMore() — an acceptable tradeoff for a small
            // "recent notifications" popover, not worth a cursor-based
            // rewrite of the list endpoint for.)
            this.items.splice(index, 1)
            this.total = Math.max(0, this.total - 1)
          } else {
            this.items[index] = data
          }
        }
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
        this.unreadCount = 0
        if (this.activeStatus === 'unread') {
          this.items = []
          this.total = 0
        }
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
