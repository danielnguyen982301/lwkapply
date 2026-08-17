<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import Button from 'primevue/button'
import Column from 'primevue/column'
import DataTable from 'primevue/datatable'
import Message from 'primevue/message'
import Paginator from 'primevue/paginator'
import ProgressSpinner from 'primevue/progressspinner'
import Tag from 'primevue/tag'

import AiToolsTabs from '@/components/ai/AiToolsTabs.vue'
import NewResumeAnalysisDialog from '@/components/ai/NewResumeAnalysisDialog.vue'
import ResumeAnalysisDetailDialog from '@/components/ai/ResumeAnalysisDetailDialog.vue'
import EditAnalysisNameDialog from '@/components/ai/EditAnalysisNameDialog.vue'
import TruncatedText from '@/components/common/TruncatedText.vue'
import { tooltip } from '@/lib/tooltip'
import { useResumeAnalysesStore } from '@/stores/resumeAnalyses'
import { AI_JOB_STATUS_LABELS, aiJobStatusSeverity } from '@/lib/ai-ui'
import { formatDate, formatDateTime } from '@/lib/date-utils'
import type { ResumeAnalysis } from '@/types/ai'

const store = useResumeAnalysesStore()

// Date + time - completed_at is the one field that actually distinguishes
// re-runs of the same resume, so a date-only label would collapse them.
function formatAnalyzedAt(value: string | null): string {
  return value ? formatDateTime(value) : '—'
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

function handleCreated(analysis: ResumeAnalysis) {
  openDetailDialog(analysis)
  loadList(store.page)
}

// --- detail dialog (also the target of a freshly-created analysis) -----
const detailDialogVisible = ref(false)

function openDetailDialog(analysis: ResumeAnalysis) {
  store.current = analysis
  detailDialogVisible.value = true
}

// Vue template expressions can't parse an inline arrow function with a
// typed destructured parameter (`({ data }: { data: X }) => ...`) - named
// here instead of written inline in @row-click below. Skips clicks that
// originated on the row's own rename button - same target.closest('a,
// button') guard as lib/row-click.ts's useApplicationRowClick, just
// opening a local dialog here instead of navigating.
function handleRowClick(event: { originalEvent: Event; data: ResumeAnalysis }) {
  const target = event.originalEvent.target as HTMLElement
  if (target.closest('a, button')) return
  openDetailDialog(event.data)
}

// --- edit (rename) dialog ------------------------------------------------
const editDialogVisible = ref(false)
const editingAnalysis = ref<ResumeAnalysis | null>(null)

function openEditDialog(analysis: ResumeAnalysis) {
  editingAnalysis.value = analysis
  editDialogVisible.value = true
}

onMounted(() => {
  loadList()
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
      <Button
        label="New Analysis"
        icon="pi pi-plus"
        size="small"
        @click="createDialogVisible = true"
      />
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
              :text="data.document_file_name"
              max-width="16rem"
              class="cursor-pointer font-medium text-ink hover:underline"
            />
          </template>
        </Column>
        <Column field="analysis_name" header="Analysis name">
          <template #body="{ data }: { data: ResumeAnalysis }">
            <div class="flex items-center gap-1">
              <TruncatedText :text="data.analysis_name" max-width="14rem" />
              <Button
                v-if="data.status === 'completed'"
                v-tooltip.bottom="tooltip('Rename analysis')"
                icon="pi pi-pencil"
                aria-label="Rename analysis"
                link
                size="small"
                @click="openEditDialog(data)"
              />
            </div>
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
            {{ formatDate(data.created_at) }}
          </template>
        </Column>
        <Column header="Analyzed at">
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

  <NewResumeAnalysisDialog v-model:visible="createDialogVisible" @created="handleCreated" />

  <ResumeAnalysisDetailDialog v-model:visible="detailDialogVisible" />

  <EditAnalysisNameDialog v-model:visible="editDialogVisible" :analysis="editingAnalysis" />
</template>
