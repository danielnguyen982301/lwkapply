<script setup lang="ts">
import { ref, watch } from 'vue'
import AutoComplete from 'primevue/autocomplete'
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import Message from 'primevue/message'
import Tag from 'primevue/tag'

import { useApplicationDocumentsStore } from '@/stores/applicationDocuments'
import { useDocumentsStore } from '@/stores/documents'
import TruncatedText from '@/components/common/TruncatedText.vue'
import { DOCUMENT_TYPE_LABELS, documentTypeSeverity } from '@/lib/document-ui'
import { formatDateTime } from '@/lib/date-utils'
import type { Document } from '@/types/document'

// Attaches an existing document from the user's library to one
// application (POST /applications/{application_id}/documents - see
// stores/applicationDocuments.ts). Only used from
// components/applications/DocumentsPanel.vue today, but pulled out
// alongside DocumentUploadDialog.vue/DocumentEditDialog.vue for the same
// reason: keeps that panel's template down to the list it actually owns.
// attach() already updates applicationDocuments' own `items`/`total`, so
// unlike DocumentEditDialog.vue this needs no follow-up sync from the
// caller.
const visible = defineModel<boolean>('visible', { default: false })
const props = defineProps<{ applicationId: string }>()
const emit = defineEmits<{ attached: [doc: Document] }>()

const attached = useApplicationDocumentsStore()
const library = useDocumentsStore()

const suggestions = ref<Document[]>([])
const selectedDocument = ref<Document | null>(null)
let debounceTimer: ReturnType<typeof setTimeout> | undefined

watch(visible, (isVisible) => {
  if (!isVisible) return
  selectedDocument.value = null
  suggestions.value = []
})

function onSearch(event: { query: string }) {
  if (debounceTimer) clearTimeout(debounceTimer)
  debounceTimer = setTimeout(() => {
    library
      .searchDocuments(event.query)
      .then((results) => {
        // Already-attached documents would just 409 on submit - filter
        // them out of the suggestion list rather than let a user pick
        // one and hit an error.
        const attachedIds = new Set(attached.items.map((doc) => doc.id))
        suggestions.value = results.filter((doc) => !attachedIds.has(doc.id))
      })
      .catch(() => {
        suggestions.value = []
      })
  }, 300)
}

async function handleSubmit() {
  if (!selectedDocument.value) return
  try {
    const doc = await attached.attach(props.applicationId, selectedDocument.value.id)
    visible.value = false
    emit('attached', doc)
  } catch {
    // attached.attachError is already set and rendered below.
  }
}

function closeDialog() {
  visible.value = false
}

// Date + time, not just date - two documents can share a file_name (e.g.
// "resume.pdf" re-uploaded after edits), so the upload timestamp is what
// actually tells them apart in the suggestion list.
const formatUploadedAt = formatDateTime
</script>

<template>
  <Dialog
    v-model:visible="visible"
    header="Attach an existing document"
    modal
    dismissable-mask
    class="w-full max-w-md"
    @hide="closeDialog"
  >
    <form class="space-y-4" @submit.prevent="handleSubmit">
      <Message v-if="attached.attachStatus === 'error'" severity="error" :closable="false">
        {{ attached.attachError }}
      </Message>

      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-ink">Document *</label>
        <AutoComplete
          v-model="selectedDocument"
          :suggestions="suggestions"
          option-label="file_name"
          placeholder="Search your document library…"
          class="w-full"
          fluid
          @complete="onSearch"
        >
          <template #option="{ option }: { option: Document }">
            <div class="flex items-center justify-between gap-3 py-1">
              <div class="flex min-w-0 flex-col">
                <TruncatedText
                  :text="option.file_name"
                  max-width="14rem"
                  class="font-medium text-ink"
                />
                <span class="text-xs text-slate"
                  >Uploaded {{ formatUploadedAt(option.created_at) }}</span
                >
              </div>
              <Tag
                :value="DOCUMENT_TYPE_LABELS[option.file_type]"
                :severity="documentTypeSeverity(option.file_type)"
                class="shrink-0 text-xs"
              />
            </div>
          </template>
        </AutoComplete>
      </div>

      <div class="flex items-center justify-end gap-3 border-t border-slate/10 pt-4">
        <Button label="Cancel" severity="secondary" outlined type="button" @click="closeDialog" />
        <Button
          type="submit"
          :label="attached.attachStatus === 'loading' ? 'Attaching…' : 'Attach'"
          :loading="attached.attachStatus === 'loading'"
          :disabled="!selectedDocument"
        />
      </div>
    </form>
  </Dialog>
</template>
