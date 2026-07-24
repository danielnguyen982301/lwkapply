import {
  INTERVIEW_RESULTS,
  INTERVIEW_TYPES,
  type InterviewResult,
  type InterviewType,
} from '@/types/interview'

export const INTERVIEW_TYPE_LABELS: Record<InterviewType, string> = {
  phone_screen: 'Phone Screen',
  technical: 'Technical',
  behavioral: 'Behavioral',
  onsite: 'Onsite',
  final: 'Final',
  other: 'Other',
}

export const INTERVIEW_RESULT_LABELS: Record<InterviewResult, string> = {
  pending: 'Pending',
  passed: 'Passed',
  failed: 'Failed',
  cancelled: 'Cancelled',
}

// PrimeVue Tag `severity` values.
const RESULT_SEVERITIES: Record<InterviewResult, string> = {
  pending: 'info',
  passed: 'success',
  failed: 'danger',
  cancelled: 'secondary',
}

export function interviewResultSeverity(result: InterviewResult): string {
  return RESULT_SEVERITIES[result]
}

export function interviewTypeOptions() {
  return INTERVIEW_TYPES.map((value) => ({ label: INTERVIEW_TYPE_LABELS[value], value }))
}

export function interviewResultOptions() {
  return INTERVIEW_RESULTS.map((value) => ({ label: INTERVIEW_RESULT_LABELS[value], value }))
}

export interface InterviewResultFilterOption {
  label: string
  value: InterviewResult | null
}

// Used by InterviewDirectoryView.vue's result filter — mirrors
// applicationStatusFilterOptions() in application-ui.ts (an extra
// "All results" option representing "no filter", alongside every real
// value).
export function interviewResultFilterOptions(): InterviewResultFilterOption[] {
  return [
    { label: 'All results', value: null },
    ...INTERVIEW_RESULTS.map((value) => ({ label: INTERVIEW_RESULT_LABELS[value], value })),
  ]
}
