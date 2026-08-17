<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import AutoComplete from 'primevue/autocomplete'
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import InputText from 'primevue/inputtext'
import Message from 'primevue/message'
import SelectButton from 'primevue/selectbutton'
import Textarea from 'primevue/textarea'

import ApplicationPicker from './ApplicationPicker.vue'
import TruncatedText from '@/components/common/TruncatedText.vue'
import { useAtsScoresStore } from '@/stores/atsScores'
import { useResumeAnalysesStore } from '@/stores/resumeAnalyses'
import { formatDateTime } from '@/lib/date-utils'
import type { AtsScore, ResumeAnalysis } from '@/types/ai'
import type { Application } from '@/types/application'

// Extracted out of AtsScoresView.vue - the "New ATS score" form dialog.
const props = defineProps<{
  /** Prefilled resume_analysis_id, e.g. arriving via
   * ?resume_analysis_id=... from ResumeAnalysesView.vue's "Score against
   * a job" button. */
  initialResumeAnalysisId?: string | null
}>()

const visible = defineModel<boolean>('visible', { default: false })
const emit = defineEmits<{ created: [score: AtsScore] }>()

const store = useAtsScoresStore()
const resumeAnalyses = useResumeAnalysesStore()

// Live-searched (server-side status=completed + analysis_name search) via
// searchCompletedForPicker() - same debounced-AutoComplete pattern as
// ApplicationPicker.vue/ResumeDocumentPicker.vue, not a preloaded list
// capped at some page size.
const selectedAnalysis = ref<ResumeAnalysis | null>(null)
const suggestions = ref<ResumeAnalysis[]>([])

let debounceTimer: ReturnType<typeof setTimeout> | undefined
function onComplete(event: { query: string }) {
  if (debounceTimer) clearTimeout(debounceTimer)
  debounceTimer = setTimeout(() => {
    resumeAnalyses
      .searchCompletedForPicker(event.query)
      .then((results) => {
        suggestions.value = results
      })
      .catch(() => {
        suggestions.value = []
      })
  }, 300)
}

type DescriptionSource = 'application' | 'url' | 'paste'
const descriptionSourceOptions = [
  { label: 'Use a tracked application', value: 'application' as DescriptionSource },
  { label: 'Paste a job URL', value: 'url' as DescriptionSource },
  { label: 'Paste a job description', value: 'paste' as DescriptionSource },
]
const descriptionSource = ref<DescriptionSource>('application')
const selectedApplication = ref<Application | null>(null)
const pastedJobUrl = ref('')
const pastedDescription = ref('')

// Matches ResumeAnalysesView.vue's "Completed At" column - this is the
// field that actually tells apart two runs of the same resume.
function analyzedAtFor(analysis: ResumeAnalysis): string {
  return analysis.completed_at ? formatDateTime(analysis.completed_at) : '—'
}

// Reset the form fresh every time the dialog opens - mirrors
// ResumeAnalysisModal.vue's `immediate: true` visible watcher.
// fetchResumeAnalysisById() is isolated (doesn't touch the AI Tools
// list's shared `current`/polling state) so preloading the prefilled
// analysis here can't disturb it.
watch(visible, (isVisible) => {
  if (!isVisible) return
  selectedAnalysis.value = null
  suggestions.value = []
  if (props.initialResumeAnalysisId) {
    const id = props.initialResumeAnalysisId
    resumeAnalyses
      .fetchResumeAnalysisById(id)
      .then((analysis) => {
        if (analysis.status === 'completed') selectedAnalysis.value = analysis
      })
      .catch(() => {
        // Leave the picker empty - the id may since have been deleted.
      })
  }
  descriptionSource.value = 'application'
  selectedApplication.value = null
  pastedJobUrl.value = ''
  pastedDescription.value = ''
})

const canSubmit = computed(() => {
  if (!selectedAnalysis.value) return false
  if (descriptionSource.value === 'application') return !!selectedApplication.value?.job_url
  if (descriptionSource.value === 'url') return pastedJobUrl.value.trim().length > 0
  return pastedDescription.value.trim().length >= 50
})

async function handleCreate() {
  if (!selectedAnalysis.value || !canSubmit.value) return
  try {
    const score = await store.create({
      resume_analysis_id: selectedAnalysis.value.id,
      job_url:
        descriptionSource.value === 'application'
          ? selectedApplication.value?.job_url
          : descriptionSource.value === 'url'
            ? pastedJobUrl.value.trim()
            : null,
      job_description: descriptionSource.value === 'paste' ? pastedDescription.value : null,
    })
    visible.value = false
    emit('created', score)
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
    header="New ATS score"
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
        <label for="ats-resume" class="text-sm font-medium text-ink">Resume Analysis *</label>
        <AutoComplete
          v-model="selectedAnalysis"
          input-id="ats-resume"
          :suggestions="suggestions"
          option-label="document_file_name"
          placeholder="Search your completed resume analyses…"
          class="w-full"
          fluid
          complete-on-focus
          @complete="onComplete"
        >
          <template #option="{ option }: { option: ResumeAnalysis }">
            <div class="flex items-center justify-between gap-3 py-1">
              <TruncatedText :text="option.analysis_name" max-width="14rem" />
              <span class="shrink-0 text-xs text-slate">Analyzed {{ analyzedAtFor(option) }}</span>
            </div>
          </template>
        </AutoComplete>
      </div>

      <div class="flex flex-col gap-2">
        <label class="text-sm font-medium text-ink">Job description *</label>
        <SelectButton
          v-model="descriptionSource"
          :options="descriptionSourceOptions"
          option-label="label"
          option-value="value"
          :allow-empty="false"
          aria-label="Job description source"
        />

        <template v-if="descriptionSource === 'application'">
          <ApplicationPicker v-model="selectedApplication" />
          <p v-if="selectedApplication && !selectedApplication.job_url" class="text-xs text-coral">
            This application has no job URL saved - paste the job description instead, or add a job
            URL from the application's detail page first.
          </p>
        </template>

        <template v-else-if="descriptionSource === 'url'">
          <InputText
            v-model="pastedJobUrl"
            type="url"
            class="w-full"
            placeholder="https://…"
            aria-label="Job posting URL"
          />
          <p class="text-xs text-slate">
            We'll fetch and score against the job description at this URL.
          </p>
        </template>

        <template v-else>
          <Textarea
            v-model="pastedDescription"
            rows="6"
            class="w-full"
            placeholder="Paste the job description here…"
          />
          <p class="text-xs text-slate">
            {{ pastedDescription.trim().length }} / 20000 characters (minimum 50)
          </p>
        </template>
      </div>

      <div class="flex items-center justify-end gap-3 border-t border-slate/10 pt-4">
        <Button label="Cancel" severity="secondary" outlined type="button" @click="closeDialog" />
        <Button
          type="submit"
          :label="store.createStatus === 'loading' ? 'Starting…' : 'Score'"
          :loading="store.createStatus === 'loading'"
          :disabled="!canSubmit"
        />
      </div>
    </form>
  </Dialog>
</template>
