import {
  APPLICATION_STATUSES,
  APPLICATION_STATUS_LABELS,
  type ApplicationStatus,
} from '@/types/application'

/** PrimeVue Tag severities for each application status. */
export function applicationStatusSeverity(
  status: ApplicationStatus,
): 'secondary' | 'info' | 'warn' | 'success' | 'danger' {
  switch (status) {
    case 'saved':
    case 'withdrawn':
      return 'secondary'
    case 'applied':
      return 'info'
    case 'phone_screen':
    case 'interviewing':
      return 'warn'
    case 'offer':
    case 'accepted':
      return 'success'
    case 'rejected':
      return 'danger'
  }
}

export interface StatusOption {
  label: string
  value: ApplicationStatus
}

export function applicationStatusOptions(): StatusOption[] {
  return APPLICATION_STATUSES.map((status) => ({
    label: APPLICATION_STATUS_LABELS[status],
    value: status,
  }))
}

export interface StatusFilterOption {
  label: string
  value: ApplicationStatus | null
}

export function applicationStatusFilterOptions(): StatusFilterOption[] {
  return [
    { label: 'All statuses', value: null },
    ...APPLICATION_STATUSES.map((status) => ({
      label: APPLICATION_STATUS_LABELS[status],
      value: status,
    })),
  ]
}
