<script setup lang="ts">
import { DateTime } from 'luxon'
import { onBeforeUnmount, onMounted, ref, watch } from 'vue'
import Button from 'primevue/button'
import Card from 'primevue/card'
import Dialog from 'primevue/dialog'
import Message from 'primevue/message'
import Paginator from 'primevue/paginator'
import ProgressSpinner from 'primevue/progressspinner'
import Select from 'primevue/select'
import Tag from 'primevue/tag'
import { useConfirm } from 'primevue/useconfirm'

import { useDocumentsStore } from '@/stores/documents'
import { DOCUMENT_TYPE_LABELS, documentTypeOptions, documentTypeSeverity } from '@/lib/document-ui'
import type { Document, DocumentType } from '@/types/document'

const props = defineProps<{ applicationId: string }>()

const store = useDocumentsStore()
const confirm = useConfirm()

const typeOptions = documentTypeOptions()

// --- Upload dialog ---------------------------------------------------
const uploadDialogVisible = ref(false)
const selectedFile = ref<File | null>(null)
const uploadType = ref<DocumentType>('other')
const fileInput = ref<HTMLInputElement | null>(null)
const uploadValidationError = ref<string | null>(null)

function openUploadDialog() {
  selectedFile.value = null
  uploadType.value = 'other'
  uploadValidationError.value = null
  uploadDialogVisible.value = true
}

function closeUploadDialog() {
  uploadDialogVisible.value = false
}

function triggerFilePicker() {
  fileInput.value?.click()
}

function onFileChange(event: Event) {
  const target = event.target as HTMLInputElement
  selectedFile.value = target.files?.[0] ?? null
  uploadValidationError.value = null
}

async function handleUpload() {
  if (!selectedFile.value) {
    uploadValidationError.value = 'Choose a file to upload.'
    return
  }
  try {
    await store.uploadDocument(props.applicationId, selectedFile.value, uploadType.value)
    uploadDialogVisible.value = false
  } catch {
    // store.uploadError is already set and rendered in the dialog below.
  }
}

// --- Edit (file_type only) dialog -------------------------------------
// Mirrors DocumentUpdate: file_name/file_url aren't client-editable, so
// this dialog only ever touches file_type.
const editDialogVisible = ref(false)
const editingDocument = ref<Document | null>(null)
const editType = ref<DocumentType>('other')

function openEditDialog(doc: Document) {
  editingDocument.value = doc
  editType.value = doc.file_type
  editDialogVisible.value = true
}

function closeEditDialog() {
  editDialogVisible.value = false
}

async function handleEditSubmit() {
  if (!editingDocument.value) return
  try {
    await store.updateDocument(props.applicationId, editingDocument.value.id, {
      file_type: editType.value,
    })
    editDialogVisible.value = false
  } catch {
    // store.mutationError is already set and rendered in the dialog below.
  }
}

// --- Delete / download / list ----------------------------------------
function confirmDelete(doc: Document) {
  confirm.require({
    message: `Delete "${doc.file_name}"? This can't be undone.`,
    header: 'Confirm deletion',
    icon: 'pi pi-exclamation-triangle',
    rejectLabel: 'Cancel',
    acceptLabel: 'Delete',
    rejectProps: { label: 'Cancel', severity: 'secondary', outlined: true },
    acceptProps: { label: 'Delete', severity: 'danger' },
    accept: () => {
      store.deleteDocument(props.applicationId, doc.id).catch(() => {})
    },
  })
}

function handleDownload(doc: Document) {
  store.downloadDocument(props.applicationId, doc.id).catch(() => {})
}

function loadDocuments(page = 1) {
  store.fetchDocuments(props.applicationId, { page }).catch(() => {})
}

function onPageChange(event: { page: number }) {
  loadDocuments(event.page + 1)
}

function formatDate(iso: string): string {
  return DateTime.fromISO(iso).toLocaleString(DateTime.DATE_MED)
}

onMounted(() => loadDocuments())

