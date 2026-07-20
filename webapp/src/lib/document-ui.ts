import { DOCUMENT_TYPES, type DocumentType } from '@/types/document'

export const DOCUMENT_TYPE_LABELS: Record<DocumentType, string> = {
  resume: 'Resume',
  cover_letter: 'Cover Letter',
  other: 'Other',
}

// PrimeVue Tag `severity` values.
const TYPE_SEVERITIES: Record<DocumentType, string> = {
  resume: 'success',
  cover_letter: 'info',
  other: 'secondary',
}

export function documentTypeSeverity(type: DocumentType): string {
  return TYPE_SEVERITIES[type]
}

export function documentTypeOptions() {
  return DOCUMENT_TYPES.map((value) => ({ label: DOCUMENT_TYPE_LABELS[value], value }))
}
