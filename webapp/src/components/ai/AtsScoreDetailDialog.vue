<script setup lang="ts">
import { ref, watch } from 'vue'
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import Message from 'primevue/message'
import ProgressSpinner from 'primevue/progressspinner'
import Textarea from 'primevue/textarea'

import AtsScoreDisplay from './AtsScoreDisplay.vue'
import { useAtsScoresStore } from '@/stores/atsScores'
import { isAiJobInFlight } from '@/lib/ai-ui'

// Extracted out of AtsScoresView.vue - the score detail dialog, including
// the failed-score paste-and-retry recovery. Reads `store.current`
// directly (set by the parent right before opening this dialog) rather
// than taking the score as a prop, since store.create() during a retry
// already reassigns `store.current` itself - a prop would need the
// parent to re-sync it on every retry instead of this dialog just
// reading the live store value.
const visible = defineModel<boolean>('visible', { default: false })
const emit = defineEmits<{ retried: [] }>()

const store = useAtsScoresStore()

// --- failed-score retry: the create dialog's job-description toggle
// (tracked application / job URL / paste) isn't available once a score
// already exists and failed - most commonly because the linked job_url
// couldn't be fetched (see backend/app/tasks/ai.py's
// JobDescriptionUnavailableError message, which explicitly asks the
// caller to resubmit with job_description pasted). Retrying always
// creates a new AtsScore (no update-in-place endpoint exists) -
// store.create() already assigns the result to `current`, so this
// dialog naturally swaps to the new attempt.
const retryDescription = ref('')

async function retryWithPastedDescription() {
  if (!store.current) return
  try {
    await store.create({
      resume_analysis_id: store.current.resume_analysis_id,
      job_description: retryDescription.value,
    })
    emit('retried')
  } catch {
    // store.createError is already set and rendered below.
  }
}

// Same shape as ResumeAnalysisModal.vue's visible watcher: starts polling
// on open if the score is still in flight, always stops on close so a
// closed dialog never keeps ticking against this store singleton.
watch(
  visible,
  (isVisible) => {
    retryDescription.value = ''
    if (isVisible && store.current && isAiJobInFlight(store.current.status)) {
      store.startPolling(store.current.id)
    } else {
      store.stopPolling()
    }
  },
  { immediate: true },
)

function closeDialog() {
  visible.value = false
}
</script>

<template>
  <Dialog
    v-model:visible="visible"
    header="ATS score"
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
        <ProgressSpinner
          aria-label="Scoring against the job description"
          style="width: 2.5rem; height: 2.5rem"
        />
        <p class="text-sm text-slate">Scoring against the job description…</p>
        <Message v-if="store.pollingTimedOut" severity="warn" :closable="false" class="mt-2">
          This is taking longer than expected. Close and reopen this score to check again.
        </Message>
      </div>

      <template v-else-if="store.current.status === 'failed'">
        <Message severity="error" :closable="false">
          {{ store.current.error_message ?? 'This score failed. Try again.' }}
        </Message>

        <div class="mt-3 space-y-2">
          <label for="ats-retry-description" class="text-sm font-medium text-ink">
            Paste the job description to retry
          </label>
          <Textarea
            id="ats-retry-description"
            v-model="retryDescription"
            rows="5"
            class="w-full"
            placeholder="Paste the job description here…"
          />
          <p class="text-xs text-slate">
            {{ retryDescription.trim().length }} / 20000 characters (minimum 50)
          </p>
          <Message v-if="store.createStatus === 'error'" severity="error" :closable="false">
            {{ store.createError }}
          </Message>
          <Button
            label="Retry with pasted description"
            size="small"
            :loading="store.createStatus === 'loading'"
            :disabled="retryDescription.trim().length < 50"
            @click="retryWithPastedDescription"
          />
        </div>
      </template>

      <AtsScoreDisplay
        v-else-if="store.current.status === 'completed' && store.current.feedback"
        :score="store.current.feedback"
        :job-description="store.current.job_description"
        :job-description-source="store.current.job_description_source"
        :job-url="store.current.job_url"
      />
    </template>
  </Dialog>
</template>
