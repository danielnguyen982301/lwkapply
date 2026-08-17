<script setup lang="ts">
import { computed, watch } from 'vue'
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import Message from 'primevue/message'
import { toTypedSchema } from '@vee-validate/zod'
import z from 'zod'
import { useForm } from 'vee-validate'
import { DateTime } from 'luxon'

import { useInterviewsStore } from '@/stores/interviews'
import { interviewResultOptions, interviewTypeOptions } from '@/lib/interview-ui'
import {
  INTERVIEW_RESULTS,
  INTERVIEW_TYPES,
  type Interview,
  type InterviewCreatePayload,
  type InterviewResult,
  type InterviewType,
} from '@/types/interview'
import CustomSelect from '@/components/custom_form_fields/CustomSelect.vue'
import CustomDatePicker from '@/components/custom_form_fields/CustomDatePicker.vue'
import CustomInputNumber from '@/components/custom_form_fields/CustomInputNumber.vue'
import CustomTextarea from '@/components/custom_form_fields/CustomTextarea.vue'

interface FormValues {
  type: InterviewType
  scheduled_at: Date | null
  duration_minutes: number | null
  feedback: string
  result: InterviewResult
}

// Extracted out of InterviewsPanel.vue - add/edit is the same dialog,
// keyed off whether `interview` is set. createInterview()/
// updateInterview() (stores/interviews.ts) already refetch the panel's
// own list on success (scheduled_at can change sort order, so a
// client-side splice/patch can't be trusted) - nothing for the panel to
// sync afterward, no emit needed here.
const visible = defineModel<boolean>('visible', { default: false })
const props = defineProps<{ applicationId: string; interview: Interview | null }>()

const store = useInterviewsStore()

const typeOptions = interviewTypeOptions()
const resultOptions = interviewResultOptions()

function blankForm(): FormValues {
  return {
    type: 'phone_screen',
    scheduled_at: null,
    duration_minutes: null,
    feedback: '',
    result: 'pending',
  }
}

function populateForm(interview: Interview): FormValues {
  const { type, scheduled_at, duration_minutes, feedback, result } = interview
  return {
    type,
    scheduled_at: scheduled_at ? DateTime.fromISO(scheduled_at).toJSDate() : null,
    duration_minutes,
    feedback: feedback ?? '',
    result,
  }
}

const validationSchema = toTypedSchema(
  z.object({
    type: z.enum(INTERVIEW_TYPES as [InterviewType, ...InterviewType[]]),
    scheduled_at: z.date(),
    duration_minutes: z.number().nullable(),
    feedback: z.string().nullable(),
    result: z.enum(INTERVIEW_RESULTS as [InterviewResult, ...InterviewResult[]]),
  }),
)

const { errors, handleSubmit, meta, resetForm } = useForm<FormValues>({
  validationSchema,
  initialValues: { ...blankForm() },
})

const dialogTitle = computed(() => (props.interview ? 'Edit interview' : 'Schedule interview'))

// Keyed off `visible`, not `props.interview` - see ContactFormDialog.vue's
// matching watch for why: PrimeVue's Dialog unmounts its slot content
// while hidden, so the Custom*/useField() fields reset on every reopen
// regardless of what this component does. Watching `props.interview`
// missed the reset entirely on a same-interview reopen (unchanged prop
// reference) and wasn't reliably ordered before the remount even when it
// did fire. `visible` fires on every open and (Vue's default pre-flush
// watch timing) runs before the remount, so the fields always pick up
// the right values.
watch(
  visible,
  (isVisible) => {
    if (isVisible) {
      resetForm({ values: props.interview ? populateForm(props.interview) : blankForm() })
    }
  },
  { immediate: true },
)

function buildPayload(formValues: FormValues): InterviewCreatePayload {
  const { type, scheduled_at, duration_minutes, feedback, result } = formValues
  return {
    type,
    scheduled_at: scheduled_at ? scheduled_at.toISOString() : '',
    duration_minutes,
    feedback: feedback.trim() || null,
    result,
  }
}

const onFormSubmit = handleSubmit(async (formValues) => {
  const payload = buildPayload(formValues)
  try {
    if (props.interview) {
      await store.updateInterview(props.applicationId, props.interview.id, payload)
    } else {
      await store.createInterview(props.applicationId, payload)
    }
    visible.value = false
  } catch {
    // store.mutationError is already set and rendered below.
  }
})

function closeDialog() {
  visible.value = false
}
</script>

<template>
  <Dialog
    v-model:visible="visible"
    :header="dialogTitle"
    modal
    dismissable-mask
    class="w-full max-w-md"
    @hide="closeDialog"
  >
    <form class="space-y-4" @submit.prevent="onFormSubmit">
      <Message v-if="store.mutationStatus === 'error'" severity="error" :closable="false">
        {{ store.mutationError }}
      </Message>

      <div class="flex flex-col gap-1">
        <label for="interview-type" class="text-sm font-medium text-ink">Type</label>
        <CustomSelect
          name="type"
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
        <CustomDatePicker
          name="scheduled_at"
          input-id="interview-scheduled"
          show-time
          hour-format="24"
          date-format="yy-mm-dd"
          show-icon
          icon-display="input"
          :invalid="!!errors.scheduled_at"
          :aria-describedby="!!errors.scheduled_at ? 'interview-scheduled-error' : undefined"
          class="w-full"
        />
      </div>

      <div class="flex flex-col gap-1">
        <label for="interview-duration" class="text-sm font-medium text-ink">
          Duration (minutes)
        </label>
        <CustomInputNumber
          name="duration_minutes"
          input-id="interview-duration"
          :min="1"
          :max="1440"
          class="w-full"
        />
      </div>

      <div class="flex flex-col gap-1">
        <label for="interview-result" class="text-sm font-medium text-ink">Result</label>
        <CustomSelect
          name="result"
          input-id="interview-result"
          :options="resultOptions"
          option-label="label"
          option-value="value"
          class="w-full"
        />
      </div>

      <div class="flex flex-col gap-1">
        <label for="interview-feedback" class="text-sm font-medium text-ink">Feedback</label>
        <CustomTextarea id="interview-feedback" name="feedback" rows="3" class="w-full" />
      </div>

      <div class="flex items-center justify-end gap-3 border-t border-slate/10 pt-4">
        <Button label="Cancel" severity="secondary" outlined type="button" @click="closeDialog" />
        <Button
          type="submit"
          :label="
            store.mutationStatus === 'loading'
              ? 'Saving…'
              : interview
                ? 'Save changes'
                : 'Schedule interview'
          "
          :loading="store.mutationStatus === 'loading'"
          :disabled="(!!interview && !meta.dirty) || store.mutationStatus === 'loading'"
        />
      </div>
    </form>
  </Dialog>
</template>
