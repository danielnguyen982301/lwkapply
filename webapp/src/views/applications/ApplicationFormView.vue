<script setup lang="ts">
import { computed, onMounted, reactive, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import Button from 'primevue/button'
import Card from 'primevue/card'
import DatePicker from 'primevue/datepicker'
import InputNumber from 'primevue/inputnumber'
import InputText from 'primevue/inputtext'
import Message from 'primevue/message'
import ProgressSpinner from 'primevue/progressspinner'
import Select from 'primevue/select'
import Textarea from 'primevue/textarea'
import { useConfirm } from 'primevue/useconfirm'

import { useApplicationsStore } from '@/stores/applications'
import { applicationStatusOptions } from '@/lib/application-ui'
import ContactsPanel from '@/components/applications/ContactsPanel.vue'
import {
  type Application,
  type ApplicationCreatePayload,
  type ApplicationStatus,
} from '@/types/application'

const route = useRoute()
const router = useRouter()
const store = useApplicationsStore()
const confirm = useConfirm()

const statusOptions = applicationStatusOptions()

const isNew = computed(() => route.name === 'application-new')
const applicationId = computed(() => (isNew.value ? null : String(route.params.id)))

interface FormState {
  company: string
  position: string
  location: string
  status: ApplicationStatus
  salary_min: string
  salary_max: string
  applied_date: string
  job_url: string
  notes: string
}

function blankForm(): FormState {
  return {
    company: '',
    position: '',
    location: '',
    status: 'saved',
    salary_min: '',
    salary_max: '',
    applied_date: '',
    job_url: '',
    notes: '',
  }
}

const form = reactive<FormState>(blankForm())
const validationErrors = ref<Partial<Record<keyof FormState, string>>>({})

const appliedDate = computed({
  get(): Date | null {
    if (!form.applied_date) return null
    return new Date(`${form.applied_date}T00:00:00`)
  },
  set(value: Date | null) {
    form.applied_date = value ? value.toISOString().slice(0, 10) : ''
  },
})

const salaryMin = computed({
  get(): number | null {
    return form.salary_min ? Number(form.salary_min) : null
  },
  set(value: number | null) {
    form.salary_min = value != null ? String(value) : ''
  },
})

const salaryMax = computed({
  get(): number | null {
    return form.salary_max ? Number(form.salary_max) : null
  },
  set(value: number | null) {
    form.salary_max = value != null ? String(value) : ''
  },
})

function populateForm(app: Application) {
  form.company = app.company
  form.position = app.position
  form.location = app.location ?? ''
  form.status = app.status
  form.salary_min = app.salary_min != null ? String(app.salary_min) : ''
  form.salary_max = app.salary_max != null ? String(app.salary_max) : ''
  form.applied_date = app.applied_date ?? ''
  form.job_url = app.job_url ?? ''
  form.notes = app.notes ?? ''
}

async function loadApplication(id: string) {
  try {
    const app = await store.fetchApplication(id)
    populateForm(app)
  } catch {
    // store.currentError is already set and rendered below.
  }
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

function validate(): boolean {
  const errors: Partial<Record<keyof FormState, string>> = {}
  if (!form.company.trim()) errors.company = 'Company is required.'
  if (!form.position.trim()) errors.position = 'Position is required.'

  const min = form.salary_min ? Number(form.salary_min) : null
  const max = form.salary_max ? Number(form.salary_max) : null
  if (min != null && Number.isNaN(min)) errors.salary_min = 'Enter a valid number.'
  if (max != null && Number.isNaN(max)) errors.salary_max = 'Enter a valid number.'
  if (min != null && max != null && !Number.isNaN(min) && !Number.isNaN(max) && min > max) {
    errors.salary_max = 'Maximum must be greater than or equal to the minimum.'
  }

  validationErrors.value = errors
  return Object.keys(errors).length === 0
}

function buildPayload(): ApplicationCreatePayload {
  return {
    company: form.company.trim(),
    position: form.position.trim(),
    location: form.location.trim() || null,
    status: form.status,
    salary_min: form.salary_min ? Number(form.salary_min) : null,
    salary_max: form.salary_max ? Number(form.salary_max) : null,
    applied_date: form.applied_date || null,
    job_url: form.job_url.trim() || null,
    notes: form.notes.trim() || null,
  }
}

async function handleSubmit() {
  if (!validate()) return
  const payload = buildPayload()
  try {
    if (isNew.value) {
      const created = await store.createApplication(payload)
      router.push({ name: 'application-detail', params: { id: created.id } })
    } else if (applicationId.value) {
      await store.updateApplication(applicationId.value, payload)
    }
  } catch {
    // store.mutationError is already set and rendered below.
  }
}

function handleDelete() {
  if (!applicationId.value) return
  confirm.require({
    message: `Delete the application to ${form.company || 'this company'}? This can't be undone.`,
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
</script>

<template>
  <div class="mx-auto max-w-2xl space-y-4">
    <div class="flex items-center justify-between">
      <h1 class="font-display text-xl font-semibold text-ink">
        {{ isNew ? 'New Application' : form.company || 'Edit Application' }}
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
        link
        size="small"
        class="ml-2"
        @click="applicationId && loadApplication(applicationId)"
      />
    </Message>

    <div
      v-else-if="!isNew && store.currentStatus === 'loading' && !form.company"
      aria-live="polite"
      class="flex justify-center rounded-card border border-slate/10 bg-white p-10"
    >
      <ProgressSpinner aria-label="Loading application" />
    </div>

    <Card v-else>
      <template #content>
        <form class="space-y-5" @submit.prevent="handleSubmit">
          <Message v-if="store.mutationStatus === 'error'" severity="error" :closable="false">
            {{ store.mutationError }}
          </Message>

          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <div class="flex flex-col gap-1">
              <label for="company" class="text-sm font-medium text-ink">Company *</label>
              <InputText
                id="company"
                v-model="form.company"
                :invalid="!!validationErrors.company"
                :aria-describedby="validationErrors.company ? 'company-error' : undefined"
                class="w-full"
              />
              <Message
                v-if="validationErrors.company"
                id="company-error"
                severity="error"
                variant="simple"
                size="small"
              >
                {{ validationErrors.company }}
              </Message>
            </div>

            <div class="flex flex-col gap-1">
              <label for="position" class="text-sm font-medium text-ink">Position *</label>
              <InputText
                id="position"
                v-model="form.position"
                :invalid="!!validationErrors.position"
                :aria-describedby="validationErrors.position ? 'position-error' : undefined"
                class="w-full"
              />
              <Message
                v-if="validationErrors.position"
                id="position-error"
                severity="error"
                variant="simple"
                size="small"
              >
                {{ validationErrors.position }}
              </Message>
            </div>

            <div class="flex flex-col gap-1">
              <label for="location" class="text-sm font-medium text-ink">Location</label>
              <InputText id="location" v-model="form.location" class="w-full" />
            </div>

            <div class="flex flex-col gap-1">
              <label for="status" class="text-sm font-medium text-ink">Status</label>
              <Select
                v-model="form.status"
                input-id="status"
                :options="statusOptions"
                option-label="label"
                option-value="value"
                class="w-full"
              />
            </div>

            <div class="flex flex-col gap-1">
              <label for="salary_min" class="text-sm font-medium text-ink">Salary min</label>
              <InputNumber
                v-model="salaryMin"
                input-id="salary_min"
                :min="0"
                :invalid="!!validationErrors.salary_min"
                :aria-describedby="validationErrors.salary_min ? 'salary-min-error' : undefined"
                class="w-full"
              />
              <Message
                v-if="validationErrors.salary_min"
                id="salary-min-error"
                severity="error"
                variant="simple"
                size="small"
              >
                {{ validationErrors.salary_min }}
              </Message>
            </div>

            <div class="flex flex-col gap-1">
              <label for="salary_max" class="text-sm font-medium text-ink">Salary max</label>
              <InputNumber
                v-model="salaryMax"
                input-id="salary_max"
                :min="0"
                :invalid="!!validationErrors.salary_max"
                :aria-describedby="validationErrors.salary_max ? 'salary-max-error' : undefined"
                class="w-full"
              />
              <Message
                v-if="validationErrors.salary_max"
                id="salary-max-error"
                severity="error"
                variant="simple"
                size="small"
              >
                {{ validationErrors.salary_max }}
              </Message>
            </div>

            <div class="flex flex-col gap-1">
              <label for="applied_date" class="text-sm font-medium text-ink">Applied date</label>
              <DatePicker
                v-model="appliedDate"
                input-id="applied_date"
                date-format="yy-mm-dd"
                show-icon
                icon-display="input"
                class="w-full"
              />
            </div>

            <div class="flex flex-col gap-1">
              <label for="job_url" class="text-sm font-medium text-ink">Job posting URL</label>
              <InputText
                id="job_url"
                v-model="form.job_url"
                type="url"
                placeholder="https://…"
                class="w-full"
              />
            </div>
          </div>

          <div class="flex flex-col gap-1">
            <label for="notes" class="text-sm font-medium text-ink">Notes</label>
            <Textarea id="notes" v-model="form.notes" rows="4" class="w-full" />
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
              />
            </div>
          </div>
        </form>
      </template>
    </Card>

    <ContactsPanel v-if="!isNew && applicationId" :application-id="applicationId" />
  </div>
</template>
