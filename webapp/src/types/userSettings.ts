// Mirrors UserSettingsRead / UserSettingsUpdate (backend/app/schemas/user_settings.py).
// Delivery *preferences* — distinct from the Notification feed itself (see
// types/notification.ts).
export interface UserSettings {
  // null = "use the global settings.REMINDER_LEAD_HOURS default".
  reminder_lead_hours: number | null
  notifications_enabled: boolean
  email_notifications_enabled: boolean
  push_notifications_enabled: boolean
}

// The backend applies this via exclude_unset, so an omitted key is left
// untouched — same convention as ContactUpdatePayload/DocumentUpdatePayload.
// An explicit `reminder_lead_hours: null` resets it to the global default.
export type UserSettingsUpdatePayload = Partial<UserSettings>
