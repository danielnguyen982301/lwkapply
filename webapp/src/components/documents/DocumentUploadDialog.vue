<script setup lang="ts">
import { ref, watch } from 'vue'
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import Message from 'primevue/message'
import Select from 'primevue/select'

import { useDocumentsStore } from '@/stores/documents'
import { documentTypeOptions } from '@/lib/document-ui'
import type { Document, DocumentType } from '@/types/document'

// Uploads a file straight to the user's document library (POST
// /documents - always standalone, never application-scoped; see
// stores/documents.ts). Shared by DocumentDirectoryView.vue (library-only
// upload) and components/applications/DocumentsPanel.vue, which also
// needs the freshly-uploaded document attached to the current
// application afterward - that's deliberately NOT this component's
// concern: it emits `uploaded` with the created Document and closes
// itself, and the caller decides what happens next (DocumentsPanel
// attaches it as a follow-up call; see its own attachError handling for
// where that failure surfaces, since this dialog is already closed by
// then).
const visible = defineModel<boolean>('visible', { default: false })
const emit = defineEmits<{ uploaded: [doc: Document] }>()

const store = useDocumentsStore()
const typeOptions = documentTypeOptions()

const selectedFile = ref<File | null>(null)
const uploadType = ref<DocumentType>('other')
const fileInput = ref<HTMLInputElement | null>(null)
const uploadValidationError = ref<string | null>(null)

// Resets on every open, not just on mount - the same dialog instance gets
// reused across multiple uploads without a full remount.
watch(visible, (isVisible) => {
  if (!isVisible) return
  selectedFile.value = null
  uploadType.value = 'other'
  uploadValidationError.value = null
})

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
    const doc = await store.uploadDocument(selectedFile.value, uploadType.value)
    visible.value = false
    emit('uploaded', doc)
  } catch {
    // store.uploadError is already set and rendered below.
  }
}

function closeDialog() {
  visible.value = false
}
</script>

<template>
  <Dialog
    v-model:visible="visible"
    header="Upload document"
    modal
    class="w-full max-w-md"
    @hide="closeDialog"
  >
    <form class="space-y-4" @submit.prevent="handleUpload">
      <Message v-if="store.uploadStatus === 'error'" severity="error" :closable="false">
        {{ store.uploadError }}
      </Message>

      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-ink">File *</label>
        <!-- PDF/Word only, matching the backend's Content-Type validation
             (app/services/r2.py) — the accept attribute is just a UI hint,
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
        <Button label="Cancel" severity="secondary" outlined type="button" @click="closeDialog" />
        <Button
          type="submit"
          :label="store.uploadStatus === 'loading' ? 'Uploading…' : 'Upload'"
          :loading="store.uploadStatus === 'loading'"
        />
      </div>
    </form>
  </Dialog>
</template>
