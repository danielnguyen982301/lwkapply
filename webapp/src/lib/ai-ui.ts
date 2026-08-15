import { type AIJobStatus } from '@/types/ai'

export const AI_JOB_STATUS_LABELS: Record<AIJobStatus, string> = {
  pending: 'Pending',
  processing: 'Processing',
  completed: 'Completed',
  failed: 'Failed',
}

// PrimeVue Tag `severity` values.
const STATUS_SEVERITIES: Record<AIJobStatus, string> = {
  pending: 'info',
  processing: 'info',
  completed: 'success',
  failed: 'danger',
}

export function aiJobStatusSeverity(status: AIJobStatus): string {
  return STATUS_SEVERITIES[status]
}

/** True for the two states a detail dialog should still be polling in. */
export function isAiJobInFlight(status: AIJobStatus): boolean {
  return status === 'pending' || status === 'processing'
}

/** Rough score-band coloring for AtsScoreDisplay.vue's score badge -
 * deliberately not the same STATUS_SEVERITIES mapping above (this is
 * about score quality, not job status). */
export function atsScoreSeverity(score: number): string {
  if (score >= 75) return 'success'
  if (score >= 50) return 'warn'
  return 'danger'
}
