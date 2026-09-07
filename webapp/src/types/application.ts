// Mirrors backend/app/models/application.py::ApplicationStatus.
// Kept as a plain string-literal union (not a TS enum) so it serializes
// identically to the JSON the API sends/expects — no extra mapping layer.
export type ApplicationStatus =
  | 'saved'
  | 'applied'
  | 'phone_screen'
  | 'interviewing'
  | 'offer'
  | 'rejected'
  | 'withdrawn'
  | 'accepted'

// Order matters here: this is the left-to-right column order the Kanban
// board (Phase 2, later step) will use, and a sensible top-to-bottom order
// for a <select> filter too.
export const APPLICATION_STATUSES: readonly ApplicationStatus[] = [
  'saved',
  'applied',
  'phone_screen',
  'interviewing',
  'offer',
  'accepted',
  'rejected',
  'withdrawn',
]

export const APPLICATION_STATUS_LABELS: Record<ApplicationStatus, string> = {
  saved: 'Saved',
  applied: 'Applied',
  phone_screen: 'Phone Screen',
  interviewing: 'Interviewing',
  offer: 'Offer',
  accepted: 'Accepted',
  rejected: 'Rejected',
  withdrawn: 'Withdrawn',
}

// Mirrors backend/app/models/application.py::SalaryCurrency. A curated set
// of major job-market currencies, not the full ISO 4217 list — extend here
// (and in the backend enum + migration) if a currency outside this set
// shows up on a job.
export type SalaryCurrency =
  | 'USD'
  | 'EUR'
  | 'GBP'
  | 'CAD'
  | 'AUD'
  | 'NZD'
  | 'CHF'
  | 'SEK'
  | 'NOK'
  | 'DKK'
  | 'ISK'
  | 'PLN'
  | 'CZK'
  | 'HUF'
  | 'RON'
  | 'UAH'
  | 'RUB'
  | 'TRY'
  | 'ILS'
  | 'AED'
  | 'SAR'
  | 'EGP'
  | 'NGN'
  | 'KES'
  | 'ZAR'
  | 'INR'
  | 'PKR'
  | 'BDT'
  | 'CNY'
  | 'JPY'
  | 'KRW'
  | 'TWD'
  | 'HKD'
  | 'SGD'
  | 'MYR'
  | 'THB'
  | 'VND'
  | 'IDR'
  | 'PHP'
  | 'BRL'
  | 'MXN'
  | 'ARS'
  | 'CLP'
  | 'COP'

export const SALARY_CURRENCIES: readonly SalaryCurrency[] = [
  'USD',
  'EUR',
  'GBP',
  'CAD',
  'AUD',
  'NZD',
  'CHF',
  'SEK',
  'NOK',
  'DKK',
  'ISK',
  'PLN',
  'CZK',
  'HUF',
  'RON',
  'UAH',
  'RUB',
  'TRY',
  'ILS',
  'AED',
  'SAR',
  'EGP',
  'NGN',
  'KES',
  'ZAR',
  'INR',
  'PKR',
  'BDT',
  'CNY',
  'JPY',
  'KRW',
  'TWD',
  'HKD',
  'SGD',
  'MYR',
  'THB',
  'VND',
  'IDR',
  'PHP',
  'BRL',
  'MXN',
  'ARS',
  'CLP',
  'COP',
]

export const SALARY_CURRENCY_LABELS: Record<SalaryCurrency, string> = {
  USD: 'US Dollar',
  EUR: 'Euro',
  GBP: 'British Pound',
  CAD: 'Canadian Dollar',
  AUD: 'Australian Dollar',
  NZD: 'New Zealand Dollar',
  CHF: 'Swiss Franc',
  SEK: 'Swedish Krona',
  NOK: 'Norwegian Krone',
  DKK: 'Danish Krone',
  ISK: 'Icelandic Krona',
  PLN: 'Polish Zloty',
  CZK: 'Czech Koruna',
  HUF: 'Hungarian Forint',
  RON: 'Romanian Leu',
  UAH: 'Ukrainian Hryvnia',
  RUB: 'Russian Ruble',
  TRY: 'Turkish Lira',
  ILS: 'Israeli Shekel',
  AED: 'UAE Dirham',
  SAR: 'Saudi Riyal',
  EGP: 'Egyptian Pound',
  NGN: 'Nigerian Naira',
  KES: 'Kenyan Shilling',
  ZAR: 'South African Rand',
  INR: 'Indian Rupee',
  PKR: 'Pakistani Rupee',
  BDT: 'Bangladeshi Taka',
  CNY: 'Chinese Yuan',
  JPY: 'Japanese Yen',
  KRW: 'South Korean Won',
  TWD: 'Taiwan Dollar',
  HKD: 'Hong Kong Dollar',
  SGD: 'Singapore Dollar',
  MYR: 'Malaysian Ringgit',
  THB: 'Thai Baht',
  VND: 'Vietnamese Dong',
  IDR: 'Indonesian Rupiah',
  PHP: 'Philippine Peso',
  BRL: 'Brazilian Real',
  MXN: 'Mexican Peso',
  ARS: 'Argentine Peso',
  CLP: 'Chilean Peso',
  COP: 'Colombian Peso',
}

