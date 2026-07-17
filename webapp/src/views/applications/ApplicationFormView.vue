<script setup lang="ts">
import { computed, onMounted, reactive, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useApplicationsStore } from '@/stores/applications'
import {
  APPLICATION_STATUSES,
  APPLICATION_STATUS_LABELS,
  type Application,
  type ApplicationCreatePayload,
  type ApplicationStatus,
} from '@/types/application'

const route = useRoute()
const router = useRouter()
const store = useApplicationsStore()

// One component, two modes — determined by which route matched, not by
// presence/absence of an id prop, since `/applications/new` and
// `/applications/:id` are registered as distinct named routes even though
// they share this component.
const isNew = computed(() => route.name === 'application-new')
const applicationId = computed(() => (isNew.value ? null : String(route.params.id)))

interface FormState {
  company: string
  position: string
  location: string
  status: ApplicationStatus
  // Kept as strings for the inputs; parsed to number|null in buildPayload().
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

// Handles navigating directly from one application's detail page to
// another's (e.g. Kanban card -> card) without an unmount in between,
// since both routes resolve to this same component instance.
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

async function handleDelete() {
  if (!applicationId.value) return
  if (
    !confirm(`Delete the application to ${form.company || 'this company'}? This can't be undone.`)
  )
    return
  try {
    await store.deleteApplication(applicationId.value)
    router.push({ name: 'applications' })
  } catch {
    // store.mutationError is already set and rendered below.
  }
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
      <RouterLink
        :to="{ name: 'applications' }"
        class="text-sm font-medium text-slate hover:text-ink"
      >
        &larr; Back to list
      </RouterLink>
    </div>

    <div
      v-if="!isNew && store.currentStatus === 'error'"
      role="alert"
      class="rounded-card border border-coral/30 bg-coral/5 p-4 text-sm text-coral"
    >
      {{ store.currentError }}
      <button
        type="button"
        class="ml-2 underline"
        @click="applicationId && loadApplication(applicationId)"
      >
        Retry
      </button>
    </div>

    <div
      v-else-if="!isNew && store.currentStatus === 'loading' && !form.company"
      aria-live="polite"
      class="rounded-card border border-slate/10 bg-white p-10 text-center text-sm text-slate"
    >
      Loading application…
    </div>

    <form
      v-else
      class="space-y-5 rounded-card border border-slate/10 bg-white p-6"
      @submit.prevent="handleSubmit"
    >
      <div
        v-if="store.mutationStatus === 'error'"
        role="alert"
        class="rounded-card border border-coral/30 bg-coral/5 p-3 text-sm text-coral"
      >
        {{ store.mutationError }}
      </div>

      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div>
          <label for="company" class="mb-1 block text-sm font-medium text-ink">Company *</label>
          <input
            id="company"
            v-model="form.company"
            type="text"
            required
            :aria-invalid="!!validationErrors.company"
            :aria-describedby="validationErrors.company ? 'company-error' : undefined"
            class="w-full rounded-card border px-3 py-2 text-sm focus:border-teal"
            :class="validationErrors.company ? 'border-coral' : 'border-slate/20'"
          />
          <p v-if="validationErrors.company" id="company-error" class="mt-1 text-xs text-coral">
            {{ validationErrors.company }}
          </p>
        </div>

        <div>
          <label for="position" class="mb-1 block text-sm font-medium text-ink">Position *</label>
          <input
            id="position"
            v-model="form.position"
            type="text"
            required
            :aria-invalid="!!validationErrors.position"
            :aria-describedby="validationErrors.position ? 'position-error' : undefined"
            class="w-full rounded-card border px-3 py-2 text-sm focus:border-teal"
            :class="validationErrors.position ? 'border-coral' : 'border-slate/20'"
          />
          <p v-if="validationErrors.position" id="position-error" class="mt-1 text-xs text-coral">
            {{ validationErrors.position }}
          </p>
        </div>

        <div>
          <label for="location" class="mb-1 block text-sm font-medium text-ink">Location</label>
          <input
            id="location"
            v-model="form.location"
            type="text"
            class="w-full rounded-card border border-slate/20 px-3 py-2 text-sm focus:border-teal"
          />
        </div>

        <div>
          <label for="status" class="mb-1 block text-sm font-medium text-ink">Status</label>
          <select
            id="status"
            v-model="form.status"
            class="w-full rounded-card border border-slate/20 px-3 py-2 text-sm focus:border-teal"
          >
            <option v-for="status in APPLICATION_STATUSES" :key="status" :value="status">
              {{ APPLICATION_STATUS_LABELS[status] }}
            </option>
          </select>
        </div>

        <div>
          <label for="salary_min" class="mb-1 block text-sm font-medium text-ink">Salary min</label>
          <input
            id="salary_min"
            v-model="form.salary_min"
            type="number"
            min="0"
            :aria-invalid="!!validationErrors.salary_min"
            :aria-describedby="validationErrors.salary_min ? 'salary-min-error' : undefined"
            class="w-full rounded-card border px-3 py-2 text-sm focus:border-teal"
            :class="validationErrors.salary_min ? 'border-coral' : 'border-slate/20'"
          />
          <p
            v-if="validationErrors.salary_min"
            id="salary-min-error"
            class="mt-1 text-xs text-coral"
          >
            {{ validationErrors.salary_min }}
          </p>
        </div>

        <div>
          <label for="salary_max" class="mb-1 block text-sm font-medium text-ink">Salary max</label>
          <input
            id="salary_max"
            v-model="form.salary_max"
            type="number"
            min="0"
            :aria-invalid="!!validationErrors.salary_max"
            :aria-describedby="validationErrors.salary_max ? 'salary-max-error' : undefined"
            class="w-full rounded-card border px-3 py-2 text-sm focus:border-teal"
            :class="validationErrors.salary_max ? 'border-coral' : 'border-slate/20'"
          />
          <p
            v-if="validationErrors.salary_max"
            id="salary-max-error"
            class="mt-1 text-xs text-coral"
          >
            {{ validationErrors.salary_max }}
          </p>
        </div>

        <div>
          <label for="applied_date" class="mb-1 block text-sm font-medium text-ink"
            >Applied date</label
          >
          <input
            id="applied_date"
            v-model="form.applied_date"
            type="date"
            class="w-full rounded-card border border-slate/20 px-3 py-2 text-sm focus:border-teal"
          />
        </div>

        <div>
          <label for="job_url" class="mb-1 block text-sm font-medium text-ink"
            >Job posting URL</label
          >
          <input
            id="job_url"
            v-model="form.job_url"
            type="url"
            placeholder="https://…"
            class="w-full rounded-card border border-slate/20 px-3 py-2 text-sm focus:border-teal"
          />
        </div>
      </div>

      <div>
        <label for="notes" class="mb-1 block text-sm font-medium text-ink">Notes</label>
        <textarea
          id="notes"
          v-model="form.notes"
          rows="4"
          class="w-full rounded-card border border-slate/20 px-3 py-2 text-sm focus:border-teal"
        ></textarea>
      </div>

      <div class="flex items-center justify-between border-t border-slate/10 pt-4">
        <button
          v-if="!isNew"
          type="button"
          class="text-sm font-medium text-coral hover:underline"
          @click="handleDelete"
        >
          Delete application
        </button>
        <span v-else />

        <div class="flex items-center gap-3">
          <button
            type="button"
            class="rounded-card border border-slate/20 px-4 py-2 text-sm font-medium text-slate hover:text-ink"
            @click="handleCancel"
          >
            Cancel
          </button>
          <button
            type="submit"
            :disabled="store.mutationStatus === 'loading'"
            class="rounded-card bg-teal px-4 py-2 text-sm font-medium text-white hover:bg-teal-dark disabled:opacity-60"
          >
            {{
              store.mutationStatus === 'loading'
                ? 'Saving…'
                : isNew
                  ? 'Create application'
                  : 'Save changes'
            }}
          </button>
        </div>
      </div>
    </form>
  </div>
</template>
