<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import Message from 'primevue/message'
import ProgressSpinner from 'primevue/progressspinner'
import Textarea from 'primevue/textarea'

import ParsedResumeDisplay from './ParsedResumeDisplay.vue'
import AtsScoreDisplay from './AtsScoreDisplay.vue'
import { useResumeAnalysesStore } from '@/stores/resumeAnalyses'
import { useAtsScoresStore } from '@/stores/atsScores'
import { isAiJobInFlight } from '@/lib/ai-ui'

// Opened from components/applications/DocumentsPanel.vue, one row at a
// time - see that file for why this exists (quick "view analysis" from
// an application's Documents section, without switching to the AI Tools
// tab and hunting for which resume/application this was). Shows only the
// *latest* analysis/score for (documentId, applicationId), not full
// history - that's the AI Tools tab's job.
const props = defineProps<{ documentId: string; applicationId: string }>()
const visible = defineModel<boolean>('visible', { default: false })

const resumeAnalyses = useResumeAnalysesStore()
const atsScores = useAtsScoresStore()
const loading = ref(false)

// Reuses `current`/polling on both stores directly, same as
// ResumeAnalysesView.vue/AtsScoresView.vue's own detail dialogs - safe
// because this modal is mounted from a different route than either of
// those views, so Vue Router never has more than one of these three
// consumers alive at once (see resumeAnalyses.ts's docstring on
// fetchLatestForDocument() for the same reasoning applied to the list
// state, which - unlike `current` - genuinely does need isolation).
async function loadRelatedScore() {
  if (!resumeAnalyses.current || resumeAnalyses.current.status !== 'completed') {
    atsScores.current = null
    return
  }
  atsScores.current = await atsScores
    .fetchLatestForApplication(props.applicationId, resumeAnalyses.current.id)
    .catch(() => null)
}

async function load() {
  loading.value = true
  pastedDescription.value = ''
  resumeAnalyses.current = await resumeAnalyses
    .fetchLatestForDocument(props.documentId)
    .catch(() => null)
  loading.value = false

  if (resumeAnalyses.current && isAiJobInFlight(resumeAnalyses.current.status)) {
    resumeAnalyses.startPolling(resumeAnalyses.current.id)
  } else {
    await loadRelatedScore()
  }
}

watch(visible, (isVisible) => {
  if (isVisible) {
    load()
  } else {
    resumeAnalyses.stopPolling()
    atsScores.stopPolling()
  }
})

// The moment polling resolves the analysis to 'completed', fetch its
// score too - fetchOne() (stores/resumeAnalyses.ts) already stops polling
// on any terminal status, this just chains the next step.
watch(
  () => resumeAnalyses.current?.status,
  (status) => {
    if (status === 'completed') loadRelatedScore()
  },
)

async function analyzeNow() {
  await resumeAnalyses.create({ document_id: props.documentId }).catch(() => {})
}

async function scoreNow() {
  if (!resumeAnalyses.current) return
  await atsScores
    .create({
      resume_analysis_id: resumeAnalyses.current.id,
      application_id: props.applicationId,
    })
    .catch(() => {})
}

// Fallback for when the automatic job_url path fails (most commonly: the
// application has no job_url, or it couldn't be fetched - see backend/
// app/tasks/ai.py's JobDescriptionUnavailableError, whose message
// explicitly asks the caller to resubmit with job_description pasted).
// Without this, that failure was a dead end - no picker/textarea existed
// anywhere in this modal to act on that instruction. An explicit paste
// always wins over job_url server-side, so application_id is still sent
// for record-keeping even though job_description is what actually drives
// this attempt.
const pastedDescription = ref('')

async function scoreNowWithPaste() {
  if (!resumeAnalyses.current) return
  await atsScores
    .create({
      resume_analysis_id: resumeAnalyses.current.id,
      application_id: props.applicationId,
      job_description: pastedDescription.value,
    })
    .catch(() => {})
}

// Two distinct ways a scoreNow() attempt can fail, both needing the same
// paste-and-retry recovery, but only one of them ever sets
// atsScores.current: (1) the request is rejected synchronously - e.g. the
// application has no job_url at all, so the backend 422s before any row
// is ever created, and only atsScores.createError reflects it; (2) the
// request succeeds (a pending row is created) but the async job_url
// fetch fails later, reflected in atsScores.current.status/error_message
// once polling resolves it. Gating the paste fallback on
// `atsScores.current?.status === 'failed'` alone (as an earlier version
// of this file did) made it unreachable for case (1) - arguably the more
// common one, since "no job_url set at all" fails immediately, with no
// fetch attempt needed to know it can't work.
const atsScoreErrorMessage = computed(() => {
  if (atsScores.current?.status === 'failed') {
    return atsScores.current.error_message ?? 'Scoring failed. Try again.'
  }
  if (!atsScores.current && atsScores.createStatus === 'error') {
    return atsScores.createError
  }
  return null
})