watch(
  () => props.applicationId,
  (newId, oldId) => {
    if (newId && newId !== oldId) loadDocuments()
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
          <h2 class="font-display text-lg font-semibold text-ink">Documents</h2>
          <Button
            label="Upload document"
            icon="pi pi-upload"
            size="small"
            @click="openUploadDialog"
          />
        </div>

        <Message v-if="store.mutationStatus === 'error'" severity="error" :closable="false">
          {{ store.mutationError }}
        </Message>

        <Message
          v-if="store.downloadError"
          severity="error"
          closable
          @close="store.downloadError = null"
        >
          {{ store.downloadError }}
        </Message>

        <Message v-if="store.listStatus === 'error'" severity="error" :closable="false">
          <span>{{ store.listError }}</span>
          <Button label="Retry" link size="small" class="ml-2" @click="loadDocuments(store.page)" />
        </Message>

        <div
          v-else-if="store.listStatus === 'loading' && store.items.length === 0"
          aria-live="polite"
          class="flex justify-center py-8"
        >
          <ProgressSpinner aria-label="Loading documents" style="width: 2rem; height: 2rem" />
        </div>

        <div
          v-else-if="store.items.length === 0"
          class="rounded-card border border-dashed border-slate/30 p-6 text-center"
        >
          <p class="text-sm text-slate">
            No documents yet. Upload a resume, cover letter, or other file for this application.
          </p>
        </div>

        <ul v-else class="divide-y divide-slate/10">
          <li
            v-for="doc in store.items"
            :key="doc.id"
            class="flex items-center justify-between gap-4 py-3"
          >
            <div class="min-w-0">
              <p class="truncate font-medium text-ink">{{ doc.file_name }}</p>
              <div class="mt-1 flex flex-wrap items-center gap-2 text-sm text-slate">
                <Tag
                  :value="DOCUMENT_TYPE_LABELS[doc.file_type]"
                  :severity="documentTypeSeverity(doc.file_type)"
                />
                <span>Uploaded {{ formatDate(doc.created_at) }}</span>
              </div>
            </div>
            <div class="flex shrink-0 gap-1">
              <Button
                icon="pi pi-download"
                aria-label="Download document"
                link
                size="small"
                :loading="store.downloadingId === doc.id"
                @click="handleDownload(doc)"
              />
              <Button
                icon="pi pi-pencil"
                aria-label="Edit document type"
                link
                size="small"
                @click="openEditDialog(doc)"
              />
              <Button
                icon="pi pi-trash"
                aria-label="Delete document"
                link
                severity="danger"
                size="small"
                @click="confirmDelete(doc)"
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
    v-model:visible="uploadDialogVisible"
    header="Upload document"
    modal
    class="w-full max-w-md"
    @hide="closeUploadDialog"
  >
    <form class="space-y-4" @submit.prevent="handleUpload">
      <Message v-if="store.uploadStatus === 'error'" severity="error" :closable="false">
        {{ store.uploadError }}
      </Message>

      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-ink">File *</label>
        <!-- PDF/Word only, matching the backend's Content-Type validation
             (app/services/s3.py) — the accept attribute is just a UI hint,
             the server still validates for real. -->
        <input
          ref="fileInput"
          type="file"
          class="hidden"
          accept=".pdf,.doc,.docx,application/pdf,application/msword,application/vnd.openxmlformats-officedocument.wordprocessingml.document"
          @change="onFileChange"
        />
        <div class="flex items-center gap-3">
          <Button
            label="Choose file"
            severity="secondary"
            outlined
            type="button"
            @click="triggerFilePicker"
          />
          <span class="truncate text-sm text-slate">{{
            selectedFile?.name ?? 'No file selected'
          }}</span>
        </div>
        <Message v-if="uploadValidationError" severity="error" variant="simple" size="small">
          {{ uploadValidationError }}
        </Message>
      </div>

      <div class="flex flex-col gap-1">
        <label for="document-type" class="text-sm font-medium text-ink">Type</label>
        <Select
          v-model="uploadType"
          input-id="document-type"
          :options="typeOptions"
          option-label="label"
          option-value="value"
          class="w-full"
        />
      </div>

      <div class="flex items-center justify-end gap-3 border-t border-slate/10 pt-4">
        <Button
          label="Cancel"
          severity="secondary"
          outlined
          type="button"
          @click="closeUploadDialog"
        />
        <Button
          type="submit"
          :label="store.uploadStatus === 'loading' ? 'Uploading…' : 'Upload'"
          :loading="store.uploadStatus === 'loading'"
        />
      </div>
    </form>
  </Dialog>

  <Dialog
    v-model:visible="editDialogVisible"
    header="Edit document type"
    modal
    class="w-full max-w-sm"
    @hide="closeEditDialog"
  >
    <form class="space-y-4" @submit.prevent="handleEditSubmit">
      <Message v-if="store.mutationStatus === 'error'" severity="error" :closable="false">
        {{ store.mutationError }}
      </Message>

      <div class="flex flex-col gap-1">
        <label for="edit-document-type" class="text-sm font-medium text-ink">Type</label>
        <Select
          v-model="editType"
          input-id="edit-document-type"
          :options="typeOptions"
          option-label="label"
          option-value="value"
          class="w-full"
        />
      </div>

      <div class="flex items-center justify-end gap-3 border-t border-slate/10 pt-4">
        <Button
          label="Cancel"
          severity="secondary"
          outlined
          type="button"
          @click="closeEditDialog"
        />
        <Button
          type="submit"
          :label="store.mutationStatus === 'loading' ? 'Saving…' : 'Save changes'"
          :loading="store.mutationStatus === 'loading'"
        />
      </div>
    </form>
  </Dialog>
</template>
