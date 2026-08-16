<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import InputText from 'primevue/inputtext'
import Message from 'primevue/message'
import Select from 'primevue/select'
import SelectButton from 'primevue/selectbutton'
import Textarea from 'primevue/textarea'

import ApplicationPicker from './ApplicationPicker.vue'
import TruncatedText from '@/components/common/TruncatedText.vue'
import { useAtsScoresStore } from '@/stores/atsScores'
import type { AtsScore, ResumeAnalysis } from '@/types/ai'
import type { Application } from '@/types/application'

// Extracted out of AtsScoresView.vue - the "New ATS score" form dialog.
// `completedAnalyses`/`documentLabels` are passed down rather than
// fetched here: the parent view already loads both for its own table's
// resume-label column (resumeLabelFor), so fetching them again here
// would just be a duplicate round trip for the same data.
const props = defineProps<{
  completedAnalyses: ResumeAnalysis[]
  documentLabels: Record<string, string>
  /** Prefilled resume_analysis_id, e.g. arriving via
   * ?resume_analysis_id=... from ResumeAnalysesView.vue's "Score against
   * a job" button. */
  initialResumeAnalysisId?: string | null
}>()

const visible = defineModel<boolean>('visible', { default: false })
const emit = defineEmits<{ created: [score: AtsScore] }>()

const store = useAtsScoresStore()

const selectedAnalysisId = ref<string | null>(null)

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

// Date + time, matching ResumeAnalysesView.vue's "Completed At" column -
// this is the field that actually tells apart two runs of the same resume.
const dateTimeFormatter = new Intl.DateTimeFormat(undefined, {
  dateStyle: 'medium',
  timeStyle: 'short',
})

function resumeLabelFor(analysis: ResumeAnalysis): string {
  return props.documentLabels[analysis.document_id] || 'Resume analysis'
}

function analyzedAtFor(analysis: ResumeAnalysis): string {
  return analysis.completed_at ? dateTimeFormatter.format(new Date(analysis.completed_at)) : '—'
}

function selectedAnalysis(id: string | null): ResumeAnalysis | undefined {
  return props.completedAnalyses.find((a) => a.id === id)
}

// Reset the form fresh every time the dialog opens - mirrors
// ResumeAnalysisModal.vue's `immediate: true` visible watcher.
watch(visible, (isVisible) => {
  if (!isVisible) return
  selectedAnalysisId.value =
    props.initialResumeAnalysisId &&
    props.completedAnalyses.some((a) => a.id === props.initialResumeAnalysisId)
      ? props.initialResumeAnalysisId
      : null
  descriptionSource.value = 'application'
  selectedApplication.value = null
  pastedJobUrl.value = ''
  pastedDescription.value = ''
})

const canSubmit = computed(() => {
  if (!selectedAnalysisId.value) return false
  if (descriptionSource.value === 'application') return !!selectedApplication.value?.job_url
  if (descriptionSource.value === 'url') return pastedJobUrl.value.trim().length > 0
  return pastedDescription.value.trim().length >= 50
})

async function handleCreate() {
  if (!selectedAnalysisId.value || !canSubmit.value) return
  try {
    const score = await store.create({
      resume_analysis_id: selectedAnalysisId.value,
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
    class="w-full max-w-lg"
    @hide="closeDialog"
  >
    <form class="space-y-4" @submit.prevent="handleCreate">
      <Message v-if="store.createStatus === 'error'" severity="error" :closable="false">
        {{ store.createError }}
      </Message>

      <div class="flex flex-col gap-1">
        <label for="ats-resume" class="text-sm font-medium text-ink">Resume *</label>
        <Select
          v-model="selectedAnalysisId"
          input-id="ats-resume"
          :options="completedAnalyses"
          option-label="id"
          option-value="id"
          placeholder="Choose a completed analysis"
          class="w-full"
        >
          <template #option="{ option }: { option: ResumeAnalysis }">
            <div class="flex items-center justify-between gap-3 py-1">
              <TruncatedText :text="resumeLabelFor(option)" max-width="14rem" />
              <span class="shrink-0 text-xs text-slate">Analyzed {{ analyzedAtFor(option) }}</span>
            </div>
          </template>
          <template #value="{ value }: { value: string | null }">
            <div v-if="value && selectedAnalysis(value)" class="flex items-center gap-2 truncate">
              <span class="truncate">{{ resumeLabelFor(selectedAnalysis(value)!) }}</span>
              <span class="shrink-0 text-xs text-slate">
                · Analyzed {{ analyzedAtFor(selectedAnalysis(value)!) }}
              </span>
            </div>
            <span v-else class="text-slate">Choose a completed analysis</span>
          </template>
        </Select>
        <p v-if="completedAnalyses.length === 0" class="text-xs text-slate">
          No completed resume analyses yet - analyze a resume first.
        </p>
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
