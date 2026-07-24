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

export interface DocumentTypeFilterOption {
  label: string
  value: DocumentType | null
}

// Used by DocumentDirectoryView.vue's file-type filter — mirrors
// interviewResultFilterOptions() in interview-ui.ts (an extra "All types"
// option representing "no filter", alongside every real value).
export function documentTypeFilterOptions(): DocumentTypeFilterOption[] {
  return [
    { label: 'All types', value: null },
    ...DOCUMENT_TYPES.map((value) => ({ label: DOCUMENT_TYPE_LABELS[value], value })),
  ]
}
