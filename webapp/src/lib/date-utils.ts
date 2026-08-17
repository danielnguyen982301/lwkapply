import { DateTime } from 'luxon'

export function formatJSDate(date: Date, format: string): string {
  return DateTime.fromJSDate(date).toFormat(format)
}

// Shared Intl.DateTimeFormat instances - every list/picker view that
// shows a created_at/scheduled_at/etc timestamp was independently
// constructing its own `new Intl.DateTimeFormat(undefined, { dateStyle:
// 'medium' [, timeStyle: 'short'] })`, which is both repetitive and a
// (harmless but pointless) fresh Intl.DateTimeFormat allocation per
// component instance. One shared instance of each is fine to reuse
// across the whole app - Intl.DateTimeFormat is stateless once
// constructed, and `undefined` locale means "the user's own", so there's
// no per-call context that would ever need a fresh instance.
const dateFormatter = new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' })
const dateTimeFormatter = new Intl.DateTimeFormat(undefined, {
  dateStyle: 'medium',
  timeStyle: 'short',
})

/** Date only, e.g. "Aug 16, 2026" - for a backend `date` field (no time
 * component at all, like `applied_date`), or wherever only the day
 * matters. */
export function formatDate(value: string | Date): string {
  return dateFormatter.format(typeof value === 'string' ? new Date(value) : value)
}

/** Date + time, e.g. "Aug 16, 2026, 3:45 PM" - for a backend `datetime`
 * field where two rows can otherwise share the same date-only label
 * (e.g. a resume re-uploaded/re-analyzed same-day) and the time is what
 * actually tells them apart. */
export function formatDateTime(value: string | Date): string {
  return dateTimeFormatter.format(typeof value === 'string' ? new Date(value) : value)
}
