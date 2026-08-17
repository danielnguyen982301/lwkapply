<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import InputText from 'primevue/inputtext'
import Message from 'primevue/message'
import ProgressSpinner from 'primevue/progressspinner'
import SelectButton from 'primevue/selectbutton'
import Tag from 'primevue/tag'
import Textarea from 'primevue/textarea'

import ParsedResumeDisplay from './ParsedResumeDisplay.vue'
import AtsScoreDisplay from './AtsScoreDisplay.vue'
import ApplicationPicker from './ApplicationPicker.vue'
import { useResumeAnalysesStore } from '@/stores/resumeAnalyses'
import { useAtsScoresStore } from '@/stores/atsScores'
import { isAiJobInFlight } from '@/lib/ai-ui'
import { formatDateTime } from '@/lib/date-utils'
import type { Application } from '@/types/application'

// Opened from views/documents/DocumentDirectoryView.vue, one row at a
// time - the Document Library's own "View AI analysis" action, alongside
// components/applications/DocumentsPanel.vue's identically-named one.
// Same analysis/score display and load()/polling shape as
// components/ai/ResumeAnalysisModal.vue (see that file for the full
// reasoning - only the *latest* analysis/score for documentId, `current`/
// polling reused directly since these two modals are never both mounted
// at once).
//
// The one real difference: DocumentsPanel.vue is reached from a specific
// application's detail page, so ResumeAnalysisModal.vue can offer a
// single "Score now" button that auto-scores against that application's
// job_url (with a paste fallback). A document in the library isn't tied
// to any one application, so there's no such job_url to default to here -
// scoring always goes through the same 3-option
// application/url/paste picker NewAtsScoreDialog.vue uses, just inlined
// (resume_analysis_id is already fixed to the loaded analysis, so there's
// no separate resume picker needed).
const props = defineProps<{ documentId: string }>()
const visible = defineModel<boolean>('visible', { default: false })

const resumeAnalyses = useResumeAnalysesStore()
const atsScores = useAtsScoresStore()
const loading = ref(false)

// --- score form (application / url / paste) -----------------------------
type DescriptionSource = 'application' | 'url' | 'paste'
const descriptionSourceOptions = [
  { label: 'Use a tracked application', value: 'application' as DescriptionSource },
  { label: 'Paste a job URL', value: 'url' as DescriptionSource },
  { label: 'Paste a job description', value: 'paste' as DescriptionSource },
]
const descriptionSource = ref<DescriptionSource>('application')
const selectedApplication = ref<Application | null>(null)
const pastedJobUrl = ref('')
const pastedDescription = ref('')

function resetScoreForm() {
  descriptionSource.value = 'application'
  selectedApplication.value = null
  pastedJobUrl.value = ''
  pastedDescription.value = ''
}

const canSubmitScore = computed(() => {
  if (descriptionSource.value === 'application') return !!selectedApplication.value?.job_url
  if (descriptionSource.value === 'url') return pastedJobUrl.value.trim().length > 0
  return pastedDescription.value.trim().length >= 50
})

async function submitScore() {
  if (!resumeAnalyses.current || !canSubmitScore.value) return
  await atsScores
    .create({
      resume_analysis_id: resumeAnalyses.current.id,
      job_url:
        descriptionSource.value === 'application'
          ? selectedApplication.value?.job_url
          : descriptionSource.value === 'url'
            ? pastedJobUrl.value.trim()
            : null,
      job_description: descriptionSource.value === 'paste' ? pastedDescription.value : null,
    })
    .catch(() => {})
}

// Same "score again without losing the existing score's display until
// the new one completes" reasoning as ResumeAnalysisModal.vue's
// showRescoreForm.
const showRescoreForm = ref(false)
const showScoreForm = computed(() => !atsScores.current || showRescoreForm.value)

function openRescoreForm() {
  resetScoreForm()
  showRescoreForm.value = true
}

// Same "Latest" framing as ResumeAnalysisModal.vue - both null only on a
// pending/processing/failed run.
const analyzedAt = computed(() =>
  resumeAnalyses.current?.completed_at ? formatDateTime(resumeAnalyses.current.completed_at) : null,
)
const scoredAt = computed(() =>
  atsScores.current?.scored_at ? formatDateTime(atsScores.current.scored_at) : null,
)

