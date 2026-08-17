<script setup lang="ts">
import { computed, watch } from 'vue'
import { useRouter } from 'vue-router'
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import Message from 'primevue/message'
import ProgressSpinner from 'primevue/progressspinner'

import ParsedResumeDisplay from './ParsedResumeDisplay.vue'
import { useResumeAnalysesStore } from '@/stores/resumeAnalyses'
import { isAiJobInFlight } from '@/lib/ai-ui'
import { formatDateTime } from '@/lib/date-utils.ts'

// Extracted out of ResumeAnalysesView.vue - the analysis detail dialog,
// also the target of a freshly-created analysis. Reads `store.current`
// directly (set by the parent right before opening this dialog) rather
// than taking it as a prop - same reasoning as AtsScoreDetailDialog.vue.
const visible = defineModel<boolean>('visible', { default: false })

const store = useResumeAnalysesStore()
const router = useRouter()

const analyzedAt = computed(() =>
  store.current?.completed_at ? formatDateTime(store.current.completed_at) : null,
)

// Same shape as AtsScoreDetailDialog.vue/ResumeAnalysisModal.vue's own
// visible watchers: starts polling on open if still in flight, always
// stops on close so a closed dialog never keeps ticking against this
// store singleton.
watch(
  visible,
  (isVisible) => {
    if (isVisible && store.current && isAiJobInFlight(store.current.status)) {
      store.startPolling(store.current.id)
    } else {
      store.stopPolling()
    }
  },
  { immediate: true },
)

function scoreAgainstJob() {
  if (!store.current) return
  visible.value = false
  router.push({ name: 'ats-scores', query: { resume_analysis_id: store.current.id } })
}

function closeDialog() {
  visible.value = false
}
</script>

<template>
  <Dialog
    v-model:visible="visible"
    header="Resume analysis"
    modal
    dismissable-mask
    class="w-full max-w-2xl"
    @hide="closeDialog"
  >
    <template v-if="store.current">
      <div
        v-if="isAiJobInFlight(store.current.status)"
        class="flex flex-col items-center gap-3 py-10"
        aria-live="polite"
      >
        <ProgressSpinner aria-label="Analyzing your resume" style="width: 2.5rem; height: 2.5rem" />
        <p class="text-sm text-slate">Analyzing your resume…</p>
        <Message v-if="store.pollingTimedOut" severity="warn" :closable="false" class="mt-2">
          This is taking longer than expected. Close and reopen this analysis to check again.
        </Message>
      </div>

      <Message v-else-if="store.current.status === 'failed'" severity="error" :closable="false">
        {{ store.current.error_message ?? 'This analysis failed. Try again.' }}
      </Message>

      <div
        v-else-if="store.current.status === 'completed' && store.current.parsed_data"
        class="space-y-6"
      >
        <p v-if="store.current.analysis_name" class="text-sm font-medium text-ink">
          Analysis name: {{ store.current.analysis_name }}
        </p>
        <div class="flex items-center gap-2">
          <span v-if="analyzedAt" class="text-xs text-slate">Analyzed {{ analyzedAt }}</span>
        </div>
        <ParsedResumeDisplay :parsed="store.current.parsed_data" />
        <div class="mt-6 flex justify-end border-t border-slate/10 pt-4">
          <Button label="Score against a job" icon="pi pi-arrow-right" @click="scoreAgainstJob" />
        </div>
      </div>
    </template>
  </Dialog>
</template>
