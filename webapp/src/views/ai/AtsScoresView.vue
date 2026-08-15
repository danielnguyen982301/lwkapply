<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import Button from 'primevue/button'
import Column from 'primevue/column'
import DataTable from 'primevue/datatable'
import Dialog from 'primevue/dialog'
import Message from 'primevue/message'
import Paginator from 'primevue/paginator'
import ProgressSpinner from 'primevue/progressspinner'
import Select from 'primevue/select'
import SelectButton from 'primevue/selectbutton'
import Tag from 'primevue/tag'
import Textarea from 'primevue/textarea'

import AiToolsTabs from '@/components/ai/AiToolsTabs.vue'
import ApplicationPicker from '@/components/ai/ApplicationPicker.vue'
import AtsScoreDisplay from '@/components/ai/AtsScoreDisplay.vue'
import { useAtsScoresStore } from '@/stores/atsScores'
import { useResumeAnalysesStore } from '@/stores/resumeAnalyses'
import { useDocumentDirectoryStore } from '@/stores/documentDirectory'
import { useApplicationsStore } from '@/stores/applications'
import {
  AI_JOB_STATUS_LABELS,
  aiJobStatusSeverity,
  atsScoreSeverity,
  isAiJobInFlight,
} from '@/lib/ai-ui'
import type { AtsScore, ResumeAnalysis } from '@/types/ai'
import type { Application } from '@/types/application'
import type { DocumentWithApplication } from '@/types/document'

const route = useRoute()
const router = useRouter()
const store = useAtsScoresStore()
const resumeAnalyses = useResumeAnalysesStore()
const documentDirectory = useDocumentDirectoryStore()
const applications = useApplicationsStore()

// --- friendly resume labels, same approach as ResumeAnalysesView.vue -----
const documentLabels = ref<Record<string, string>>({})

async function loadDocumentLabels() {
  const docs = await documentDirectory
    .searchResumeDocuments('', 100)
    .catch(() => [] as DocumentWithApplication[])
  documentLabels.value = Object.fromEntries(docs.map((doc) => [doc.id, doc.file_name]))
}

const dateFormatter = new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' })

// resume_analysis_id -> document_id, built once on mount from the same
// fetch the create dialog's picker needs (see loadResumeAnalysisIndex()
// below) - deliberately NOT read from stores/resumeAnalyses.ts's `items`,
// which is only populated once the Resume Analyses tab has actually been
// visited in this session and would silently show blank labels otherwise.
const resumeAnalysisIndex = ref<Record<string, string>>({})

function resumeLabelFor(resumeAnalysisId: string): string {
  const documentId = resumeAnalysisIndex.value[resumeAnalysisId]
  return (documentId && documentLabels.value[documentId]) || 'Resume analysis'
}

// --- list ----------------------------------------------------------------
function loadList(page = 1) {
  store.fetchAtsScores({ page }).catch(() => {})
}

const paginatorFirst = computed(() => (store.page - 1) * store.pageSize)

async function onPageChange(event: { first: number; rows: number }) {
  await store.fetchAtsScores({ page: Math.floor(event.first / event.rows) + 1 }).catch(() => {})
}

// --- create dialog ---------------------------------------------------
const createDialogVisible = ref(false)
const completedAnalyses = ref<ResumeAnalysis[]>([])
const selectedAnalysisId = ref<string | null>(null)

type DescriptionSource = 'application' | 'paste'
const descriptionSourceOptions = [
  { label: 'Use a tracked application', value: 'application' as DescriptionSource },
  { label: 'Paste a job description', value: 'paste' as DescriptionSource },
]
const descriptionSource = ref<DescriptionSource>('application')
const selectedApplication = ref<Application | null>(null)
const pastedDescription = ref('')

async function loadResumeAnalysisIndex() {
  const analyses = await resumeAnalyses.fetchCompletedForPicker().catch(() => [])
  completedAnalyses.value = analyses
  resumeAnalysisIndex.value = Object.fromEntries(
    analyses.map((analysis) => [analysis.id, analysis.document_id]),
  )
}

