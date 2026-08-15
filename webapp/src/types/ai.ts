// Mirrors backend/app/models/resume_analysis.py::AIJobStatus - shared by
// both ResumeAnalysis and AtsScore (see backend/app/models/ats_score.py's
// module docstring for why the two reuse one Postgres enum).
export type AIJobStatus = 'pending' | 'processing' | 'completed' | 'failed'

export const AI_JOB_STATUSES: readonly AIJobStatus[] = [
  'pending',
  'processing',
  'completed',
  'failed',
]

// --- Gemini structured-output shapes ---------------------------------------
// Mirrors backend/app/schemas/ai.py's ParsedResume/WorkExperienceItem/
// EducationItem/AtsScoreResult exactly (down to field presence - every
// field there is required, even where nullable, per that file's own
// docstring on Gemini's response_schema constraints; doesn't matter here
// since the frontend only ever reads these, never sends them).

export interface WorkExperienceItem {
  company: string
  title: string
  start_date: string | null
  end_date: string | null
  description: string | null
}

export interface EducationItem {
  institution: string
  degree: string | null
  field_of_study: string | null
  graduation_date: string | null
}

export interface ParsedResume {
  full_name: string | null
  email: string | null
  phone: string | null
  summary: string | null
  skills: string[]
  work_experience: WorkExperienceItem[]
  education: EducationItem[]
  total_years_experience: number | null
}

export interface AtsScoreResult {
  score: number
  summary: string
  matched_keywords: string[]
  missing_keywords: string[]
  suggestions: string[]
}

// --- Resume analyses ---------------------------------------------------------

export interface ResumeAnalysisCreatePayload {
  document_id: string
}

// Mirrors ResumeAnalysisRead. `parsed_data` is typed as ParsedResume|null
// rather than a loose object - it's exactly that shape once status is
// 'completed' (see ParsedResumeDisplay.vue, the one place this gets
// rendered), null otherwise.
export interface ResumeAnalysis {
  id: string
  document_id: string
  status: AIJobStatus
  parsed_data: ParsedResume | null
  error_message: string | null
  created_at: string
  updated_at: string
}

export interface ResumeAnalysisListResponse {
  items: ResumeAnalysis[]
  total: number
  page: number
  page_size: number
}

export interface ResumeAnalysisListParams {
  document_id?: string
  page?: number
  page_size?: number
}

// --- ATS scores ----------------------------------------------------------

export interface AtsScoreCreatePayload {
  resume_analysis_id: string
  application_id?: string | null
  /** Optional - prefers the linked application's job_url when omitted.
   * Server-enforced 50-20000 char bounds when provided; see
   * AtsScoresView.vue's create dialog for the client-side hint. */
  job_description?: string | null
}

// Mirrors AtsScoreRead. `feedback` is typed as AtsScoreResult|null for the
// same reason ResumeAnalysis.parsed_data is - exact shape once completed.
export interface AtsScore {
  id: string
  resume_analysis_id: string
  application_id: string | null
  job_description: string | null
  job_description_source: 'pasted' | 'url' | null
  status: AIJobStatus
  score: number | null
  feedback: AtsScoreResult | null
  error_message: string | null
  created_at: string
  updated_at: string
}

export interface AtsScoreListResponse {
  items: AtsScore[]
  total: number
  page: number
  page_size: number
}

export interface AtsScoreListParams {
  application_id?: string
  page?: number
  page_size?: number
}