// Reuses `current`/polling on both stores directly - same as
// ResumeAnalysisModal.vue (see that file for why this is safe: the two
// modals are never both mounted at once).
async function loadRelatedScore() {
  if (!resumeAnalyses.current || resumeAnalyses.current.status !== 'completed') {
    atsScores.current = null
    return
  }
  atsScores.current = await atsScores
    .fetchLatestForResumeAnalysis(resumeAnalyses.current.id)
    .catch(() => null)
}

async function load() {
  loading.value = true
  resetScoreForm()
  showRescoreForm.value = false
  resumeAnalyses.current = await resumeAnalyses
    .fetchLatestForDocument(props.documentId)
    .catch(() => null)
  loading.value = false

  if (resumeAnalyses.current && isAiJobInFlight(resumeAnalyses.current.status)) {
    resumeAnalyses.startPolling(resumeAnalyses.current.id)
  } else {
    await loadRelatedScore()
  }
}

// immediate: true - same reasoning as ResumeAnalysisModal.vue: the caller
// (DocumentDirectoryView.vue) mounts this with v-if="analysisModalDocumentId"
// and sets visible=true in the same click handler, so there's no
// false->true transition on first open for a plain watch() to catch.
watch(
  visible,
  (isVisible) => {
    if (isVisible) {
      load()
    } else {
      resumeAnalyses.stopPolling()
      atsScores.stopPolling()
    }
  },
  { immediate: true },
)

watch(
  () => resumeAnalyses.current?.status,
  (status) => {
    if (status === 'completed') loadRelatedScore()
  },
)

watch(
  () => atsScores.current?.status,
  (status) => {
    if (status === 'completed') showRescoreForm.value = false
  },
)

async function analyzeNow() {
  await resumeAnalyses.create({ document_id: props.documentId }).catch(() => {})
}

// Same dual-source error reasoning as ResumeAnalysisModal.vue's
// atsScoreErrorMessage: an async job_url-fetch failure surfaces via
// atsScores.current.status/error_message once polling resolves it, a
// synchronous rejection (validation, no job_url) only via createError.
const atsScoreErrorMessage = computed(() => {
  if (atsScores.current?.status === 'failed') {
    return atsScores.current.error_message ?? 'Scoring failed. Try again.'
  }
  if (atsScores.createStatus === 'error') {
    return atsScores.createError
  }
  return null
})

onBeforeUnmount(() => {
  resumeAnalyses.stopPolling()
  atsScores.stopPolling()
})
</script>