// Symbol shown alongside salary_min/salary_max in the application form —
// not necessarily the symbol used in-country, but the one job seekers
// scanning a salary figure will recognize fastest.
export const SALARY_CURRENCY_SYMBOLS: Record<SalaryCurrency, string> = {
  USD: '$',
  EUR: '€',
  GBP: '£',
  CAD: 'C$',
  AUD: 'A$',
  NZD: 'NZ$',
  CHF: 'CHF',
  SEK: 'kr',
  NOK: 'kr',
  DKK: 'kr',
  ISK: 'kr',
  PLN: 'zł',
  CZK: 'Kč',
  HUF: 'Ft',
  RON: 'lei',
  UAH: '₴',
  RUB: '₽',
  TRY: '₺',
  ILS: '₪',
  AED: 'AED',
  SAR: 'SAR',
  EGP: 'E£',
  NGN: '₦',
  KES: 'KSh',
  ZAR: 'R',
  INR: '₹',
  PKR: '₨',
  BDT: '৳',
  CNY: 'CN¥',
  JPY: '¥',
  KRW: '₩',
  TWD: 'NT$',
  HKD: 'HK$',
  SGD: 'S$',
  MYR: 'RM',
  THB: '฿',
  VND: '₫',
  IDR: 'Rp',
  PHP: '₱',
  BRL: 'R$',
  MXN: 'MX$',
  ARS: 'AR$',
  CLP: 'CL$',
  COP: 'CO$',
}

// Mirrors ApplicationRead (backend/app/schemas/application.py).
export interface Application {
  id: string
  user_id: string
  company: string
  position: string
  /** Optional user-chosen label to tell apart applications to the same
   * company/position (a re-apply, two postings with the same title). */
  application_name: string | null
  location: string | null
  status: ApplicationStatus
  salary_min: number | null
  salary_max: number | null
  salary_currency: SalaryCurrency
  /** ISO date string, e.g. "2026-07-16" (backend `date`, not `datetime`). */
  applied_date: string | null
  job_url: string | null
  notes: string | null
  created_at: string
  updated_at: string
}

// Mirrors ApplicationListResponse.
export interface ApplicationListResponse {
  items: Application[]
  total: number
  page: number
  page_size: number
}

// Query params accepted by GET /applications (backend uses `status` as the
// query alias, `status_filter` is just the Python-side param name).
//
// `status` is `ApplicationStatus | null | undefined`, not just optional:
// - `undefined` (key omitted) => "don't change this filter"
// - `null`                    => "explicitly clear this filter"
// This distinction matters for partial updates like `fetchApplications({ page: 2 })`,
// which should keep whatever status filter is already active rather than
// wiping it.
export interface ApplicationListParams {
  status?: ApplicationStatus | null
  search?: string
  page?: number
  page_size?: number
}

// Mirrors ApplicationCreate, which is just ApplicationBase — every field
// the backend accepts on create. `status` is optional since the backend
// defaults it to `saved`.
export interface ApplicationCreatePayload {
  company: string
  position: string
  application_name?: string | null
  location?: string | null
  status?: ApplicationStatus
  salary_min?: number | null
  salary_max?: number | null
  salary_currency?: SalaryCurrency
  applied_date?: string | null
  job_url?: string | null
  notes?: string | null
}

// Mirrors ApplicationUpdate: identical fields, all optional. The backend
// uses `exclude_unset=True`, so only keys actually present in the request
// body are touched — omit a field here rather than sending `undefined`/
// `null` for "don't change this".
export type ApplicationUpdatePayload = Partial<ApplicationCreatePayload>