const showAtsPasteFallback = computed(
  () =>
    atsScores.current?.status === 'failed' ||
    (!atsScores.current && atsScores.createStatus === 'error'),
)

// Belt-and-suspenders alongside the `visible` watcher above: if the whole
// Documents panel unmounts (user navigates away) while this modal is
// still open and polling, the `visible` prop watcher never fires (Vue
// doesn't trigger prop/model watchers on teardown), so without this the
// interval would keep running against these still-alive Pinia store
// singletons indefinitely. Same reasoning as every other view's
// onUnmounted-calls-stopPolling() convention in this feature.
onBeforeUnmount(() => {
  resumeAnalyses.stopPolling()
  atsScores.stopPolling()
})
</script>

<template>
  <Dialog v-model:visible="visible" header="Resume analysis" modal class="w-full max-w-2xl">
    <div v-if="loading" class="flex justify-center py-10" aria-live="polite">
      <ProgressSpinner aria-label="Loading" style="width: 2rem; height: 2rem" />
    </div>

    <div v-else-if="!resumeAnalyses.current" class="py-6 text-center">
      <p class="text-sm text-slate">No analysis yet for this resume.</p>
      <Message
        v-if="resumeAnalyses.createStatus === 'error'"
        severity="error"
        :closable="false"
        class="mt-4 text-left"
      >
        {{ resumeAnalyses.createError }}
      </Message>
      <Button
        label="Analyze now"
        class="mt-4"
        :loading="resumeAnalyses.createStatus === 'loading'"
        @click="analyzeNow"
      />
    </div>

    <template v-else>
      <div
        v-if="isAiJobInFlight(resumeAnalyses.current.status)"
        class="flex flex-col items-center gap-3 py-10"
        aria-live="polite"
      >
        <ProgressSpinner aria-label="Analyzing your resume" style="width: 2.5rem; height: 2.5rem" />
        <p class="text-sm text-slate">Analyzing your resume…</p>
      </div>

      <Message
        v-else-if="resumeAnalyses.current.status === 'failed'"
        severity="error"
        :closable="false"
      >
        {{ resumeAnalyses.current.error_message ?? 'This analysis failed. Try again.' }}
        <Button label="Try again" link size="small" class="ml-2" @click="analyzeNow" />
      </Message>

      <div v-else-if="resumeAnalyses.current.parsed_data" class="space-y-6">
        <ParsedResumeDisplay :parsed="resumeAnalyses.current.parsed_data" />

        <div class="border-t border-slate/10 pt-4">
          <div
            v-if="atsScores.current && isAiJobInFlight(atsScores.current.status)"
            class="flex flex-col items-center gap-3 py-6"
            aria-live="polite"
          >
            <ProgressSpinner
              aria-label="Scoring against this job"
              style="width: 2rem; height: 2rem"
            />
            <p class="text-sm text-slate">Scoring against this job…</p>
          </div>

          <AtsScoreDisplay
            v-else-if="atsScores.current?.status === 'completed' && atsScores.current.feedback"
            :score="atsScores.current.feedback"
            :job-description="atsScores.current.job_description"
            :job-description-source="atsScores.current.job_description_source"
          />

          <div v-else class="text-center">
            <p v-if="!atsScores.current" class="text-sm text-slate">
              Not scored against this job yet.
            </p>

            <Message
              v-if="atsScoreErrorMessage"
              severity="error"
              :closable="false"
              class="mt-3 text-left"
            >
              {{ atsScoreErrorMessage }}
            </Message>

            <Button
              label="Score now"
              class="mt-3"
              :severity="showAtsPasteFallback ? 'secondary' : undefined"
              :outlined="showAtsPasteFallback"
              :loading="atsScores.createStatus === 'loading'"
              @click="scoreNow"
            />

            <div v-if="showAtsPasteFallback" class="mt-4 space-y-2 text-left">
              <label for="modal-ats-retry-description" class="text-sm font-medium text-ink">
                Or paste the job description directly
              </label>
              <Textarea
                id="modal-ats-retry-description"
                v-model="pastedDescription"
                rows="5"
                class="w-full"
                placeholder="Paste the job description here…"
              />
              <p class="text-xs text-slate">
                {{ pastedDescription.trim().length }} / 20000 characters (minimum 50)
              </p>
              <Button
                label="Score with pasted description"
                size="small"
                :loading="atsScores.createStatus === 'loading'"
                :disabled="pastedDescription.trim().length < 50"
                @click="scoreNowWithPaste"
              />
            </div>
          </div>
        </div>
      </div>
    </template>
  </Dialog>
</template>
