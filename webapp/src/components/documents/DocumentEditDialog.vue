<script setup lang="ts">
import { ref, watch } from 'vue'
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import Message from 'primevue/message'
import Select from 'primevue/select'

import { useDocumentsStore } from '@/stores/documents'
import { documentTypeOptions } from '@/lib/document-ui'
import type { Document, DocumentType } from '@/types/document'

// Edits a document's file_type - the only client-editable field (mirrors
// DocumentUpdate; file_name/file_url are set once at upload time). Always
// goes through the top-level library store (PATCH /documents/{id}), even
// when opened from an application-scoped context - a document's file_type
// is a property of the document itself, not of any one application it's
// attached to. Shared by DocumentDirectoryView.vue and
// components/applications/DocumentsPanel.vue, which additionally needs to
// patch its own attached-documents list on `updated` (a separate store
// from the library one - see stores/applicationDocuments.ts).
const visible = defineModel<boolean>('visible', { default: false })
const props = defineProps<{ document: Document | null }>()
const emit = defineEmits<{ updated: [doc: Document] }>()

const store = useDocumentsStore()
const typeOptions = documentTypeOptions()

const editType = ref<DocumentType>('other')

watch(
  () => props.document,
  (doc) => {
    if (doc) editType.value = doc.file_type
  },
  { immediate: true },
)

async function handleSubmit() {
  if (!props.document) return
  try {
    const updated = await store.updateDocument(props.document.id, { file_type: editType.value })
    visible.value = false
    emit('updated', updated)
  } catch {
    // store.mutationError is already set and rendered below.
  }
}

function closeDialog() {
  visible.value = false
}
</script>

<template>
  <Dialog
    v-model:visible="visible"
    header="Edit document type"
    modal
    dismissable-mask
    class="w-full max-w-sm"
    @hide="closeDialog"
  >
    <form class="space-y-4" @submit.prevent="handleSubmit">
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
        <Button label="Cancel" severity="secondary" outlined type="button" @click="closeDialog" />
        <Button
          type="submit"
          :label="store.mutationStatus === 'loading' ? 'Saving…' : 'Save changes'"
          :loading="store.mutationStatus === 'loading'"
        />
      </div>
    </form>
  </Dialog>
</template>
