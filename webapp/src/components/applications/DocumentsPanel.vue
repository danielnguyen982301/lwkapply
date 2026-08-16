<script setup lang="ts">
import { DateTime } from 'luxon'
import { onBeforeUnmount, onMounted, ref, watch } from 'vue'
import Button from 'primevue/button'
import Card from 'primevue/card'
import Message from 'primevue/message'
import Paginator from 'primevue/paginator'
import ProgressSpinner from 'primevue/progressspinner'
import Tag from 'primevue/tag'
import { useConfirm } from 'primevue/useconfirm'

import { tooltip } from '@/lib/tooltip'
import { useApplicationDocumentsStore } from '@/stores/applicationDocuments'
import { useDocumentsStore } from '@/stores/documents'
import { DOCUMENT_TYPE_LABELS, documentTypeSeverity } from '@/lib/document-ui'
import DocumentUploadDialog from '@/components/documents/DocumentUploadDialog.vue'
import DocumentEditDialog from '@/components/documents/DocumentEditDialog.vue'
import DocumentAttachDialog from '@/components/documents/DocumentAttachDialog.vue'
import ResumeAnalysisModal from '@/components/ai/ResumeAnalysisModal.vue'
import type { Document } from '@/types/document'

const props = defineProps<{ applicationId: string; jobUrl: string | null }>()

// Attached-to-this-application list/attach/detach vs. the user's whole
// document library (upload/edit/download/permanent-delete) - see
// stores/applicationDocuments.ts's module docstring for why these are two
// separate stores now that a document can belong to zero, one, or several
// applications.
const attached = useApplicationDocumentsStore()
const library = useDocumentsStore()

// --- AI analysis modal ---------------------------------------------------
const analysisModalVisible = ref(false)
const analysisModalDocumentId = ref<string | null>(null)

function openAnalysisModal(doc: Document) {
  analysisModalDocumentId.value = doc.id
  analysisModalVisible.value = true
}
const confirm = useConfirm()

// --- Upload dialog (uploads to the library, then attaches here) ---------
// DocumentUploadDialog.vue only handles the library upload itself - the
// attach-to-this-application step is this panel's own concern (a
// DocumentDirectoryView.vue upload has no application to attach to), done
// as a follow-up call once the dialog has already closed. A failure here
// surfaces via attached.attachError below, not inside the (by then
// closed) upload dialog.
const uploadDialogVisible = ref(false)

function handleUploaded(doc: Document) {
  attached.attach(props.applicationId, doc.id).catch(() => {})
}

// --- Attach-existing dialog ------------------------------------------
// DocumentAttachDialog.vue already updates applicationDocuments' own
// items/total on a successful attach - nothing to sync here.
const attachDialogVisible = ref(false)

// --- Edit (file_type only) dialog -------------------------------------
const editDialogVisible = ref(false)
const editingDocument = ref<Document | null>(null)

function openEditDialog(doc: Document) {
  editingDocument.value = doc
  editDialogVisible.value = true
}

// DocumentEditDialog.vue patches the library store's own copy - this
// panel's `attached.items` is a separate store's array, so it needs its
// own patch to stay in sync (same reasoning as the attach-after-upload
// split above).
function handleUpdated(doc: Document) {
  const index = attached.items.findIndex((item) => item.id === doc.id)
  if (index !== -1) attached.items[index] = doc
}

// --- Detach / download / list ----------------------------------------
function confirmDetach(doc: Document) {
  confirm.require({
    message: `Remove "${doc.file_name}" from this application? The document itself won't be deleted - it stays in your document library.`,
    header: 'Remove document',
    icon: 'pi pi-exclamation-triangle',
    rejectLabel: 'Cancel',
    acceptLabel: 'Remove',
    rejectProps: { label: 'Cancel', severity: 'secondary', outlined: true },
    acceptProps: { label: 'Remove', severity: 'danger' },
    accept: () => {
      attached.detach(props.applicationId, doc.id).catch(() => {})
    },
  })
}

function handleDownload(doc: Document) {
  library.downloadDocument(doc.id).catch(() => {})
}

