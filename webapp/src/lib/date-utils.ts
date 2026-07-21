import { DateTime } from 'luxon'

export function formatJSDate(date: Date, format: string): string {
  return DateTime.fromJSDate(date).toFormat(format)
}
