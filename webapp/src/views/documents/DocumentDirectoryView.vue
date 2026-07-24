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
import Tag from 'primevue/tag'

import { useDocumentDirectoryStore } from '@/stores/documentDirectory'
import ApplicationStatusTag from '@/components/applications/ApplicationStatusTag.vue'
import {
  DOCUMENT_TYPE_LABELS,
  documentTypeFilterOptions,
  documentTypeSeverity,
} from '@/lib/document-ui'
import type { DocumentType, DocumentWithApplication } from '@/types/document'

const store = useDocumentDirectoryStore()

const typeFilterOptions = documentTypeFilterOptions()

// Debounced text search, same shape as ContactDirectoryView.vue's search
// box — the store itself stays synchronous (fetch-on-call), debouncing is
// purely a view-level concern so it doesn't leak into every other caller
// of fetchDocuments().
const searchInput = ref(store.search)
let debounceTimer: ReturnType<typeof setTimeout> | undefined

function handleSearchInput() {
  if (debounceTimer) clearTimeout(debounceTimer)
  debounceTimer = setTimeout(() => {
    store.setSearch(searchInput.value).catch(() => {})
  }, 300)
}

onBeforeUnmount(() => {
  if (debounceTimer) clearTimeout(debounceTimer)
})

async function handleFileTypeFilterChange(value: DocumentType | null) {
  await store.setFileTypeFilter(value).catch(() => {})
}

const hasActiveFilter = computed(() => store.search !== '' || store.fileType !== null)

function clearFilters() {
  searchInput.value = ''
  if (debounceTimer) clearTimeout(debounceTimer)
  store.fetchDocuments({ search: null, file_type: null, page: 1 }).catch(() => {})
}

onMounted(() => {
  store.fetchDocuments().catch(() => {})
})

const paginatorFirst = computed(() => (store.page - 1) * store.pageSize)

async function onPageChange(event: { first: number; rows: number }) {
  const page = Math.floor(event.first / event.rows) + 1
  await store.fetchDocuments({ page }).catch(() => {})
}

const dateFormatter = new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' })

function formatUploadedAt(value: string): string {
  return dateFormatter.format(new Date(value))
}
</script>

<template>
  <div class="space-y-4">
    <div class="flex items-center justify-between">
      <h1 class="font-display text-xl font-semibold text-ink">Documents</h1>
    </div>

    <p class="max-w-2xl text-sm text-slate">
      Every resume, cover letter, and attachment across all your applications, in one place. To
      upload, replace, or delete a document, open the application it belongs to.
    </p>

    <div class="flex flex-wrap items-center gap-3">
      <IconField>
        <InputIcon class="pi pi-search" />
        <InputText
          v-model="searchInput"
          type="search"
          placeholder="Search by file name or company"
          class="w-72"
          aria-label="Search documents"
          @input="handleSearchInput"
        />
      </IconField>
      <Select
        :model-value="store.fileType"
        :options="typeFilterOptions"
        option-label="label"
        option-value="value"
        class="w-48"
        aria-label="Filter documents by type"
        @update:model-value="handleFileTypeFilterChange"
      />
    </div>

    <Message v-if="store.listStatus === 'error'" severity="error" :closable="false">
      <span>{{ store.listError }}</span>
      <Button
        label="Retry"
        link
        size="small"
        class="ml-2"
        @click="store.fetchDocuments().catch(() => {})"
      />
    </Message>

    <div
      v-else-if="store.listStatus === 'loading' && store.items.length === 0"
      aria-live="polite"
      class="flex justify-center rounded-card border border-slate/10 bg-white p-10"
    >
      <ProgressSpinner aria-label="Loading documents" />
    </div>

    <div
      v-else-if="store.items.length === 0"
      class="rounded-card border border-dashed border-slate/30 p-10 text-center"
    >
      <h2 class="font-display text-lg font-semibold text-ink">
        {{ hasActiveFilter ? 'No matching documents' : 'No documents yet' }}
      </h2>
      <p class="mx-auto mt-2 max-w-sm text-sm text-slate">
        <template v-if="hasActiveFilter">Try a different search term or type filter.</template>
        <template v-else>
          Upload a resume or cover letter from within an application's detail page and it'll show up
          here.
        </template>
      </p>
      <Button
        v-if="hasActiveFilter"
        label="Clear filters"
        link
        class="mt-4"
        @click="clearFilters"
      />
    </div>

    <div v-else class="space-y-0">
      <DataTable
        :value="store.items"
        :loading="store.listStatus === 'loading'"
        size="small"
        striped-rows
        aria-label="All your documents"
      >
        <Column header="File name">
          <template #body="{ data }: { data: DocumentWithApplication }">
            <span class="font-medium text-ink">{{ data.file_name }}</span>
          </template>
        </Column>
        <Column header="Type">
          <template #body="{ data }: { data: DocumentWithApplication }">
            <Tag
              :value="DOCUMENT_TYPE_LABELS[data.file_type]"
              :severity="documentTypeSeverity(data.file_type)"
            />
          </template>
        </Column>
        <Column header="Company">
          <template #body="{ data }: { data: DocumentWithApplication }">
            <RouterLink
              :to="{ name: 'application-detail', params: { id: data.application.id } }"
              class="text-ink hover:underline"
            >
              {{ data.application.company }}
            </RouterLink>
          </template>
        </Column>
        <Column header="Position">
          <template #body="{ data }: { data: DocumentWithApplication }">
            {{ data.application.position }}
          </template>
        </Column>
        <Column header="Status">
          <template #body="{ data }: { data: DocumentWithApplication }">
            <ApplicationStatusTag :status="data.application.status" />
          </template>
        </Column>
        <Column header="Uploaded">
          <template #body="{ data }: { data: DocumentWithApplication }">
            {{ formatUploadedAt(data.created_at) }}
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
