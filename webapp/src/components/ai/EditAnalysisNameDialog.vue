<script setup lang="ts">
import { ref, watch } from 'vue'
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import InputText from 'primevue/inputtext'
import Message from 'primevue/message'

import { useResumeAnalysesStore } from '@/stores/resumeAnalyses'
import type { ResumeAnalysis } from '@/types/ai'

// Edits a resume analysis's analysis_name - the only client-editable
// field (mirrors ResumeAnalysisUpdate; every other field is either
// server-computed or immutable once parsing completes). Same single-field
// edit shape as components/documents/DocumentEditDialog.vue (file_type).
// Used by views/ai/ResumeAnalysesView.vue's row-level rename button.
const visible = defineModel<boolean>('visible', { default: false })
const props = defineProps<{ analysis: ResumeAnalysis | null }>()
const emit = defineEmits<{ updated: [analysis: ResumeAnalysis] }>()

const store = useResumeAnalysesStore()
const editName = ref('')

watch(
  visible,
  (isVisible) => {
    if (isVisible) editName.value = props.analysis?.analysis_name ?? ''
  },
  { immediate: true },
)

async function handleSubmit() {
  if (!props.analysis || !editName.value.trim()) return
  try {
    const updated = await store.updateAnalysisName(props.analysis.id, {
      analysis_name: editName.value.trim(),
    })
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
    header="Edit analysis name"
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
        <label for="edit-analysis-name" class="text-sm font-medium text-ink">Name</label>
        <InputText
          id="edit-analysis-name"
          v-model="editName"
          class="w-full"
          maxlength="255"
          autofocus
        />
      </div>

      <div class="flex items-center justify-end gap-3 border-t border-slate/10 pt-4">
        <Button label="Cancel" severity="secondary" outlined type="button" @click="closeDialog" />
        <Button
          type="submit"
          :label="store.mutationStatus === 'loading' ? 'Saving…' : 'Save changes'"
          :loading="store.mutationStatus === 'loading'"
          :disabled="!editName.trim()"
        />
      </div>
    </form>
  </Dialog>
</template>
