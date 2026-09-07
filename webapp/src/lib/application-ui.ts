import {
  APPLICATION_STATUSES,
  APPLICATION_STATUS_LABELS,
  SALARY_CURRENCIES,
  SALARY_CURRENCY_LABELS,
  type ApplicationStatus,
  type SalaryCurrency,
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

export interface CurrencyOption {
  label: string
  value: SalaryCurrency
}

export function salaryCurrencyOptions(): CurrencyOption[] {
  return SALARY_CURRENCIES.map((currency) => ({
    label: `${currency} — ${SALARY_CURRENCY_LABELS[currency]}`,
    value: currency,
  }))
}

// Application.source is deliberately a free-form string (see its
// docstring in types/application.ts) so a new site never needs a
// migration - this only supplies a nicer display name for the ones
// we know about, falling back to a simple capitalization for anything
// else rather than requiring every new source to be added here too.
const APPLICATION_SOURCE_LABELS: Record<string, string> = {
  vietnamworks: 'VietnamWorks',
}

export function applicationSourceLabel(source: string): string {
  return APPLICATION_SOURCE_LABELS[source] ?? source.charAt(0).toUpperCase() + source.slice(1)
}