async function openCreateDialog() {
  selectedAnalysisId.value = null
  descriptionSource.value = 'application'
  selectedApplication.value = null
  pastedDescription.value = ''
  await loadResumeAnalysisIndex()

  const preselected = route.query.resume_analysis_id
  if (
    typeof preselected === 'string' &&
    completedAnalyses.value.some((a) => a.id === preselected)
  ) {
    selectedAnalysisId.value = preselected
  }

  createDialogVisible.value = true
}

function closeCreateDialog() {
  createDialogVisible.value = false
  // Don't let a stale resume_analysis_id keep re-triggering the dialog on
  // a later mount/query change - clear it once the dialog's been handled.
  if (route.query.resume_analysis_id) {
    router.replace({ name: 'ats-scores' })
  }
}

const canSubmit = computed(() => {
  if (!selectedAnalysisId.value) return false
  if (descriptionSource.value === 'application') return !!selectedApplication.value
  return pastedDescription.value.trim().length >= 50
})

async function handleCreate() {
  if (!selectedAnalysisId.value || !canSubmit.value) return
  try {
    const score = await store.create({
      resume_analysis_id: selectedAnalysisId.value,
      application_id:
        descriptionSource.value === 'application' ? selectedApplication.value?.id : null,
      job_description: descriptionSource.value === 'paste' ? pastedDescription.value : null,
    })
    createDialogVisible.value = false
    if (route.query.resume_analysis_id) router.replace({ name: 'ats-scores' })
    openDetailDialog(score)
    loadList(store.page)
  } catch {
    // store.createError is already set and rendered in the dialog below.
  }
}

// --- detail dialog -----------------------------------------------------
const detailDialogVisible = ref(false)

// Fetched (isolated - see applications.ts::fetchApplicationById) whenever
// the open score has an application_id, so the detail view can say
// "Scored against Acme Corp — Backend Engineer" instead of just a job_url
// source tag with no indication of *which* job. Cleared for scores with
// no application_id (a standalone, pasted-description score).
const detailApplication = ref<Application | null>(null)

async function loadDetailApplication(applicationId: string | null) {
  detailApplication.value = applicationId
    ? await applications.fetchApplicationById(applicationId).catch(() => null)
    : null
}

function openDetailDialog(score: AtsScore) {
  store.current = score
  retryDescription.value = ''
  detailDialogVisible.value = true
  loadDetailApplication(score.application_id)
  if (isAiJobInFlight(score.status)) store.startPolling(score.id)
}

function closeDetailDialog() {
  detailDialogVisible.value = false
  store.stopPolling()
}

// --- failed-score retry: the create dialog's job-description toggle
// (application job_url vs. paste) isn't available once a score already
// exists and failed - most commonly because the linked application's
// job_url couldn't be fetched (see backend/app/tasks/ai.py's
// JobDescriptionUnavailableError message, which explicitly asks the
// caller to resubmit with job_description pasted). Without this, a
// job_url failure was a dead end with no way to recover from the detail
// dialog. Retrying always creates a new AtsScore (no update-in-place
// endpoint exists) - store.create() already assigns the result to
// `current`, so the dialog naturally swaps to the new attempt.
const retryDescription = ref('')

async function retryWithPastedDescription() {
  if (!store.current) return
  try {
    await store.create({
      resume_analysis_id: store.current.resume_analysis_id,
      application_id: store.current.application_id,
      job_description: retryDescription.value,
    })
    loadList(store.page)
  } catch {
    // store.createError is already set and rendered below.
  }
}

// Vue template expressions can't parse an inline arrow function with a
// typed destructured parameter - named here instead of written inline in
// @row-click below (same reason as ResumeAnalysesView.vue's handleRowClick).
function handleRowClick(event: { data: AtsScore }) {
  openDetailDialog(event.data)
}

onMounted(() => {
  loadList()
  loadDocumentLabels()
  loadResumeAnalysisIndex()
  if (typeof route.query.resume_analysis_id === 'string') openCreateDialog()
})

