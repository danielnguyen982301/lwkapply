<script setup lang="ts">
import { ref, watch } from 'vue'
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import Message from 'primevue/message'

import ResumeDocumentPicker from './ResumeDocumentPicker.vue'
import { useResumeAnalysesStore } from '@/stores/resumeAnalyses'
import type { ResumeAnalysis } from '@/types/ai'
import type { Document } from '@/types/document'

// Extracted out of ResumeAnalysesView.vue - the "New resume analysis"
// form dialog. Emits the created analysis so the parent can immediately
// open ResumeAnalysisDetailDialog.vue on it (same "created -> open
// detail" handoff NewAtsScoreDialog.vue uses for AtsScoresView.vue).
const visible = defineModel<boolean>('visible', { default: false })
const emit = defineEmits<{ created: [analysis: ResumeAnalysis] }>()

const store = useResumeAnalysesStore()
const selectedDocument = ref<Document | null>(null)

// Reset on every open, not just on mount - the same dialog instance gets
// reused across multiple analyses without a full remount.
watch(visible, (isVisible) => {
  if (isVisible) selectedDocument.value = null
})

async function handleCreate() {
  if (!selectedDocument.value) return
  try {
    const analysis = await store.create({ document_id: selectedDocument.value.id })
    visible.value = false
    emit('created', analysis)
  } catch {
    // store.createError is already set and rendered below.
  }
}

function closeDialog() {
  visible.value = false
}
</script>

<template>
  <Dialog
    v-model:visible="visible"
    header="New resume analysis"
    modal
    dismissable-mask
    class="w-full max-w-lg"
    @hide="closeDialog"
  >
    <form class="space-y-4" @submit.prevent="handleCreate">
      <Message v-if="store.createStatus === 'error'" severity="error" :closable="false">
        {{ store.createError }}
      </Message>

      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-ink">Resume *</label>
        <ResumeDocumentPicker v-model="selectedDocument" />
      </div>

      <div class="flex items-center justify-end gap-3 border-t border-slate/10 pt-4">
        <Button label="Cancel" severity="secondary" outlined type="button" @click="closeDialog" />
        <Button
          type="submit"
          :label="store.createStatus === 'loading' ? 'Starting…' : 'Analyze'"
          :loading="store.createStatus === 'loading'"
          :disabled="!selectedDocument"
        />
      </div>
    </form>
  </Dialog>
</template>
