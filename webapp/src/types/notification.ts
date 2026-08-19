// Mirrors NotificationRead / NotificationListResponse / UnreadCountResponse
// (backend/app/schemas/notification.py). Only one producer exists today
// (app/tasks/reminders.py's send_due_reminders), so `type` only ever has
// one value in practice — but the union is written out to match
// NotificationType's shape rather than collapsing it to a bare `string`.
export type NotificationType = 'interview_reminder'

export interface Notification {
  id: string
  type: NotificationType
  title: string
  body: string
  application_id: string | null
  interview_id: string | null
  read_at: string | null
  created_at: string
}

export interface NotificationListResponse {
  items: Notification[]
  total: number
  page: number
  page_size: number
}

export interface UnreadCountResponse {
  unread_count: number
}

// Mirrors GET /notifications' `status` query param (backend/app/api/v1/
// endpoints/notifications.py). The backend also accepts "all", but the
// bell popover only ever shows two tabs — Unread and Read — so the
// frontend-facing type is narrower than the full backend contract.
export type NotificationStatusFilter = 'unread' | 'read'
