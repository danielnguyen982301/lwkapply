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

export function funnelStageColor(status: ApplicationStatus): string {
  return FUNNEL_STAGE_COLORS[status]
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

export const INTERVIEW_RESULT_COLORS: Record<(typeof INTERVIEW_RESULT_ORDER)[number], string> = {
  pending: '#8D96A8', // slate.light
  passed: '#2A9D8F', // teal
  failed: '#E15554', // coral
  cancelled: '#5C677D', // slate
}

/** `0.734` -> `"73%"`; null (no data yet) -> `"—"`. Shared by every
 * percentage-shaped metric on the dashboard (response_rate, pass_rate)
 * so rounding/formatting can't drift between them. */
export function formatPercent(value: number | null): string {
  if (value === null) return '—'
  return `${Math.round(value * 100)}%`
}
