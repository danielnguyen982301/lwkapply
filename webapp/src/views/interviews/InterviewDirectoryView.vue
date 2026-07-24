<script setup lang="ts">
import { computed, onMounted } from 'vue'
import { RouterLink } from 'vue-router'
import Button from 'primevue/button'
import Column from 'primevue/column'
import DataTable from 'primevue/datatable'
import Message from 'primevue/message'
import Paginator from 'primevue/paginator'
import ProgressSpinner from 'primevue/progressspinner'
import Select from 'primevue/select'
import Tag from 'primevue/tag'

import { useInterviewDirectoryStore } from '@/stores/interviewDirectory'
import ApplicationStatusTag from '@/components/applications/ApplicationStatusTag.vue'
import {
  INTERVIEW_RESULT_LABELS,
  INTERVIEW_TYPE_LABELS,
  interviewResultFilterOptions,
  interviewResultSeverity,
} from '@/lib/interview-ui'
import type { InterviewResult, InterviewWithApplication } from '@/types/interview'

const store = useInterviewDirectoryStore()

const resultFilterOptions = interviewResultFilterOptions()

const hasActiveFilter = computed(() => store.result !== null)

async function handleResultFilterChange(value: InterviewResult | null) {
  await store.setResultFilter(value).catch(() => {})
}

function clearFilter() {
  store.setResultFilter(null).catch(() => {})
}

onMounted(() => {
  store.fetchInterviews().catch(() => {})
})

const paginatorFirst = computed(() => (store.page - 1) * store.pageSize)

async function onPageChange(event: { first: number; rows: number }) {
  const page = Math.floor(event.first / event.rows) + 1
  await store.fetchInterviews({ page }).catch(() => {})
}

// Kept local rather than pulled from a shared date helper, since only
// this view needs a "date + time" display for a directory row (the panel
// version, InterviewsPanel.vue, formats via its own Dialog fields).
const dateFormatter = new Intl.DateTimeFormat(undefined, {
  dateStyle: 'medium',
  timeStyle: 'short',
})

function formatScheduledAt(value: string): string {
  return dateFormatter.format(new Date(value))
}
</script>

<template>
  <div class="space-y-4">
    <div class="flex items-center justify-between">
      <h1 class="font-display text-xl font-semibold text-ink">Interviews</h1>
    </div>

    <p class="max-w-2xl text-sm text-slate">
      Every interview across all your applications, in one place. To schedule or edit an interview,
      open the application it belongs to.
    </p>

    <div class="flex flex-wrap items-center gap-3">
      <Select
        :model-value="store.result"
        :options="resultFilterOptions"
        option-label="label"
        option-value="value"
        class="w-56"
        aria-label="Filter interviews by result"
        @update:model-value="handleResultFilterChange"
      />
    </div>

    <Message v-if="store.listStatus === 'error'" severity="error" :closable="false">
      <span>{{ store.listError }}</span>
      <Button
        label="Retry"
        link
        size="small"
        class="ml-2"
        @click="store.fetchInterviews().catch(() => {})"
      />
    </Message>

    <div
      v-else-if="store.listStatus === 'loading' && store.items.length === 0"
      aria-live="polite"
      class="flex justify-center rounded-card border border-slate/10 bg-white p-10"
    >
      <ProgressSpinner aria-label="Loading interviews" />
    </div>

    <div
      v-else-if="store.items.length === 0"
      class="rounded-card border border-dashed border-slate/30 p-10 text-center"
    >
      <h2 class="font-display text-lg font-semibold text-ink">
        {{ hasActiveFilter ? 'No matching interviews' : 'No interviews yet' }}
      </h2>
      <p class="mx-auto mt-2 max-w-sm text-sm text-slate">
        <template v-if="hasActiveFilter">Try a different result filter.</template>
        <template v-else>
          Schedule an interview from within an application's detail page and it'll show up here.
        </template>
      </p>
      <Button v-if="hasActiveFilter" label="Clear filter" link class="mt-4" @click="clearFilter" />
    </div>

    <div v-else class="space-y-0">
      <DataTable
        :value="store.items"
        :loading="store.listStatus === 'loading'"
        size="small"
        striped-rows
        aria-label="All your interviews"
      >
        <Column header="Scheduled">
          <template #body="{ data }: { data: InterviewWithApplication }">
            <span class="font-medium text-ink">{{ formatScheduledAt(data.scheduled_at) }}</span>
          </template>
        </Column>
        <Column header="Type">
          <template #body="{ data }: { data: InterviewWithApplication }">
            {{ INTERVIEW_TYPE_LABELS[data.type] }}
          </template>
        </Column>
        <Column header="Company">
          <template #body="{ data }: { data: InterviewWithApplication }">
            <RouterLink
              :to="{ name: 'application-detail', params: { id: data.application.id } }"
              class="text-ink hover:underline"
            >
              {{ data.application.company }}
            </RouterLink>
          </template>
        </Column>
        <Column header="Position">
          <template #body="{ data }: { data: InterviewWithApplication }">
            {{ data.application.position }}
          </template>
        </Column>
        <Column header="Status">
          <template #body="{ data }: { data: InterviewWithApplication }">
            <ApplicationStatusTag :status="data.application.status" />
          </template>
        </Column>
        <Column header="Result">
          <template #body="{ data }: { data: InterviewWithApplication }">
            <Tag
              :value="INTERVIEW_RESULT_LABELS[data.result]"
              :severity="interviewResultSeverity(data.result)"
            />
          </template>
        </Column>
        <Column header="Duration">
          <template #body="{ data }: { data: InterviewWithApplication }">
            {{ data.duration_minutes ? `${data.duration_minutes} min` : '—' }}
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
</template>
