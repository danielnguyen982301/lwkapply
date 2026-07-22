<script setup lang="ts">
import { DateTime } from 'luxon'
import { computed, onMounted, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { z } from 'zod'
import Button from 'primevue/button'
import Card from 'primevue/card'
import Message from 'primevue/message'
import ProgressSpinner from 'primevue/progressspinner'
import { useConfirm } from 'primevue/useconfirm'
import { useForm } from 'vee-validate'
import { toTypedSchema } from '@vee-validate/zod'

import { useApplicationsStore } from '@/stores/applications'
import { applicationStatusOptions } from '@/lib/application-ui'
import { formatJSDate } from '@/lib/date-utils'
import ContactsPanel from '@/components/applications/ContactsPanel.vue'
import InterviewsPanel from '@/components/applications/InterviewsPanel.vue'
import DocumentsPanel from '@/components/applications/DocumentsPanel.vue'
import {
  APPLICATION_STATUSES,
  type Application,
  type ApplicationCreatePayload,
  type ApplicationStatus,
} from '@/types/application'
import CustomInputText from '@/components/custom_form_fields/CustomInputText.vue'
import CustomSelect from '@/components/custom_form_fields/CustomSelect.vue'
import CustomInputNumber from '@/components/custom_form_fields/CustomInputNumber.vue'
import CustomDatePicker from '@/components/custom_form_fields/CustomDatePicker.vue'
import CustomTextarea from '@/components/custom_form_fields/CustomTextarea.vue'

const route = useRoute()
const router = useRouter()
const store = useApplicationsStore()
const confirm = useConfirm()

const statusOptions = applicationStatusOptions()

const isNew = computed(() => route.name === 'application-new')
const applicationId = computed(() => (isNew.value ? null : String(route.params.id)))

interface FormValues {
  company: string
  position: string
  location: string
  status: ApplicationStatus
  salary_min: number | null
  salary_max: number | null
  applied_date: Date | null
  job_url: string
  notes: string
}

function blankForm(): FormValues {
  return {
    company: '',
    position: '',
    location: '',
    status: 'saved',
    salary_min: null,
    salary_max: null,
    applied_date: null,
    job_url: '',
    notes: '',
  }
}

function populateForm(app: Application): FormValues {
  return {
    company: app.company,
    position: app.position,
    location: app.location ?? '',
    status: app.status,
    salary_min: app.salary_min,
    salary_max: app.salary_max,
    applied_date: app.applied_date ? DateTime.fromISO(app.applied_date).toJSDate() : null,
    job_url: app.job_url ?? '',
    notes: app.notes ?? '',
  }
}

const schema = toTypedSchema(
  z
    .object({
      company: z.string().trim().min(1, 'Company is required.'),
      position: z.string().trim().min(1, 'Position is required.'),
      location: z.string().trim().optional().default(''),
      status: z.enum(APPLICATION_STATUSES as [ApplicationStatus, ...ApplicationStatus[]]),
      salary_min: z.number().nullable(),
      salary_max: z.number().nullable(),
      applied_date: z.date().nullable(),
      job_url: z.string().trim().optional().default(''),
      notes: z.string().trim().optional().default(''),
    })
    .refine(
      (data) =>
        data.salary_min == null || data.salary_max == null || data.salary_min <= data.salary_max,
      { message: 'Maximum must be greater than or equal to the minimum.', path: ['salary_max'] },
    ),
)

const { values, handleSubmit, errors, meta, resetForm } = useForm<FormValues>({
  validationSchema: schema,
  initialValues: { ...blankForm() },
})

async function loadApplication(id: string) {
  try {
    const app = await store.fetchApplication(id)

    resetForm({ values: { ...populateForm(app) } })
  } catch {
    // store.currentError is already set and rendered below.
  }
}

function buildPayload(values: FormValues): ApplicationCreatePayload {
  return {
    company: values.company,
    position: values.position,
    location: values.location || null,
    status: values.status,
    salary_min: values.salary_min,
    salary_max: values.salary_max,
    applied_date: values.applied_date ? formatJSDate(values.applied_date, 'yyyy-MM-dd') : null,
    job_url: values.job_url || null,
    notes: values.notes || null,
  }
}

const onFormSubmit = handleSubmit(async (formValues) => {
  const payload = buildPayload(formValues)
  try {
    if (isNew.value) {
      const created = await store.createApplication(payload)
      router.push({ name: 'application-detail', params: { id: created.id } })
    } else if (applicationId.value) {
      await store.updateApplication(applicationId.value, payload)
      resetForm({ values: { ...formValues } })
    }
  } catch {
    // store.mutationError is already set and rendered below.
  }
})

function handleDelete() {
  if (!applicationId.value) return
  const company = values.company || 'this company'
  confirm.require({
    message: `Delete the application to ${company}? This can't be undone.`,
    header: 'Confirm deletion',
    icon: 'pi pi-exclamation-triangle',
    rejectLabel: 'Cancel',
    acceptLabel: 'Delete',
    rejectProps: { label: 'Cancel', severity: 'secondary', outlined: true },
    acceptProps: { label: 'Delete', severity: 'danger' },
    accept: async () => {
      try {
        await store.deleteApplication(applicationId.value!)
        router.push({ name: 'applications' })
      } catch {
        // store.mutationError is already set and rendered below.
      }
    },
  })
}

function handleCancel() {
  router.push({ name: 'applications' })
}

onMounted(() => {
  if (!isNew.value && applicationId.value) {
    loadApplication(applicationId.value)
  }
})

watch(
  () => route.params.id,
  (newId, oldId) => {
    if (!isNew.value && newId && newId !== oldId) {
      loadApplication(String(newId))
    }
  },
)
</script>

<template>
  <form class="mx-auto max-w-2xl space-y-4" @submit.prevent="onFormSubmit">
    <div class="flex items-center justify-between">
      <h1 class="font-display text-xl font-semibold text-ink">
        {{ isNew ? 'New Application' : values.company || 'Edit Application' }}
      </h1>
      <Button
        label="Back to list"
        icon="pi pi-arrow-left"
        as="RouterLink"
        :to="{ name: 'applications' }"
        link
        size="small"
      />
    </div>

    <Message v-if="!isNew && store.currentStatus === 'error'" severity="error" :closable="false">
      <span>{{ store.currentError }}</span>
      <Button
        label="Retry"
        type="button"
        link
        size="small"
        class="ml-2"
        @click="applicationId && loadApplication(applicationId)"
      />
    </Message>

    <div
      v-else-if="!isNew && store.currentStatus === 'loading' && !values.company"
      aria-live="polite"
      class="flex justify-center rounded-card border border-slate/10 bg-white p-10"
    >
      <ProgressSpinner aria-label="Loading application" />
    </div>

    <Card v-else>
      <template #content>
        <div class="space-y-5">
          <Message v-if="store.mutationStatus === 'error'" severity="error" :closable="false">
            {{ store.mutationError }}
          </Message>

          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <div class="flex flex-col gap-1">
              <label for="company" class="text-sm font-medium text-ink">Company *</label>
              <CustomInputText
                id="company"
                name="company"
                :invalid="!!errors.company"
                :aria-describedby="!!errors.company ? 'company-error' : undefined"
                class="w-full"
              />
            </div>

            <div class="flex flex-col gap-1">
              <label for="position" class="text-sm font-medium text-ink">Position *</label>
              <CustomInputText
                id="position"
                name="position"
                :invalid="!!errors.position"
                :aria-describedby="!!errors.position ? 'position-error' : undefined"
                class="w-full"
              />
            </div>

            <div class="flex flex-col gap-1">
              <label for="location" class="text-sm font-medium text-ink">Location</label>
              <CustomInputText id="location" name="location" class="w-full" />
            </div>

            <div class="flex flex-col gap-1">
              <label for="status" class="text-sm font-medium text-ink">Status</label>
              <CustomSelect
                name="status"
                input-id="status"
                :options="statusOptions"
                option-label="label"
                option-value="value"
                class="w-full"
              />
            </div>

            <div class="flex flex-col gap-1">
              <label for="salary_min" class="text-sm font-medium text-ink">Salary min</label>
              <CustomInputNumber
                name="salary_min"
                input-id="salary_min"
                :min="0"
                :invalid="!!errors.salary_min"
                :aria-describedby="!!errors.salary_min ? 'salary-min-error' : undefined"
                class="w-full"
              />
            </div>

            <div class="flex flex-col gap-1">
              <label for="salary_max" class="text-sm font-medium text-ink">Salary max</label>
              <CustomInputNumber
                name="salary_max"
                input-id="salary_max"
                :min="0"
                :invalid="!!errors.salary_max"
                :aria-describedby="!!errors.salary_max ? 'salary-max-error' : undefined"
                class="w-full"
              />
            </div>

            <div class="flex flex-col gap-1">
              <label for="applied_date" class="text-sm font-medium text-ink">Applied date</label>
              <CustomDatePicker
                name="applied_date"
                input-id="applied_date"
                date-format="yy-mm-dd"
                show-icon
                icon-display="input"
                class="w-full"
              />
            </div>

            <div class="flex flex-col gap-1">
              <label for="job_url" class="text-sm font-medium text-ink">Job posting URL</label>
              <CustomInputText
                id="job_url"
                name="jobUrl"
                type="url"
                placeholder="https://…"
                class="w-full"
              />
            </div>
          </div>

          <div class="flex flex-col gap-1">
            <label for="notes" class="text-sm font-medium text-ink">Notes</label>
            <CustomTextarea id="notes" name="notes" rows="4" class="w-full" />
          </div>

          <div class="flex items-center justify-between border-t border-slate/10 pt-4">
            <Button
              v-if="!isNew"
              label="Delete application"
              link
              severity="danger"
              type="button"
              @click="handleDelete"
            />

            <div class="ml-auto flex items-center gap-3">
              <Button
                label="Cancel"
                severity="secondary"
                outlined
                type="button"
                @click="handleCancel"
              />
              <Button
                type="submit"
                :label="
                  store.mutationStatus === 'loading'
                    ? 'Saving…'
                    : isNew
                      ? 'Create application'
                      : 'Save changes'
                "
                :loading="store.mutationStatus === 'loading'"
                :disabled="(!isNew && !meta.dirty) || store.mutationStatus === 'loading'"
              />
            </div>
          </div>
        </div>
      </template>
    </Card>

    <ContactsPanel v-if="!isNew && applicationId" :application-id="applicationId" />
    <InterviewsPanel v-if="!isNew && applicationId" :application-id="applicationId" />
    <DocumentsPanel v-if="!isNew && applicationId" :application-id="applicationId" />
  </form>
</template>
