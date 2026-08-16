<script setup lang="ts">
import { ref } from 'vue'
import AutoComplete from 'primevue/autocomplete'
import TruncatedText from '@/components/common/TruncatedText.vue'
import { useDocumentsStore } from '@/stores/documents'
import type { Document } from '@/types/document'

// v-model'd to the selected resume Document (or null). Plain v-model, not
// a vee-validate field — mirrors DocumentsPanel.vue's own upload/edit
// dialogs, which use plain refs rather than vee-validate/zod, since a
// selection-only field doesn't fit that pattern cleanly (same reasoning
// noted for the file input there).
const model = defineModel<Document | null>({ default: null })

const store = useDocumentsStore()
const suggestions = ref<Document[]>([])

// 300ms debounce, same shape as DocumentDirectoryView.vue's search box.
// searchDocuments() is the isolated variant of fetchDocuments() - see
// stores/documents.ts - so typing here never disturbs the Document
// Library view's own list/pagination state.
let debounceTimer: ReturnType<typeof setTimeout> | undefined

function onComplete(event: { query: string }) {
  if (debounceTimer) clearTimeout(debounceTimer)
  debounceTimer = setTimeout(() => {
    store
      .searchDocuments(event.query, 'resume')
      .then((results) => {
        suggestions.value = results
      })
      .catch(() => {
        suggestions.value = []
      })
  }, 300)
}

// Date + time, not just date - two resumes can share a file_name (e.g.
// "resume.pdf" re-uploaded after edits), so the upload timestamp is what
// actually tells them apart in the suggestion list.
const dateFormatter = new Intl.DateTimeFormat(undefined, {
  dateStyle: 'medium',
  timeStyle: 'short',
})

function formatUploadedAt(value: string): string {
  return dateFormatter.format(new Date(value))
}
</script>

<template>
  <AutoComplete
    v-model="model"
    :suggestions="suggestions"
    option-label="file_name"
    placeholder="Search your uploaded resumes…"
    class="w-full"
    fluid
    @complete="onComplete"
  >
    <template #option="{ option }: { option: Document }">
      <div class="flex flex-col py-1">
        <TruncatedText :text="option.file_name" max-width="20rem" class="font-medium text-ink" />
        <span class="text-xs text-slate">Uploaded {{ formatUploadedAt(option.created_at) }}</span>
      </div>
    </template>
  </AutoComplete>
</template>
