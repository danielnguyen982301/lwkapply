<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { useApplicationsStore } from '@/stores/applications'
import {
  APPLICATION_STATUSES,
  APPLICATION_STATUS_LABELS,
  type ApplicationStatus,
} from '@/types/application'

const store = useApplicationsStore()

// Local filter state seeded from the store so returning to this view (e.g.
// after opening a details page) keeps whatever filters were active.
const searchInput = ref(store.filters.search)
const statusFilter = ref<ApplicationStatus | ''>(store.filters.status ?? '')

const hasActiveFilters = computed(() => !!store.filters.status || !!store.filters.search)

let debounceTimer: ReturnType<typeof setTimeout> | undefined

function handleSearchInput() {
  if (debounceTimer) clearTimeout(debounceTimer)
  // Debounced so we're not firing a request on every keystroke — 350ms is
  // long enough to let someone finish typing a word, short enough to still
  // feel live.
  debounceTimer = setTimeout(() => {
    store.setFilters({ search: searchInput.value }).catch(() => {})
  }, 350)
}

function handleStatusChange() {
  store
    .setFilters({ status: statusFilter.value === '' ? null : statusFilter.value })
    .catch(() => {})
}

function clearFilters() {
  if (debounceTimer) clearTimeout(debounceTimer)
  searchInput.value = ''
  statusFilter.value = ''
  store.setFilters({ status: null, search: '' }).catch(() => {})
}

onBeforeUnmount(() => {
  if (debounceTimer) clearTimeout(debounceTimer)
})

onMounted(() => {
  // Errors are surfaced via store.listStatus/listError in the template —
  // swallow here just to avoid an unhandled-rejection console warning.
  store.fetchApplications().catch(() => {})
})

// Color alone never carries the meaning — each badge still renders its
// text label — this is just a visual accent for scanning the list quickly.
const statusStyles: Record<ApplicationStatus, string> = {
  saved: 'bg-slate/10 text-slate',
  applied: 'bg-ink/10 text-ink',
  phone_screen: 'bg-amber/15 text-amber',
  interviewing: 'bg-amber/25 text-ink',
  offer: 'bg-teal/15 text-teal-dark',
  accepted: 'bg-teal text-white',
  rejected: 'bg-coral/15 text-coral',
  withdrawn: 'bg-slate/10 text-slate-light',
}

function formatSalary(min: number | null, max: number | null): string {
  if (min == null && max == null) return '—'
  const fmt = (n: number) => `$${n.toLocaleString()}`
  if (min != null && max != null) return min === max ? fmt(min) : `${fmt(min)} – ${fmt(max)}`
  return fmt((min ?? max) as number)
}

function formatDate(value: string | null): string {
  if (!value) return '—'
  return new Date(value).toLocaleDateString(undefined, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  })
}

const rangeLabel = computed(() => {
  if (store.total === 0) return '0 of 0'
  const start = (store.page - 1) * store.pageSize + 1
  const end = Math.min(store.page * store.pageSize, store.total)
  return `${start}–${end} of ${store.total}`
})

async function goToPage(page: number) {
  await store.fetchApplications({ page }).catch(() => {})
}

async function handleDelete(id: string, company: string) {
  if (!confirm(`Delete the application to ${company}? This can't be undone.`)) return
  try {
    await store.deleteApplication(id)
  } catch {
    // store.mutationError is already set and rendered below; nothing
    // further to do here until we have a shared toast/notification pattern.
  }
}
</script>

