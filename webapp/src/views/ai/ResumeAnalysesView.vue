<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import Button from 'primevue/button'
import Column from 'primevue/column'
import DataTable from 'primevue/datatable'
import Dialog from 'primevue/dialog'
import Message from 'primevue/message'
import Paginator from 'primevue/paginator'
import ProgressSpinner from 'primevue/progressspinner'
import Tag from 'primevue/tag'

import AiToolsTabs from '@/components/ai/AiToolsTabs.vue'
import ResumeDocumentPicker from '@/components/ai/ResumeDocumentPicker.vue'
import ParsedResumeDisplay from '@/components/ai/ParsedResumeDisplay.vue'
import TruncatedText from '@/components/common/TruncatedText.vue'
import { useResumeAnalysesStore } from '@/stores/resumeAnalyses'
import { useDocumentsStore } from '@/stores/documents'
import { AI_JOB_STATUS_LABELS, aiJobStatusSeverity, isAiJobInFlight } from '@/lib/ai-ui'
import type { ResumeAnalysis } from '@/types/ai'
import type { Document } from '@/types/document'

const router = useRouter()
const store = useResumeAnalysesStore()
const documents = useDocumentsStore()

// --- friendly row labels (document_id -> file_name) ---------------------
// ResumeAnalysisRead has no file_name, only document_id - see BACKEND_SUMMARY.md/
// the plan for why this is a frontend-only join rather than a backend change.
// page_size 100 (the backend's max) rather than the picker's default 10 -
// this wants every resume the user has, not just top search matches.
// Falls back to a date-based label for anything not found here (a document
// since deleted, or beyond the 100-resume cap).
const documentLabels = ref<Record<string, string>>({})

async function loadDocumentLabels() {
  const docs = await documents.searchDocuments('', 'resume', 100).catch(() => [] as Document[])
  documentLabels.value = Object.fromEntries(docs.map((doc) => [doc.id, doc.file_name]))
}

const dateFormatter = new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' })
// Date + time - completed_at is the one field that actually distinguishes
// re-runs of the same resume, so a date-only label would collapse them.
const dateTimeFormatter = new Intl.DateTimeFormat(undefined, {
  dateStyle: 'medium',
  timeStyle: 'short',
})

function labelFor(analysis: ResumeAnalysis): string {
  return (
    documentLabels.value[analysis.document_id] ??
    `Resume analysis · ${dateFormatter.format(new Date(analysis.created_at))}`
  )
}

function formatAnalyzedAt(value: string | null): string {
  return value ? dateTimeFormatter.format(new Date(value)) : '—'
}

// --- list ----------------------------------------------------------------
function loadList(page = 1) {
  store.fetchResumeAnalyses({ page }).catch(() => {})
}

const paginatorFirst = computed(() => (store.page - 1) * store.pageSize)

async function onPageChange(event: { first: number; rows: number }) {
  await store
    .fetchResumeAnalyses({ page: Math.floor(event.first / event.rows) + 1 })
    .catch(() => {})
}

// --- create dialog ---------------------------------------------------
const createDialogVisible = ref(false)
const selectedDocument = ref<Document | null>(null)

function openCreateDialog() {
  selectedDocument.value = null
  createDialogVisible.value = true
}

function closeCreateDialog() {
  createDialogVisible.value = false
}

async function handleCreate() {
  if (!selectedDocument.value) return
  try {
    const analysis = await store.create({ document_id: selectedDocument.value.id })
    createDialogVisible.value = false
    openDetailDialog(analysis)
    loadList(store.page)
  } catch {
    // store.createError is already set and rendered in the dialog below.
  }
}

// --- detail dialog (also the target of a freshly-created analysis) -----
const detailDialogVisible = ref(false)

function openDetailDialog(analysis: ResumeAnalysis) {
  store.current = analysis
  detailDialogVisible.value = true
  if (isAiJobInFlight(analysis.status)) store.startPolling(analysis.id)
}

function closeDetailDialog() {
  detailDialogVisible.value = false
  store.stopPolling()
}

function scoreAgainstJob() {
  if (!store.current) return
  detailDialogVisible.value = false
  router.push({ name: 'ats-scores', query: { resume_analysis_id: store.current.id } })
}

