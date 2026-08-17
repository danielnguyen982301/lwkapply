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
// tab and hunting for which resume this was). Shows only the *latest*
// analysis/score for documentId, not full history - that's the AI Tools
// tab's job. `jobUrl` is the current application's job_url (looked up by
// the caller, which already has the full Application on hand) - AtsScore
// itself has no application link any more (see BACKEND_SUMMARY.md's "A
// note on Document / ApplicationDocument"), so this modal has to be
// handed the job_url explicitly rather than deriving it server-side.
const props = defineProps<{ documentId: string; jobUrl: string | null }>()
const visible = defineModel<boolean>('visible', { default: false })

const resumeAnalyses = useResumeAnalysesStore()
const atsScores = useAtsScoresStore()
const loading = ref(false)

const pastedDescription = ref('')
const hasJobUrl = computed(() => !!props.jobUrl)

// The latest score for this resume isn't necessarily a score against
// *this* application's job - it could equally be the latest of several
// scores run from AtsScoresView.vue against a different application's
// job description entirely (a score is just resume_analysis_id +
// job_description/job_url, with no link back to any one application -
// see BACKEND_SUMMARY.md's "A note on Document / ApplicationDocument").
// So unlike the "no score yet" case, having a completed score already
// doesn't mean there's nothing useful left to do here - `showRescoreForm`
// lets the user re-open the same scoring form to score again against
// *this* application's actual job, without losing the existing score's
// display until the new one actually completes.
const showRescoreForm = ref(false)
const showScoreForm = computed(() => !atsScores.current || showRescoreForm.value)

function openRescoreForm() {
  pastedDescription.value = ''
  showRescoreForm.value = true
}

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
    .fetchLatestForResumeAnalysis(resumeAnalyses.current.id)
    .catch(() => null)
}

async function load() {
  loading.value = true
  pastedDescription.value = ''
  showRescoreForm.value = false
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

// immediate: true matters here - DocumentsPanel.vue mounts this component
// with v-if="analysisModalDocumentId" *and* sets visible=true in the same
// click handler (openAnalysisModal()), so on first open this component's
// `visible` model starts at `true` from the very first render - there's
// no false->true transition for a plain watch() to catch, so load()
// silently never ran on the first open (only on a subsequent close+reopen,
// which - since the component stays mounted - is a real transition).
watch(
  visible,
  (isVisible) => {
    if (isVisible) {
      load()
    } else {
      resumeAnalyses.stopPolling()
      atsScores.stopPolling()
    }
  },
  { immediate: true },
)

// The moment polling resolves the analysis to 'completed', fetch its
// score too - fetchOne() (stores/resumeAnalyses.ts) already stops polling
// on any terminal status, this just chains the next step.
watch(
  () => resumeAnalyses.current?.status,
  (status) => {
    if (status === 'completed') loadRelatedScore()
  },
)

// Collapses the rescore form back down once a rescore actually finishes -
// otherwise, since atsScores.current already flips to the new (now
// completed) score the moment polling resolves it, the form would keep
// showing underneath a score it no longer applies to until the user
// manually dismissed it.
watch(
  () => atsScores.current?.status,
  (status) => {
    if (status === 'completed') showRescoreForm.value = false
  },
)

async function analyzeNow() {
  await resumeAnalyses.create({ document_id: props.documentId }).catch(() => {})
}

async function scoreNow() {
  if (!resumeAnalyses.current || !props.jobUrl) return
  await atsScores
    .create({
      resume_analysis_id: resumeAnalyses.current.id,
      job_url: props.jobUrl,
    })
    .catch(() => {})
}

async function scoreNowWithPaste() {
  if (!resumeAnalyses.current) return
  await atsScores
    .create({
      resume_analysis_id: resumeAnalyses.current.id,
      job_description: pastedDescription.value,
    })
    .catch(() => {})
}

// Fallback for when the automatic job_url path fails (the application's
// job_url couldn't be fetched - see backend/app/tasks/ai.py's
// JobDescriptionUnavailableError, whose message explicitly asks the
// caller to resubmit with job_description pasted). Two distinct ways a
// scoreNow() attempt can fail, both needing the same paste-and-retry
// recovery, but only one of them ever sets atsScores.current.status to
// 'failed': (1) the async job_url fetch fails later, reflected in
// atsScores.current once polling resolves it; (2) a synchronous
// rejection (e.g. no job_url, validation error), reflected only in
// atsScores.createError. Deliberately NOT gated on `!atsScores.current`
// any more - during a rescore, atsScores.current is still the *previous*
// completed score while the new attempt is in flight/failing, so that
// guard would silently swallow a real rescore error instead of showing it.
const atsScoreErrorMessage = computed(() => {
  if (atsScores.current?.status === 'failed') {
    return atsScores.current.error_message ?? 'Scoring failed. Try again.'
  }
  if (atsScores.createStatus === 'error') {
    return atsScores.createError
  }
  return null
})

const showAtsPasteFallback = computed(
  () =>
    !hasJobUrl.value ||
    atsScores.current?.status === 'failed' ||
    atsScores.createStatus === 'error',
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
  <Dialog
    v-model:visible="visible"
    header="Resume analysis"
    modal
    dismissable-mask
    class="w-full max-w-2xl"
  >
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

          <div v-else class="space-y-4">
            <!-- The latest score isn't necessarily a score against *this*
                 application's job - see showRescoreForm's declaration -
                 so this stays visible even once a rescore form is opened
                 below it, right up until the new attempt actually
                 completes and replaces it. -->
            <AtsScoreDisplay
              v-if="atsScores.current?.status === 'completed' && atsScores.current.feedback"
              :score="atsScores.current.feedback"
              :job-description="atsScores.current.job_description"
              :job-description-source="atsScores.current.job_description_source"
              :job-url="atsScores.current.job_url"
            />

            <div v-if="!showScoreForm" class="text-center">
              <Button
                label="Score again"
                icon="pi pi-refresh"
                link
                size="small"
                @click="openRescoreForm"
              />
            </div>

            <div
              v-else
              :class="
                atsScores.current ? 'border-t border-slate/10 pt-4 text-center' : 'text-center'
              "
            >
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
                v-if="hasJobUrl"
                :label="atsScores.current ? 'Score again against this job' : 'Score now'"
                class="mt-3"
                :severity="showAtsPasteFallback ? 'secondary' : undefined"
                :outlined="showAtsPasteFallback"
                :loading="atsScores.createStatus === 'loading'"
                @click="scoreNow"
              />

              <div v-if="showAtsPasteFallback" class="mt-4 space-y-2 text-left">
                <p v-if="!hasJobUrl" class="text-sm text-slate">
                  This application has no job URL saved. Provide job URL to the application or paste
                  the job description to score against it.
                </p>
                <label for="modal-ats-retry-description" class="text-sm font-medium text-ink">
                  {{ hasJobUrl ? 'Or paste the job description directly' : 'Job description' }}
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

              <Button
                v-if="atsScores.current"
                label="Cancel"
                link
                size="small"
                class="mt-2 block"
                @click="showRescoreForm = false"
              />
            </div>
          </div>
        </div>
      </div>
    </template>
  </Dialog>
</template>
