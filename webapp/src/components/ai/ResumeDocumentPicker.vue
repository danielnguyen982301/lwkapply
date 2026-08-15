<script setup lang="ts">
import { ref } from 'vue'
import AutoComplete from 'primevue/autocomplete'
import { useDocumentDirectoryStore } from '@/stores/documentDirectory'
import type { DocumentWithApplication } from '@/types/document'

// v-model'd to the selected resume Document (or null). Plain v-model, not
// a vee-validate field — mirrors DocumentsPanel.vue's own upload/edit
// dialogs, which use plain refs rather than vee-validate/zod, since a
// selection-only field doesn't fit that pattern cleanly (same reasoning
// noted for the file input there).
const model = defineModel<DocumentWithApplication | null>({ default: null })

const store = useDocumentDirectoryStore()
const suggestions = ref<DocumentWithApplication[]>([])

// 300ms debounce, same shape as DocumentDirectoryView.vue's search box.
// searchResumeDocuments() is the isolated variant of fetchDocuments() -
// see stores/documentDirectory.ts - so typing here never disturbs the
// Documents directory view's own list/pagination state.
let debounceTimer: ReturnType<typeof setTimeout> | undefined

function onComplete(event: { query: string }) {
  if (debounceTimer) clearTimeout(debounceTimer)
  debounceTimer = setTimeout(() => {
    store
      .searchResumeDocuments(event.query)
      .then((results) => {
        suggestions.value = results
      })
      .catch(() => {
        suggestions.value = []
      })
  }, 300)
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
    <template #option="{ option }: { option: DocumentWithApplication }">
      <div class="flex flex-col py-1">
        <span class="font-medium text-ink">{{ option.file_name }}</span>
        <span class="text-xs text-slate">
          {{ option.application.company }} · {{ option.application.position }}
        </span>
      </div>
    </template>
  </AutoComplete>
</template>
