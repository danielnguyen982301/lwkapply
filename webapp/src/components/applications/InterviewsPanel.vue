<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref, watch } from 'vue'
import Button from 'primevue/button'
import Card from 'primevue/card'
import Message from 'primevue/message'
import Paginator from 'primevue/paginator'
import ProgressSpinner from 'primevue/progressspinner'
import Tag from 'primevue/tag'
import { useConfirm } from 'primevue/useconfirm'
import { DateTime } from 'luxon'
import { tooltip } from '@/lib/tooltip'

import { useInterviewsStore } from '@/stores/interviews'
import {
  INTERVIEW_RESULT_LABELS,
  INTERVIEW_TYPE_LABELS,
  interviewResultSeverity,
} from '@/lib/interview-ui'
import InterviewFormDialog from '@/components/interviews/InterviewFormDialog.vue'
import type { Interview } from '@/types/interview'

const props = defineProps<{ applicationId: string }>()

const store = useInterviewsStore()
const confirm = useConfirm()

const dialogVisible = ref(false)
const editingInterview = ref<Interview | null>(null)

function openAddDialog() {
  editingInterview.value = null
  dialogVisible.value = true
}

function openEditDialog(interview: Interview) {
  editingInterview.value = interview
  dialogVisible.value = true
}

function confirmDelete(interview: Interview) {
  confirm.require({
    message: `Delete this ${INTERVIEW_TYPE_LABELS[interview.type]} interview? This can't be undone.`,
    header: 'Confirm deletion',
    icon: 'pi pi-exclamation-triangle',
    rejectLabel: 'Cancel',
    acceptLabel: 'Delete',
    rejectProps: { label: 'Cancel', severity: 'secondary', outlined: true },
    acceptProps: { label: 'Delete', severity: 'danger' },
    accept: () => {
      store.deleteInterview(props.applicationId, interview.id).catch(() => {})
    },
  })
}

function loadInterviews(page = 1) {
  store.fetchInterviews(props.applicationId, { page }).catch(() => {})
}

function onPageChange(event: { page: number }) {
  loadInterviews(event.page + 1)
}

function formatScheduledAt(iso: string): string {
  return DateTime.fromISO(iso).toLocaleString({
    dateStyle: 'medium',
    timeStyle: 'short',
  })
}

onMounted(() => loadInterviews())

watch(
  () => props.applicationId,
  (newId, oldId) => {
    if (newId && newId !== oldId) loadInterviews()
  },
)

onBeforeUnmount(() => {
  store.reset()
})
</script>

<template>
  <Card>
    <template #content>
      <div class="space-y-4">
        <div class="flex flex-wrap items-center justify-between gap-2">
          <h2 class="font-display text-lg font-semibold text-ink">Interviews</h2>
          <Button
            label="Schedule interview"
            icon="pi pi-plus"
            size="small"
            @click="openAddDialog"
          />
        </div>

        <Message v-if="store.mutationStatus === 'error'" severity="error" :closable="false">
          {{ store.mutationError }}
        </Message>

        <Message v-if="store.listStatus === 'error'" severity="error" :closable="false">
          <span>{{ store.listError }}</span>
          <Button
            label="Retry"
            link
            size="small"
            class="ml-2"
            @click="loadInterviews(store.page)"
          />
        </Message>

        <div
          v-else-if="store.listStatus === 'loading' && store.items.length === 0"
          aria-live="polite"
          class="flex justify-center py-8"
        >
          <ProgressSpinner aria-label="Loading interviews" style="width: 2rem; height: 2rem" />
        </div>

        <div
          v-else-if="store.items.length === 0"
          class="rounded-card border border-dashed border-slate/30 p-6 text-center"
        >
          <p class="text-sm text-slate">
            No interviews scheduled yet. Add one to keep track of upcoming rounds.
          </p>
        </div>

        <ul v-else class="divide-y divide-slate/10">
          <li
            v-for="interview in store.items"
            :key="interview.id"
            class="flex items-start justify-between gap-4 py-3"
          >
            <div class="min-w-0">
              <div class="flex flex-wrap items-center gap-2">
                <p class="font-medium text-ink">{{ INTERVIEW_TYPE_LABELS[interview.type] }}</p>
                <Tag
                  :value="INTERVIEW_RESULT_LABELS[interview.result]"
                  :severity="interviewResultSeverity(interview.result)"
                />
              </div>
              <p class="mt-1 text-sm text-slate">{{ formatScheduledAt(interview.scheduled_at) }}</p>
              <p v-if="interview.duration_minutes" class="text-sm text-slate">
                {{ interview.duration_minutes }} min
              </p>
              <p v-if="interview.feedback" class="mt-1 text-sm text-slate">
                {{ interview.feedback }}
              </p>
            </div>
            <div class="flex shrink-0 gap-1">
              <Button
                v-tooltip.bottom="tooltip('Edit interview')"
                icon="pi pi-pencil"
                aria-label="Edit interview"
                link
                size="small"
                @click="openEditDialog(interview)"
              />
              <Button
                v-tooltip.bottom="tooltip('Delete interview')"
                icon="pi pi-trash"
                aria-label="Delete interview"
                text
                severity="danger"
                size="small"
                @click="confirmDelete(interview)"
              />
            </div>
          </li>
        </ul>

        <Paginator
          v-if="store.total > store.pageSize"
          :rows="store.pageSize"
          :total-records="store.total"
          :first="(store.page - 1) * store.pageSize"
          @page="onPageChange"
        />
      </div>
    </template>
  </Card>

  <InterviewFormDialog
    v-model:visible="dialogVisible"
    :application-id="props.applicationId"
    :interview="editingInterview"
  />
</template>
