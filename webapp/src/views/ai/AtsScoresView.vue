<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import Button from 'primevue/button'
import Column from 'primevue/column'
import DataTable from 'primevue/datatable'
import Message from 'primevue/message'
import Paginator from 'primevue/paginator'
import ProgressSpinner from 'primevue/progressspinner'
import Tag from 'primevue/tag'

import AiToolsTabs from '@/components/ai/AiToolsTabs.vue'
import NewAtsScoreDialog from '@/components/ai/NewAtsScoreDialog.vue'
import AtsScoreDetailDialog from '@/components/ai/AtsScoreDetailDialog.vue'
import ResumeAnalysisDetailDialog from '@/components/ai/ResumeAnalysisDetailDialog.vue'
import TruncatedText from '@/components/common/TruncatedText.vue'
import { useAtsScoresStore } from '@/stores/atsScores'
import { useResumeAnalysesStore } from '@/stores/resumeAnalyses'
import { AI_JOB_STATUS_LABELS, aiJobStatusSeverity, atsScoreSeverity } from '@/lib/ai-ui'
import { formatDate } from '@/lib/date-utils'
import type { AtsScore } from '@/types/ai'

const route = useRoute()
const router = useRouter()
const store = useAtsScoresStore()
const resumeAnalysesStore = useResumeAnalysesStore()

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

// Prefilled via ?resume_analysis_id=... arriving from ResumeAnalysesView.vue's
// "Score against a job" button - read live off the route so a later
// query change (Vue Router won't remount this component for a query-only
// change) is picked up by the watcher below.
const preselectedResumeAnalysisId = computed(() =>
  typeof route.query.resume_analysis_id === 'string' ? route.query.resume_analysis_id : null,
)

function openCreateDialog() {
  createDialogVisible.value = true
}

// Don't let a stale resume_analysis_id keep re-triggering the dialog on
// a later mount/query change - clear it once the dialog's been closed by
// any path (Cancel, successful create, clicking outside).
watch(createDialogVisible, (isVisible) => {
  if (!isVisible && route.query.resume_analysis_id) {
    router.replace({ name: 'ats-scores' })
  }
})

function handleScoreCreated(score: AtsScore) {
  openDetailDialog(score)
  loadList(store.page)
}

// --- detail dialog -----------------------------------------------------
const detailDialogVisible = ref(false)

function openDetailDialog(score: AtsScore) {
  store.current = score
  detailDialogVisible.value = true
}

// Vue template expressions can't parse an inline arrow function with a
// typed destructured parameter - named here instead of written inline in
// @row-click below (same reason as ResumeAnalysesView.vue's handleRowClick).
function handleRowClick(event: { data: AtsScore }) {
  openDetailDialog(event.data)
}

// --- resume analysis dialog (reused from ResumeAnalysesView.vue) -------
// AtsScore only carries resume_analysis_id/document_file_name/analysis_name,
// not the full parsed analysis - fetch it on demand rather than joining
// server-side just for this one click-through.
const analysisDialogVisible = ref(false)
const loadingAnalysisId = ref<string | null>(null)

async function openAnalysisDialog(score: AtsScore) {
  loadingAnalysisId.value = score.id
  try {
    await resumeAnalysesStore.fetchOne(score.resume_analysis_id)
    analysisDialogVisible.value = true
  } catch {
    // resumeAnalysesStore.currentError is already set; nothing else to do here
  } finally {
    loadingAnalysisId.value = null
  }
}

onMounted(() => {
  loadList()
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
  resumeAnalysesStore.stopPolling()
})
</script>

<template>
  <div class="space-y-4">
    <AiToolsTabs />

    <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
      <div>
        <h1 class="font-display text-xl font-semibold text-ink">ATS Scores</h1>
        <p class="mt-1 max-w-2xl text-sm text-slate">
          Score a completed resume analysis against a job description - sourced from a tracked
          application's job URL, a pasted job URL, or pasted directly.
        </p>
      </div>
      <Button
        label="New Score"
        icon="pi pi-plus"
        size="small"
        class="self-start"
        @click="openCreateDialog"
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
      <div class="overflow-x-auto">
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
              <TruncatedText
                :text="data.document_file_name"
                max-width="16rem"
                class="cursor-pointer font-medium text-ink hover:underline"
              />
            </template>
          </Column>
          <Column field="analysis_name" header="Analysis used">
            <template #body="{ data }: { data: AtsScore }">
              <ProgressSpinner
                v-if="loadingAnalysisId === data.id"
                style="width: 1rem; height: 1rem"
                stroke-width="6"
                aria-label="Loading analysis"
              />
              <TruncatedText
                v-else
                :text="data.analysis_name"
                max-width="14rem"
                class="cursor-pointer font-medium text-ink hover:underline"
                @click.stop="openAnalysisDialog(data)"
              />
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
              {{ formatDate(data.created_at) }}
            </template>
          </Column>
        </DataTable>
      </div>

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

  <NewAtsScoreDialog
    v-model:visible="createDialogVisible"
    :initial-resume-analysis-id="preselectedResumeAnalysisId"
    @created="handleScoreCreated"
  />

  <AtsScoreDetailDialog v-model:visible="detailDialogVisible" @retried="loadList(store.page)" />

  <ResumeAnalysisDetailDialog v-model:visible="analysisDialogVisible" />
</template>
