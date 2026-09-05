<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { RouterLink } from 'vue-router'
import Button from 'primevue/button'
import Column from 'primevue/column'
import DataTable from 'primevue/datatable'
import IconField from 'primevue/iconfield'
import InputIcon from 'primevue/inputicon'
import InputText from 'primevue/inputtext'
import Message from 'primevue/message'
import Paginator from 'primevue/paginator'
import ProgressSpinner from 'primevue/progressspinner'
import Select from 'primevue/select'
import { useConfirm } from 'primevue/useconfirm'

import { useApplicationsStore } from '@/stores/applications'
import ApplicationStatusTag from '@/components/applications/ApplicationStatusTag.vue'
import ViewTabs from '@/components/applications/ViewTabs.vue'
import TruncatedText from '@/components/common/TruncatedText.vue'
import { applicationStatusFilterOptions } from '@/lib/application-ui'
import { tooltip } from '@/lib/tooltip'
import { useApplicationRowClick } from '@/lib/row-click'
import type { Application, ApplicationStatus } from '@/types/application'

const store = useApplicationsStore()
const confirm = useConfirm()

const statusFilterOptions = applicationStatusFilterOptions()

// Local filter state seeded from the store so returning to this view (e.g.
// after opening a details page) keeps whatever filters were active.
const searchInput = ref(store.filters.search)
const statusFilter = ref<ApplicationStatus | null>(store.filters.status ?? null)

const hasActiveFilters = computed(() => !!store.filters.status || !!store.filters.search)

let debounceTimer: ReturnType<typeof setTimeout> | undefined

function handleSearchInput() {
  if (debounceTimer) clearTimeout(debounceTimer)
  debounceTimer = setTimeout(() => {
    store.setFilters({ search: searchInput.value }).catch(() => {})
  }, 350)
}

function handleStatusChange() {
  store.setFilters({ status: statusFilter.value }).catch(() => {})
}

function clearFilters() {
  if (debounceTimer) clearTimeout(debounceTimer)
  searchInput.value = ''
  statusFilter.value = null
  store.setFilters({ status: null, search: '' }).catch(() => {})
}

onBeforeUnmount(() => {
  if (debounceTimer) clearTimeout(debounceTimer)
})

onMounted(() => {
  store.fetchApplications().catch(() => {})
})

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

const paginatorFirst = computed(() => (store.page - 1) * store.pageSize)

async function onPageChange(event: { first: number; rows: number }) {
  const page = Math.floor(event.first / event.rows) + 1
  await store.fetchApplications({ page }).catch(() => {})
}

const handleRowClick = useApplicationRowClick<Application>((app) => app.id)

function confirmDelete(app: Application) {
  confirm.require({
    message: `Delete the application to ${app.company}? This can't be undone.`,
    header: 'Confirm deletion',
    icon: 'pi pi-exclamation-triangle',
    rejectLabel: 'Cancel',
    acceptLabel: 'Delete',
    rejectProps: { label: 'Cancel', severity: 'secondary', outlined: true },
    acceptProps: { label: 'Delete', severity: 'danger' },
    accept: () => {
      store.deleteApplication(app.id).catch(() => {})
    },
  })
}
</script>

<template>
  <div class="space-y-4">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <h1 class="font-display text-xl font-semibold text-ink">Applications</h1>
      <Button label="New Application" as="RouterLink" :to="{ name: 'application-new' }" />
    </div>

    <ViewTabs />

    <div class="flex flex-wrap items-center gap-3">
      <IconField class="min-w-[220px] flex-1">
        <InputIcon class="pi pi-search" />
        <InputText
          v-model="searchInput"
          type="search"
          placeholder="Search by company, position, or application name…"
          class="w-full"
          aria-label="Search by company, position, or application name"
          @input="handleSearchInput"
        />
      </IconField>
      <Select
        v-model="statusFilter"
        :options="statusFilterOptions"
        option-label="label"
        option-value="value"
        placeholder="All statuses"
        aria-label="Filter by status"
        class="min-w-[180px]"
        @change="handleStatusChange"
      />
      <Button
        v-if="hasActiveFilters"
        label="Clear filters"
        link
        size="small"
        @click="clearFilters"
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
        @click="store.fetchApplications().catch(() => {})"
      />
    </Message>

    <div
      v-else-if="store.listStatus === 'loading' && store.items.length === 0"
      aria-live="polite"
      class="flex justify-center rounded-card border border-slate/10 bg-surface p-10"
    >
      <ProgressSpinner aria-label="Loading applications" />
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
      <Button
        v-if="hasActiveFilters"
        label="Clear filters"
        link
        class="mt-4"
        @click="clearFilters"
      />
    </div>

    <div v-else class="space-y-0">
      <!-- Wide (8-column) table doesn't reflow on narrow screens - it
           scrolls horizontally within this wrapper instead of squeezing
           columns unreadably thin or breaking the page layout. -->
      <div class="overflow-x-auto">
        <DataTable
          :value="store.items"
          :loading="store.listStatus === 'loading'"
          size="small"
          striped-rows
          selection-mode="single"
          aria-label="Your job applications"
          @row-click="handleRowClick"
        >
          <Column field="application_name" header="Application name">
            <template #body="{ data }: { data: Application }">
              <TruncatedText :text="data.application_name" max-width="12rem" />
            </template>
          </Column>
          <Column field="company" header="Company">
            <template #body="{ data }: { data: Application }">
              <RouterLink
                :to="{ name: 'application-detail', params: { id: data.id } }"
                class="block max-w-[12rem] truncate font-medium text-ink hover:underline"
                :title="data.company"
              >
                {{ data.company }}
              </RouterLink>
            </template>
          </Column>
          <Column field="position" header="Position">
            <template #body="{ data }: { data: Application }">
              <TruncatedText :text="data.position" max-width="12rem" />
            </template>
          </Column>
          <Column field="location" header="Location">
            <template #body="{ data }: { data: Application }">
              <TruncatedText :text="data.location" max-width="10rem" />
            </template>
          </Column>
          <Column field="status" header="Status">
            <template #body="{ data }: { data: Application }">
              <ApplicationStatusTag :status="data.status" />
            </template>
          </Column>
          <Column header="Salary">
            <template #body="{ data }: { data: Application }">
              {{ formatSalary(data.salary_min, data.salary_max) }}
            </template>
          </Column>
          <Column header="Applied">
            <template #body="{ data }: { data: Application }">
              {{ formatDate(data.applied_date) }}
            </template>
          </Column>
          <Column header-class="text-right" body-class="text-right">
            <template #body="{ data }: { data: Application }">
              <div class="flex justify-end gap-1">
                <Button
                  v-tooltip.bottom="tooltip('Edit application')"
                  icon="pi pi-pencil"
                  aria-label="Edit application"
                  as="RouterLink"
                  :to="{ name: 'application-detail', params: { id: data.id } }"
                  link
                  size="small"
                />
                <Button
                  v-tooltip.bottom="tooltip('Delete application')"
                  icon="pi pi-trash"
                  aria-label="Delete application"
                  text
                  severity="danger"
                  size="small"
                  @click="confirmDelete(data)"
                />
              </div>
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
        class="border-x border-b border-slate/10 bg-surface"
        @page="onPageChange"
      />
    </div>
  </div>
</template>
