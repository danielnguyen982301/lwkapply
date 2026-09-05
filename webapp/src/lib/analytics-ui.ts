import { APPLICATION_STATUS_LABELS, type ApplicationStatus } from '@/types/application'

// Chart.js draws into a <canvas> 2D context, which can't resolve CSS
// custom properties the way DOM elements can - so these are literal hex
// values, not var(--color-teal) references. They're still derived
// directly from tailwind.config.js's palette (teal #2A9D8F / teal.dark
// #1F7A6F / coral #E15554 / slate.light #8D96A8), not invented for this
// file. If that palette ever changes, this needs a matching update -
// there's no automatic way to keep them in sync short of a build step
// this project doesn't otherwise need.
//
// The funnel stages read top-to-bottom as one continuous gradient of
// teal intensity - saved is the lightest tint, accepted is the darkest.
// The color itself encodes "how far along the pipeline", which is real
// structure, not decoration: a glance at hue alone tells you roughly
// where an application sits, before reading a single label.
const FUNNEL_STAGE_COLORS: Record<ApplicationStatus, string> = {
  saved: '#C9E7E2',
  applied: '#9FD3C9',
  phone_screen: '#6FBFAF',
  interviewing: '#2A9D8F', // teal (tailwind.config.js)
  offer: '#238A7D',
  accepted: '#1F7A6F', // teal.dark (tailwind.config.js)
  rejected: '#E15554', // coral (tailwind.config.js)
  withdrawn: '#8D96A8', // slate.light (tailwind.config.js)
}

// Dark-mode counterpart - not the same values, a compressed-and-brightened
// version of the same gradient. The light palette's darkest stops
// (accepted #1F7A6F, close in luminance to a near-black canvas) would
// nearly disappear against style.css's `.app-dark` background
// (--color-paper: #0F131B), so every stop here stays well above that
// floor - same relative ordering (saved lightest -> accepted most
// saturated), just re-anchored to stay visible on a dark canvas.
const FUNNEL_STAGE_COLORS_DARK: Record<ApplicationStatus, string> = {
  saved: '#7FC9BE',
  applied: '#63BBAE',
  phone_screen: '#4FADA0',
  interviewing: '#35B0A2', // dark-mode teal (style.css .app-dark --color-teal)
  offer: '#2F9C90',
  accepted: '#2A8F83', // dark-mode teal.dark (style.css .app-dark --color-teal-dark)
  rejected: '#EB6E6C', // dark-mode coral (style.css .app-dark --color-coral)
  withdrawn: '#97A1B5', // dark-mode slate (style.css .app-dark --color-slate)
}

export function funnelStageColor(status: ApplicationStatus, isDark = false): string {
  return (isDark ? FUNNEL_STAGE_COLORS_DARK : FUNNEL_STAGE_COLORS)[status]
}

export function funnelStageLabel(status: ApplicationStatus): string {
  return APPLICATION_STATUS_LABELS[status]
}

export const INTERVIEW_RESULT_LABELS = {
  pending: 'Pending',
  passed: 'Passed',
  failed: 'Failed',
  cancelled: 'Cancelled',
} as const

export const INTERVIEW_RESULT_ORDER = ['pending', 'passed', 'failed', 'cancelled'] as const

const INTERVIEW_RESULT_COLORS: Record<(typeof INTERVIEW_RESULT_ORDER)[number], string> = {
  pending: '#8D96A8', // slate.light
  passed: '#2A9D8F', // teal
  failed: '#E15554', // coral
  cancelled: '#5C677D', // slate
}

// Dark-mode counterpart, same reasoning as FUNNEL_STAGE_COLORS_DARK above -
// reuses style.css's `.app-dark` values for the same tokens.
const INTERVIEW_RESULT_COLORS_DARK: Record<(typeof INTERVIEW_RESULT_ORDER)[number], string> = {
  pending: '#B7BECD', // dark-mode slate.light
  passed: '#35B0A2', // dark-mode teal
  failed: '#EB6E6C', // dark-mode coral
  cancelled: '#97A1B5', // dark-mode slate
}

export function interviewResultColor(
  key: (typeof INTERVIEW_RESULT_ORDER)[number],
  isDark = false,
): string {
  return (isDark ? INTERVIEW_RESULT_COLORS_DARK : INTERVIEW_RESULT_COLORS)[key]
}

// Chart chrome (gridlines, axis ticks, legend labels) - chart.js defaults
// these to a color tuned for a light canvas only, and won't pick up a dark
// background on its own. `paper`/`slate`'s dark-mode values (style.css
// .app-dark) don't work directly here (a gridline needs to sit *between*
// the two, not equal either), so these are their own explicit pair.
export function chartGridColor(isDark = false): string {
  return isDark ? '#242B38' : '#EEF0F3'
}

export function chartTextColor(isDark = false): string {
  return isDark ? '#97A1B5' : '#5C677D' // slate / dark-mode slate
}

/** `0.734` -> `"73%"`; null (no data yet) -> `"—"`. Shared by every
 * percentage-shaped metric on the dashboard (response_rate, pass_rate)
 * so rounding/formatting can't drift between them. */
export function formatPercent(value: number | null): string {
  if (value === null) return '—'
  return `${Math.round(value * 100)}%`
}
