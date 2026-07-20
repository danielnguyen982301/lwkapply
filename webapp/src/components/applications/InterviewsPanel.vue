<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, reactive, ref, watch } from 'vue'
import Button from 'primevue/button'
import Card from 'primevue/card'
import DatePicker from 'primevue/datepicker'
import Dialog from 'primevue/dialog'
import InputNumber from 'primevue/inputnumber'
import Message from 'primevue/message'
import Paginator from 'primevue/paginator'
import ProgressSpinner from 'primevue/progressspinner'
import Select from 'primevue/select'
import Tag from 'primevue/tag'
import Textarea from 'primevue/textarea'
import { useConfirm } from 'primevue/useconfirm'

import { useInterviewsStore } from '@/stores/interviews'
import {
  INTERVIEW_RESULT_LABELS,
  INTERVIEW_TYPE_LABELS,
  interviewResultOptions,
  interviewResultSeverity,
  interviewTypeOptions,
} from '@/lib/interview-ui'
import type {
  Interview,
  InterviewCreatePayload,
  InterviewResult,
  InterviewType,
} from '@/types/interview'

const props = defineProps<{ applicationId: string }>()

const store = useInterviewsStore()
const confirm = useConfirm()

const typeOptions = interviewTypeOptions()
const resultOptions = interviewResultOptions()

interface FormState {
  type: InterviewType
  scheduled_at: string
  duration_minutes: number | null
  feedback: string
  result: InterviewResult
}

function blankForm(): FormState {
  return {
    type: 'phone_screen',
    scheduled_at: '',
    duration_minutes: null,
    feedback: '',
    result: 'pending',
  }
}

const dialogVisible = ref(false)
const editingInterview = ref<Interview | null>(null)
const form = reactive<FormState>(blankForm())
const validationErrors = ref<Partial<Record<'scheduled_at', string>>>({})

const dialogTitle = computed(() =>
  editingInterview.value ? 'Edit interview' : 'Schedule interview',
)

const scheduledAt = computed({
  get(): Date | null {
    return form.scheduled_at ? new Date(form.scheduled_at) : null
  },
  set(value: Date | null) {
    form.scheduled_at = value ? value.toISOString() : ''
  },
})

function openAddDialog() {
  editingInterview.value = null
  Object.assign(form, blankForm())
  validationErrors.value = {}
  dialogVisible.value = true
}

function openEditDialog(interview: Interview) {
  editingInterview.value = interview
  form.type = interview.type
  form.scheduled_at = interview.scheduled_at
  form.duration_minutes = interview.duration_minutes
  form.feedback = interview.feedback ?? ''
  form.result = interview.result
  validationErrors.value = {}
  dialogVisible.value = true
}

function closeDialog() {
  dialogVisible.value = false
}

function validate(): boolean {
  const errors: Partial<Record<'scheduled_at', string>> = {}
  if (!form.scheduled_at) errors.scheduled_at = 'Date and time are required.'
  validationErrors.value = errors
  return Object.keys(errors).length === 0
}

function buildPayload(): InterviewCreatePayload {
  return {
    type: form.type,
    scheduled_at: form.scheduled_at,
    duration_minutes: form.duration_minutes,
    feedback: form.feedback.trim() || null,
    result: form.result,
  }
}

async function handleSubmit() {
  if (!validate()) return
  const payload = buildPayload()
  try {
    if (editingInterview.value) {
      await store.updateInterview(props.applicationId, editingInterview.value.id, payload)
    } else {
      await store.createInterview(props.applicationId, payload)
    }
    dialogVisible.value = false
  } catch {
    // store.mutationError is already set and rendered in the dialog below.
  }
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
  return new Date(iso).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' })
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
        <div class="flex items-center justify-between">
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
                icon="pi pi-pencil"
                aria-label="Edit interview"
                link
                size="small"
                @click="openEditDialog(interview)"
              />
              <Button
                icon="pi pi-trash"
                aria-label="Delete interview"
                link
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

  <Dialog
    v-model:visible="dialogVisible"
    :header="dialogTitle"
    modal
    class="w-full max-w-md"
    @hide="closeDialog"
  >
    <form class="space-y-4" @submit.prevent="handleSubmit">
      <Message v-if="store.mutationStatus === 'error'" severity="error" :closable="false">
        {{ store.mutationError }}
      </Message>

      <div class="flex flex-col gap-1">
        <label for="interview-type" class="text-sm font-medium text-ink">Type</label>
        <Select
          v-model="form.type"
          input-id="interview-type"
          :options="typeOptions"
          option-label="label"
          option-value="value"
          class="w-full"
        />
      </div>

      <div class="flex flex-col gap-1">
        <label for="interview-scheduled" class="text-sm font-medium text-ink">
          Date &amp; time *
        </label>
        <DatePicker
          v-model="scheduledAt"
          input-id="interview-scheduled"
          show-time
          hour-format="24"
          date-format="yy-mm-dd"
          show-icon
          icon-display="input"
          :invalid="!!validationErrors.scheduled_at"
          :aria-describedby="
            validationErrors.scheduled_at ? 'interview-scheduled-error' : undefined
          "
          class="w-full"
        />
        <Message
          v-if="validationErrors.scheduled_at"
          id="interview-scheduled-error"
          severity="error"
          variant="simple"
          size="small"
        >
          {{ validationErrors.scheduled_at }}
        </Message>
      </div>

      <div class="flex flex-col gap-1">
        <label for="interview-duration" class="text-sm font-medium text-ink">
          Duration (minutes)
        </label>
        <InputNumber
          v-model="form.duration_minutes"
          input-id="interview-duration"
          :min="1"
          :max="1440"
          class="w-full"
        />
      </div>

      <div class="flex flex-col gap-1">
        <label for="interview-result" class="text-sm font-medium text-ink">Result</label>
        <Select
          v-model="form.result"
          input-id="interview-result"
          :options="resultOptions"
          option-label="label"
          option-value="value"
          class="w-full"
        />
      </div>

      <div class="flex flex-col gap-1">
        <label for="interview-feedback" class="text-sm font-medium text-ink">Feedback</label>
        <Textarea id="interview-feedback" v-model="form.feedback" rows="3" class="w-full" />
      </div>

      <div class="flex items-center justify-end gap-3 border-t border-slate/10 pt-4">
        <Button label="Cancel" severity="secondary" outlined type="button" @click="closeDialog" />
        <Button
          type="submit"
          :label="
            store.mutationStatus === 'loading'
              ? 'Saving…'
              : editingInterview
                ? 'Save changes'
                : 'Schedule interview'
          "
          :loading="store.mutationStatus === 'loading'"
        />
      </div>
    </form>
  </Dialog>
</template>
