<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
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
import { useConfirm } from 'primevue/useconfirm'

import { useDocumentsStore } from '@/stores/documents'
import TruncatedText from '@/components/common/TruncatedText.vue'
import DocumentUploadDialog from '@/components/documents/DocumentUploadDialog.vue'
import DocumentEditDialog from '@/components/documents/DocumentEditDialog.vue'
import DocumentAnalysisModal from '@/components/ai/DocumentAnalysisModal.vue'
import {
  DOCUMENT_TYPE_LABELS,
  documentTypeFilterOptions,
  documentTypeSeverity,
} from '@/lib/document-ui'
import { tooltip } from '@/lib/tooltip'
import { formatDateTime } from '@/lib/date-utils'
import type { Document, DocumentType } from '@/types/document'

// The user's whole document library - a document is a top-level, standalone
// resource now (see stores/documents.ts / BACKEND_SUMMARY.md's "A note on
// Document / ApplicationDocument"), so upload/edit/delete all live here
// rather than only on an application's Documents panel. Attaching an
// already-uploaded document to a specific application still happens from
// that application's detail page (components/applications/DocumentsPanel.vue).
const store = useDocumentsStore()
const confirm = useConfirm()

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

function loadDocuments(page = 1) {
  store.fetchDocuments({ page }).catch(() => {})
}

onMounted(() => {
  loadDocuments()
})

const paginatorFirst = computed(() => (store.page - 1) * store.pageSize)

async function onPageChange(event: { first: number; rows: number }) {
  await store.fetchDocuments({ page: Math.floor(event.first / event.rows) + 1 }).catch(() => {})
}

// Date + time, not just date - two documents can share an upload date, and
// the time is what actually tells them apart (matches the same "Uploaded"
// timestamp shown in ResumeDocumentPicker.vue/DocumentAttachDialog.vue's
// suggestion lists).
const formatUploadedAt = formatDateTime

// --- Upload / edit dialogs ---------------------------------------------
// Both extracted into components/documents/ so DocumentsPanel.vue
// (application-scoped) can reuse the same upload/edit UX - see those
// files for why the library store owns both, regardless of which view
// opened the dialog.
const uploadDialogVisible = ref(false)
const editDialogVisible = ref(false)
const editingDocument = ref<Document | null>(null)

function openEditDialog(doc: Document) {
  editingDocument.value = doc
  editDialogVisible.value = true
}

// --- AI analysis modal ---------------------------------------------------
// Same trigger as components/applications/DocumentsPanel.vue's own
// "View AI analysis" button - see components/ai/DocumentAnalysisModal.vue
// for why this is a separate component rather than reusing
// ResumeAnalysisModal.vue directly (no single application/job_url here).
const analysisModalVisible = ref(false)
const analysisModalDocumentId = ref<string | null>(null)

function openAnalysisModal(doc: Document) {
  analysisModalDocumentId.value = doc.id
  analysisModalVisible.value = true
}

// --- Delete / download -------------------------------------------------
function confirmDelete(doc: Document) {
  confirm.require({
    message: `Permanently delete "${doc.file_name}"? This removes it from every application it's attached to and permanently deletes any AI analyses and ATS scores run against it, and can't be undone.`,
    header: 'Confirm deletion',
    icon: 'pi pi-exclamation-triangle',
    rejectLabel: 'Cancel',
    acceptLabel: 'Delete',
    rejectProps: { label: 'Cancel', severity: 'secondary', outlined: true },
    acceptProps: { label: 'Delete', severity: 'danger' },
    accept: () => {
      store.deleteDocument(doc.id).catch(() => {})
    },
  })
}

function handleDownload(doc: Document) {
  store.downloadDocument(doc.id).catch(() => {})
}
</script>

<template>
  <div class="space-y-4">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <h1 class="font-display text-xl font-semibold text-ink">Documents</h1>
      <Button
        label="Upload document"
        icon="pi pi-upload"
        size="small"
        @click="uploadDialogVisible = true"
      />
    </div>

    <p class="max-w-2xl text-sm text-slate">
      Your resume, cover letter, and other file library. Attach a document to as many applications
      as you like from that application's detail page.
    </p>

    <div class="flex flex-wrap items-center gap-3">
      <IconField>
        <InputIcon class="pi pi-search" />
        <InputText
          v-model="searchInput"
          type="search"
          placeholder="Search by file name"
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
      <Button label="Retry" link size="small" class="ml-2" @click="loadDocuments(store.page)" />
    </Message>

    <Message
      v-if="store.downloadError"
      severity="error"
      closable
      @close="store.downloadError = null"
    >
      {{ store.downloadError }}
    </Message>

    <div
      v-else-if="store.listStatus === 'loading' && store.items.length === 0"
      aria-live="polite"
      class="flex justify-center rounded-card border border-slate/10 bg-surface p-10"
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
        <template v-else>Upload a resume, cover letter, or other file to get started.</template>
      </p>
      <Button
        v-if="hasActiveFilter"
        label="Clear filters"
        link
        class="mt-4"
        @click="clearFilters"
      />
      <Button
        v-else
        label="Upload document"
        link
        class="mt-4"
        @click="uploadDialogVisible = true"
      />
    </div>

    <div v-else class="space-y-0">
      <div class="overflow-x-auto">
        <DataTable
          :value="store.items"
          :loading="store.listStatus === 'loading'"
          size="small"
          striped-rows
          aria-label="All your documents"
        >
          <Column header="File name">
            <template #body="{ data }: { data: Document }">
              <TruncatedText
                :text="data.file_name"
                max-width="16rem"
                class="font-medium text-ink"
              />
            </template>
          </Column>
          <Column header="Type">
            <template #body="{ data }: { data: Document }">
              <Tag
                :value="DOCUMENT_TYPE_LABELS[data.file_type]"
                :severity="documentTypeSeverity(data.file_type)"
              />
            </template>
          </Column>
          <Column header="Uploaded">
            <template #body="{ data }: { data: Document }">
              {{ formatUploadedAt(data.created_at) }}
            </template>
          </Column>
          <Column header="" style="width: 11rem">
            <template #body="{ data }: { data: Document }">
              <div class="flex justify-end gap-1">
                <Button
                  v-if="data.file_type === 'resume'"
                  v-tooltip.bottom="tooltip('View AI analysis')"
                  icon="pi pi-sparkles"
                  aria-label="View AI analysis"
                  link
                  size="small"
                  @click="openAnalysisModal(data)"
                />
                <Button
                  v-tooltip.bottom="tooltip('Download document')"
                  icon="pi pi-download"
                  aria-label="Download document"
                  link
                  size="small"
                  :loading="store.downloadingId === data.id"
                  @click="handleDownload(data)"
                />
                <Button
                  v-tooltip.bottom="tooltip('Edit document type')"
                  icon="pi pi-pencil"
                  aria-label="Edit document type"
                  link
                  size="small"
                  @click="openEditDialog(data)"
                />
                <Button
                  v-tooltip.bottom="tooltip('Delete document')"
                  icon="pi pi-trash"
                  aria-label="Delete document"
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

  <DocumentUploadDialog v-model:visible="uploadDialogVisible" />

  <DocumentEditDialog v-model:visible="editDialogVisible" :document="editingDocument" />

  <DocumentAnalysisModal
    v-if="analysisModalDocumentId"
    v-model:visible="analysisModalVisible"
    :document-id="analysisModalDocumentId"
  />
</template>