// Covers navigating here again with a different resume_analysis_id while
// already on this route (Vue Router won't remount the component for a
// query-only change).
watch(
  () => route.query.resume_analysis_id,
  (value) => {
    if (typeof value === 'string' && !createDialogVisible.value) openCreateDialog()
  },
)

onBeforeUnmount(() => {
  store.stopPolling()
})
</script>

<template>
  <div class="space-y-4">
    <AiToolsTabs />

    <div class="flex items-center justify-between">
      <div>
        <h1 class="font-display text-xl font-semibold text-ink">ATS Scores</h1>
        <p class="mt-1 max-w-2xl text-sm text-slate">
          Score a completed resume analysis against a job description - either sourced from a
          tracked application's job URL, or pasted directly.
        </p>
      </div>
      <Button label="New Score" icon="pi pi-plus" size="small" @click="openCreateDialog" />
    </div>

    <Message v-if="store.listStatus === 'error'" severity="error" :closable="false">
      <span>{{ store.listError }}</span>
      <Button label="Retry" link size="small" class="ml-2" @click="loadList(store.page)" />
    </Message>

    <div
      v-else-if="store.listStatus === 'loading' && store.items.length === 0"
      aria-live="polite"
      class="flex justify-center rounded-card border border-slate/10 bg-white p-10"
    >
      <ProgressSpinner aria-label="Loading ATS scores" />
    </div>

    <div
      v-else-if="store.items.length === 0"
      class="rounded-card border border-dashed border-slate/30 p-10 text-center"
    >
      <h2 class="font-display text-lg font-semibold text-ink">No scores yet</h2>
      <p class="mx-auto mt-2 max-w-sm text-sm text-slate">
        Score a completed resume analysis against a job to see how well it matches.
      </p>
    </div>

    <div v-else class="space-y-0">
      <DataTable
        :value="store.items"
        :loading="store.listStatus === 'loading'"
        size="small"
        striped-rows
        aria-label="Your ATS scores"
        selection-mode="single"
        @row-click="handleRowClick"
      >
        <Column header="Resume">
          <template #body="{ data }: { data: AtsScore }">
            <span class="cursor-pointer font-medium text-ink hover:underline">
              {{ resumeLabelFor(data.resume_analysis_id) }}
            </span>
          </template>
        </Column>
        <Column header="Status">
          <template #body="{ data }: { data: AtsScore }">
            <Tag
              :value="AI_JOB_STATUS_LABELS[data.status]"
              :severity="aiJobStatusSeverity(data.status)"
            />
          </template>
        </Column>
        <Column header="Score">
          <template #body="{ data }: { data: AtsScore }">
            <Tag
              v-if="data.score !== null"
              :value="`${data.score}/100`"
              :severity="atsScoreSeverity(data.score)"
            />
            <span v-else class="text-slate">—</span>
          </template>
        </Column>
        <Column header="Source">
          <template #body="{ data }: { data: AtsScore }">
            <span v-if="data.job_description_source" class="text-sm text-slate">
              {{ data.job_description_source === 'url' ? 'Job URL' : 'Pasted' }}
            </span>
            <span v-else class="text-slate">—</span>
          </template>
        </Column>
        <Column header="Created">
          <template #body="{ data }: { data: AtsScore }">
            {{ dateFormatter.format(new Date(data.created_at)) }}
          </template>
        </Column>
      </DataTable>

      <Paginator
        :rows="store.pageSize"
        :total-records="store.total"
        :first="paginatorFirst"
        template="FirstPageLink PrevPageLink CurrentPageReport NextPageLink LastPageLink"
        current-page-report-template="Page {currentPage} of {totalPages}"
        class="border-x border-b border-slate/10 bg-white"
        @page="onPageChange"
      />
    </div>
  </div>

  <Dialog
    v-model:visible="createDialogVisible"
    header="New ATS score"
    modal
    class="w-full max-w-lg"
    @hide="closeCreateDialog"
  >
    <form class="space-y-4" @submit.prevent="handleCreate">
      <Message v-if="store.createStatus === 'error'" severity="error" :closable="false">
        {{ store.createError }}
      </Message>

      <div class="flex flex-col gap-1">
        <label for="ats-resume" class="text-sm font-medium text-ink">Resume *</label>
        <Select
          v-model="selectedAnalysisId"
          input-id="ats-resume"
          :options="completedAnalyses"
          option-label="id"
          option-value="id"
          placeholder="Choose a completed analysis"
          class="w-full"
        >
          <template #option="{ option }: { option: ResumeAnalysis }">
            {{ resumeLabelFor(option.id) }}
          </template>
          <template #value="{ value }: { value: string | null }">
            <span v-if="value">{{ resumeLabelFor(value) }}</span>
            <span v-else class="text-slate">Choose a completed analysis</span>
          </template>
        </Select>
        <p v-if="completedAnalyses.length === 0" class="text-xs text-slate">
          No completed resume analyses yet - analyze a resume first.
        </p>
      </div>

      <div class="flex flex-col gap-2">
        <label class="text-sm font-medium text-ink">Job description *</label>
        <SelectButton
          v-model="descriptionSource"
          :options="descriptionSourceOptions"
          option-label="label"
          option-value="value"
          :allow-empty="false"
          aria-label="Job description source"
        />

        <ApplicationPicker
          v-if="descriptionSource === 'application'"
          v-model="selectedApplication"
        />

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
      </div>

      <div class="flex items-center justify-end gap-3 border-t border-slate/10 pt-4">
        <Button
          label="Cancel"
          severity="secondary"
          outlined
          type="button"
          @click="closeCreateDialog"
        />
        <Button
          type="submit"
          :label="store.createStatus === 'loading' ? 'Starting…' : 'Score'"
          :loading="store.createStatus === 'loading'"
          :disabled="!canSubmit"
        />
      </div>
    </form>
  </Dialog>

  <Dialog
    v-model:visible="detailDialogVisible"
    header="ATS score"
    modal
    class="w-full max-w-2xl"
    @hide="closeDetailDialog"
  >
    <template v-if="store.current">
      <div
        v-if="isAiJobInFlight(store.current.status)"
        class="flex flex-col items-center gap-3 py-10"
        aria-live="polite"
      >
        <ProgressSpinner
          aria-label="Scoring against the job description"
          style="width: 2.5rem; height: 2.5rem"
        />
        <p class="text-sm text-slate">Scoring against the job description…</p>
        <Message v-if="store.pollingTimedOut" severity="warn" :closable="false" class="mt-2">
          This is taking longer than expected. Close and reopen this score to check again.
        </Message>
      </div>

      <template v-else-if="store.current.status === 'failed'">
        <Message severity="error" :closable="false">
          {{ store.current.error_message ?? 'This score failed. Try again.' }}
        </Message>

        <div class="mt-3 space-y-2">
          <label for="ats-retry-description" class="text-sm font-medium text-ink">
            Paste the job description to retry
          </label>
          <Textarea
            id="ats-retry-description"
            v-model="retryDescription"
            rows="5"
            class="w-full"
            placeholder="Paste the job description here…"
          />
          <p class="text-xs text-slate">
            {{ retryDescription.trim().length }} / 20000 characters (minimum 50)
          </p>
          <Message v-if="store.createStatus === 'error'" severity="error" :closable="false">
            {{ store.createError }}
          </Message>
          <Button
            label="Retry with pasted description"
            size="small"
            :loading="store.createStatus === 'loading'"
            :disabled="retryDescription.trim().length < 50"
            @click="retryWithPastedDescription"
          />
        </div>
      </template>

      <AtsScoreDisplay
        v-else-if="store.current.status === 'completed' && store.current.feedback"
        :score="store.current.feedback"
        :job-description="store.current.job_description"
        :job-description-source="store.current.job_description_source"
        :application-summary="detailApplication"
      />
    </template>
  </Dialog>
</template>