<template>
  <Dialog
    v-model:visible="visible"
    header="Resume analysis"
    modal
    dismissable-mask
    class="w-full max-w-2xl"
  >
    <div v-if="loading" class="flex justify-center py-10" aria-live="polite">
      <ProgressSpinner aria-label="Loading" style="width: 2rem; height: 2rem" />
    </div>

    <div v-else-if="!resumeAnalyses.current" class="py-6 text-center">
      <p class="text-sm text-slate">No analysis yet for this resume.</p>
      <Message
        v-if="resumeAnalyses.createStatus === 'error'"
        severity="error"
        :closable="false"
        class="mt-4 text-left"
      >
        {{ resumeAnalyses.createError }}
      </Message>
      <Button
        label="Analyze now"
        class="mt-4"
        :loading="resumeAnalyses.createStatus === 'loading'"
        @click="analyzeNow"
      />
    </div>

    <template v-else>
      <div
        v-if="isAiJobInFlight(resumeAnalyses.current.status)"
        class="flex flex-col items-center gap-3 py-10"
        aria-live="polite"
      >
        <ProgressSpinner aria-label="Analyzing your resume" style="width: 2.5rem; height: 2.5rem" />
        <p class="text-sm text-slate">Analyzing your resume…</p>
      </div>

      <Message
        v-else-if="resumeAnalyses.current.status === 'failed'"
        severity="error"
        :closable="false"
      >
        {{ resumeAnalyses.current.error_message ?? 'This analysis failed. Try again.' }}
        <Button label="Try again" link size="small" class="ml-2" @click="analyzeNow" />
      </Message>

      <div v-else-if="resumeAnalyses.current.parsed_data" class="space-y-6">
        <p v-if="resumeAnalyses.current.analysis_name" class="text-sm font-medium text-ink">
          Analysis name: {{ resumeAnalyses.current.analysis_name }}
        </p>
        <div class="flex items-center gap-2">
          <Tag value="Latest" severity="info" />
          <span v-if="analyzedAt" class="text-xs text-slate">Analyzed {{ analyzedAt }}</span>
        </div>
        <ParsedResumeDisplay :parsed="resumeAnalyses.current.parsed_data" />

        <div class="border-t border-slate/10 pt-4">
          <div
            v-if="atsScores.current && isAiJobInFlight(atsScores.current.status)"
            class="flex flex-col items-center gap-3 py-6"
            aria-live="polite"
          >
            <ProgressSpinner
              aria-label="Scoring against this job"
              style="width: 2rem; height: 2rem"
            />
            <p class="text-sm text-slate">Scoring against this job…</p>
          </div>

          <div v-else class="space-y-4">
            <template
              v-if="atsScores.current?.status === 'completed' && atsScores.current.feedback"
            >
              <div class="flex items-center gap-2">
                <Tag value="Latest" severity="info" />
                <span v-if="scoredAt" class="text-xs text-slate">Scored {{ scoredAt }}</span>
              </div>
              <AtsScoreDisplay
                :score="atsScores.current.feedback"
                :job-description="atsScores.current.job_description"
                :job-description-source="atsScores.current.job_description_source"
                :job-url="atsScores.current.job_url"
              />
            </template>

            <div v-if="!showScoreForm" class="text-center">
              <Button
                label="Score again"
                icon="pi pi-refresh"
                link
                size="small"
                @click="openRescoreForm"
              />
            </div>

            <div
              v-else
              class="flex flex-col gap-2 text-left"
              :class="atsScores.current ? 'border-t border-slate/10 pt-4' : ''"
            >
              <p v-if="!atsScores.current" class="text-center text-sm text-slate">
                Not scored against a job yet.
              </p>

              <Message v-if="atsScoreErrorMessage" severity="error" :closable="false">
                {{ atsScoreErrorMessage }}
              </Message>

              <label class="text-sm font-medium text-ink">Job description *</label>
              <SelectButton
                v-model="descriptionSource"
                :options="descriptionSourceOptions"
                option-label="label"
                option-value="value"
                :allow-empty="false"
                aria-label="Job description source"
              />

              <template v-if="descriptionSource === 'application'">
                <ApplicationPicker v-model="selectedApplication" />
                <p
                  v-if="selectedApplication && !selectedApplication.job_url"
                  class="text-xs text-coral"
                >
                  This application has no job URL saved - paste the job description instead, or add
                  a job URL from the application's detail page first.
                </p>
              </template>

              <template v-else-if="descriptionSource === 'url'">
                <InputText
                  v-model="pastedJobUrl"
                  type="url"
                  class="w-full"
                  placeholder="https://…"
                  aria-label="Job posting URL"
                />
                <p class="text-xs text-slate">
                  We'll fetch and score against the job description at this URL.
                </p>
              </template>

              <template v-else>
                <Textarea
                  v-model="pastedDescription"
                  rows="6"
                  class="w-full"
                  placeholder="Paste the job description here…"
                />
                <p class="text-xs text-slate">
                  {{ pastedDescription.trim().length }} / 20000 characters (minimum 50)
                </p>
              </template>

              <div class="mt-1 flex items-center gap-3">
                <Button
                  :label="atsScores.current ? 'Score again' : 'Score now'"
                  :loading="atsScores.createStatus === 'loading'"
                  :disabled="!canSubmitScore"
                  @click="submitScore"
                />
                <Button
                  v-if="atsScores.current"
                  label="Cancel"
                  link
                  size="small"
                  @click="showRescoreForm = false"
                />
              </div>
            </div>
          </div>
        </div>
      </div>
    </template>
  </Dialog>
</template>