// Vue template expressions can't parse an inline arrow function with a
// typed destructured parameter (`({ data }: { data: X }) => ...`) - named
// here instead of written inline in @row-click below.
function handleRowClick(event: { data: ResumeAnalysis }) {
  openDetailDialog(event.data)
}

onMounted(() => {
  loadList()
  loadDocumentLabels()
})

onBeforeUnmount(() => {
  store.stopPolling()
})
</script>

<template>
  <div class="space-y-4">
    <AiToolsTabs />

    <div class="flex items-center justify-between">
      <div>
        <h1 class="font-display text-xl font-semibold text-ink">Resume Analyses</h1>
        <p class="mt-1 max-w-2xl text-sm text-slate">
          Pick one of your uploaded resumes to extract skills, work experience, and education with
          AI.
        </p>
      </div>
      <Button label="New Analysis" icon="pi pi-plus" size="small" @click="openCreateDialog" />
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
      <ProgressSpinner aria-label="Loading resume analyses" />
    </div>

    <div
      v-else-if="store.items.length === 0"
      class="rounded-card border border-dashed border-slate/30 p-10 text-center"
    >
      <h2 class="font-display text-lg font-semibold text-ink">No analyses yet</h2>
      <p class="mx-auto mt-2 max-w-sm text-sm text-slate">
        Start one from an already-uploaded resume.
      </p>
    </div>

    <div v-else class="space-y-0">
      <DataTable
        :value="store.items"
        :loading="store.listStatus === 'loading'"
        size="small"
        striped-rows
        aria-label="Your resume analyses"
        selection-mode="single"
        @row-click="handleRowClick"
      >
        <Column header="Resume">
          <template #body="{ data }: { data: ResumeAnalysis }">
            <TruncatedText
              :text="labelFor(data)"
              max-width="16rem"
              class="cursor-pointer font-medium text-ink hover:underline"
            />
          </template>
        </Column>
        <Column header="Status">
          <template #body="{ data }: { data: ResumeAnalysis }">
            <Tag
              :value="AI_JOB_STATUS_LABELS[data.status]"
              :severity="aiJobStatusSeverity(data.status)"
            />
          </template>
        </Column>
        <Column header="Created">
          <template #body="{ data }: { data: ResumeAnalysis }">
            {{ dateFormatter.format(new Date(data.created_at)) }}
          </template>
        </Column>
        <Column header="Analyzed At">
          <template #body="{ data }: { data: ResumeAnalysis }">
            {{ formatAnalyzedAt(data.completed_at) }}
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
    header="New resume analysis"
    modal
    class="w-full max-w-lg"
    @hide="closeCreateDialog"
  >
    <form class="space-y-4" @submit.prevent="handleCreate">
      <Message v-if="store.createStatus === 'error'" severity="error" :closable="false">
        {{ store.createError }}
      </Message>

      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-ink">Resume *</label>
        <ResumeDocumentPicker v-model="selectedDocument" />
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
          :label="store.createStatus === 'loading' ? 'Starting…' : 'Analyze'"
          :loading="store.createStatus === 'loading'"
          :disabled="!selectedDocument"
        />
      </div>
    </form>
  </Dialog>

  <Dialog
    v-model:visible="detailDialogVisible"
    header="Resume analysis"
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
        <ProgressSpinner aria-label="Analyzing your resume" style="width: 2.5rem; height: 2.5rem" />
        <p class="text-sm text-slate">Analyzing your resume…</p>
        <Message v-if="store.pollingTimedOut" severity="warn" :closable="false" class="mt-2">
          This is taking longer than expected. Close and reopen this analysis to check again.
        </Message>
      </div>

      <Message v-else-if="store.current.status === 'failed'" severity="error" :closable="false">
        {{ store.current.error_message ?? 'This analysis failed. Try again.' }}
      </Message>

      <div v-else-if="store.current.status === 'completed' && store.current.parsed_data">
        <ParsedResumeDisplay :parsed="store.current.parsed_data" />
        <div class="mt-6 flex justify-end border-t border-slate/10 pt-4">
          <Button label="Score against a job" icon="pi pi-arrow-right" @click="scoreAgainstJob" />
        </div>
      </div>
    </template>
  </Dialog>
</template>