function loadDocuments(page = 1) {
  attached.fetchAttached(props.applicationId, { page }).catch(() => {})
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
  attached.reset()
})
</script>

<template>
  <Card>
    <template #content>
      <div class="space-y-4">
        <div class="flex items-center justify-between">
          <h2 class="font-display text-lg font-semibold text-ink">Documents</h2>
          <div class="flex gap-2">
            <Button
              label="Attach existing"
              icon="pi pi-link"
              severity="secondary"
              outlined
              size="small"
              @click="attachDialogVisible = true"
            />
            <Button
              label="Upload document"
              icon="pi pi-upload"
              size="small"
              @click="uploadDialogVisible = true"
            />
          </div>
        </div>

        <Message v-if="attached.listStatus === 'error'" severity="error" :closable="false">
          <span>{{ attached.listError }}</span>
          <Button
            label="Retry"
            link
            size="small"
            class="ml-2"
            @click="loadDocuments(attached.page)"
          />
        </Message>

        <Message
          v-if="attached.attachError"
          severity="error"
          closable
          @close="attached.attachError = null"
        >
          {{ attached.attachError }}
        </Message>

        <Message
          v-if="attached.detachError"
          severity="error"
          closable
          @close="attached.detachError = null"
        >
          {{ attached.detachError }}
        </Message>

        <Message
          v-if="library.downloadError"
          severity="error"
          closable
          @close="library.downloadError = null"
        >
          {{ library.downloadError }}
        </Message>

        <div
          v-if="attached.listStatus === 'loading' && attached.items.length === 0"
          aria-live="polite"
          class="flex justify-center py-8"
        >
          <ProgressSpinner aria-label="Loading documents" style="width: 2rem; height: 2rem" />
        </div>

        <div
          v-else-if="attached.items.length === 0"
          class="rounded-card border border-dashed border-slate/30 p-6 text-center"
        >
          <p class="text-sm text-slate">
            No documents attached yet. Upload a new file or attach one already in your document
            library.
          </p>
        </div>

        <ul v-else class="divide-y divide-slate/10">
          <li
            v-for="doc in attached.items"
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
                v-if="doc.file_type === 'resume'"
                v-tooltip.bottom="tooltip('View AI analysis')"
                icon="pi pi-sparkles"
                aria-label="View AI analysis"
                link
                size="small"
                @click="openAnalysisModal(doc)"
              />
              <Button
                v-tooltip.bottom="tooltip('Download document')"
                icon="pi pi-download"
                aria-label="Download document"
                link
                size="small"
                :loading="library.downloadingId === doc.id"
                @click="handleDownload(doc)"
              />
              <Button
                v-tooltip.bottom="tooltip('Edit document type')"
                icon="pi pi-pencil"
                aria-label="Edit document type"
                link
                size="small"
                @click="openEditDialog(doc)"
              />
              <Button
                v-tooltip.bottom="tooltip('Remove from this application')"
                icon="pi pi-times"
                aria-label="Remove from this application"
                text
                severity="danger"
                size="small"
                :loading="attached.detachingId === doc.id"
                @click="confirmDetach(doc)"
              />
            </div>
          </li>
        </ul>

        <Paginator
          v-if="attached.total > attached.pageSize"
          :rows="attached.pageSize"
          :total-records="attached.total"
          :first="(attached.page - 1) * attached.pageSize"
          @page="onPageChange"
        />
      </div>
    </template>
  </Card>

  <DocumentUploadDialog v-model:visible="uploadDialogVisible" @uploaded="handleUploaded" />

  <DocumentEditDialog
    v-model:visible="editDialogVisible"
    :document="editingDocument"
    @updated="handleUpdated"
  />

  <DocumentAttachDialog
    v-model:visible="attachDialogVisible"
    :application-id="props.applicationId"
  />

  <ResumeAnalysisModal
    v-if="analysisModalDocumentId"
    v-model:visible="analysisModalVisible"
    :document-id="analysisModalDocumentId"
    :job-url="props.jobUrl"
  />
</template>