<template>
  <div class="space-y-4">
    <div class="flex items-center justify-between">
      <h1 class="font-display text-xl font-semibold text-ink">Applications</h1>
      <button
        type="button"
        disabled
        title="Coming soon"
        class="cursor-not-allowed rounded-card bg-teal/40 px-4 py-2 text-sm font-medium text-white"
      >
        New Application
      </button>
    </div>

    <div class="flex flex-wrap items-center gap-3">
      <div class="min-w-[220px] flex-1">
        <label for="application-search" class="sr-only">Search by company or position</label>
        <input
          id="application-search"
          v-model="searchInput"
          type="search"
          placeholder="Search by company or position…"
          class="w-full rounded-card border border-slate/20 px-3 py-2 text-sm text-ink placeholder:text-slate-light focus:border-teal"
          @input="handleSearchInput"
        />
      </div>
      <div>
        <label for="status-filter" class="sr-only">Filter by status</label>
        <select
          id="status-filter"
          v-model="statusFilter"
          class="rounded-card border border-slate/20 px-3 py-2 text-sm text-ink focus:border-teal"
          @change="handleStatusChange"
        >
          <option value="">All statuses</option>
          <option v-for="status in APPLICATION_STATUSES" :key="status" :value="status">
            {{ APPLICATION_STATUS_LABELS[status] }}
          </option>
        </select>
      </div>
      <button
        v-if="hasActiveFilters"
        type="button"
        class="text-sm font-medium text-slate hover:text-ink"
        @click="clearFilters"
      >
        Clear filters
      </button>
    </div>

    <div
      v-if="store.mutationStatus === 'error'"
      role="alert"
      class="rounded-card border border-coral/30 bg-coral/5 p-3 text-sm text-coral"
    >
      {{ store.mutationError }}
    </div>

    <div
      v-if="store.listStatus === 'error'"
      role="alert"
      class="rounded-card border border-coral/30 bg-coral/5 p-4 text-sm text-coral"
    >
      {{ store.listError }}
      <button
        type="button"
        class="ml-2 underline"
        @click="store.fetchApplications().catch(() => {})"
      >
        Retry
      </button>
    </div>

    <div
      v-else-if="store.listStatus === 'loading' && store.items.length === 0"
      aria-live="polite"
      class="rounded-card border border-slate/10 bg-white p-10 text-center text-sm text-slate"
    >
      Loading applications…
    </div>

    <div
      v-else-if="store.items.length === 0"
      class="rounded-card border border-dashed border-slate/30 p-10 text-center"
    >
      <h2 class="font-display text-lg font-semibold text-ink">
        {{ hasActiveFilters ? 'No matching applications' : 'No applications yet' }}
      </h2>
      <p class="mx-auto mt-2 max-w-sm text-sm text-slate">
        <template v-if="hasActiveFilters"> Try a different search term or status filter. </template>
        <template v-else>
          Once you save or apply to a role, it'll show up here so you can track it through every
          stage of the process.
        </template>
      </p>
      <button
        v-if="hasActiveFilters"
        type="button"
        class="mt-4 text-sm font-medium text-teal hover:underline"
        @click="clearFilters"
      >
        Clear filters
      </button>
    </div>

    <div
      v-else
      class="overflow-hidden rounded-card border border-slate/10 bg-white transition-opacity"
      :class="{ 'pointer-events-none opacity-50': store.listStatus === 'loading' }"
      :aria-busy="store.listStatus === 'loading'"
    >
      <table class="w-full text-left text-sm">
        <caption class="sr-only">
          Your job applications
        </caption>
        <thead class="border-b border-slate/10 bg-paper text-xs uppercase tracking-wide text-slate">
          <tr>
            <th scope="col" class="px-4 py-3 font-medium">Company</th>
            <th scope="col" class="px-4 py-3 font-medium">Position</th>
            <th scope="col" class="px-4 py-3 font-medium">Location</th>
            <th scope="col" class="px-4 py-3 font-medium">Status</th>
            <th scope="col" class="px-4 py-3 font-medium">Salary</th>
            <th scope="col" class="px-4 py-3 font-medium">Applied</th>
            <th scope="col" class="px-4 py-3"><span class="sr-only">Actions</span></th>
          </tr>
        </thead>
        <tbody class="divide-y divide-slate/10">
          <tr v-for="app in store.items" :key="app.id" class="hover:bg-paper/60">
            <td class="px-4 py-3 font-medium text-ink">{{ app.company }}</td>
            <td class="px-4 py-3 text-slate">{{ app.position }}</td>
            <td class="px-4 py-3 text-slate">{{ app.location ?? '—' }}</td>
            <td class="px-4 py-3">
              <span
                class="inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium"
                :class="statusStyles[app.status]"
              >
                {{ APPLICATION_STATUS_LABELS[app.status] }}
              </span>
            </td>
            <td class="px-4 py-3 text-slate">{{ formatSalary(app.salary_min, app.salary_max) }}</td>
            <td class="px-4 py-3 text-slate">{{ formatDate(app.applied_date) }}</td>
            <td class="px-4 py-3 text-right">
              <button
                type="button"
                class="text-xs font-medium text-coral hover:underline"
                @click="handleDelete(app.id, app.company)"
              >
                Delete
              </button>
            </td>
          </tr>
        </tbody>
      </table>

      <div
        class="flex items-center justify-between border-t border-slate/10 px-4 py-3 text-sm text-slate"
      >
        <span>{{ rangeLabel }}</span>
        <div class="flex items-center gap-2">
          <button
            type="button"
            class="rounded-card border border-slate/20 px-3 py-1 disabled:opacity-40"
            :disabled="!store.hasPreviousPage || store.listStatus === 'loading'"
            @click="goToPage(store.page - 1)"
          >
            Previous
          </button>
          <span aria-live="polite">Page {{ store.page }} of {{ store.totalPages }}</span>
          <button
            type="button"
            class="rounded-card border border-slate/20 px-3 py-1 disabled:opacity-40"
            :disabled="!store.hasNextPage || store.listStatus === 'loading'"
            @click="goToPage(store.page + 1)"
          >
            Next
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
