<script setup lang="ts">
import Tag from 'primevue/tag'
import type { AtsScoreResult } from '@/types/ai'

const props = defineProps<{
  score: AtsScoreResult
  /** The actual job description text used for this score (pasted or
   * scraped from job_url) - always populated once a score is completed,
   * regardless of source. Without showing this, there's no way to tell
   * which job a score was actually run against. */
  jobDescription: string | null
  jobDescriptionSource?: 'pasted' | 'url' | null
  /** Only known when the caller already has the linked application on
   * hand (see AtsScoresView.vue) - optional, not every score has one
   * (application_id is nullable). */
  applicationSummary?: { company: string; position: string } | null
}>()

// Deliberately NOT built via string interpolation (e.g. `text-${x}`) -
// Tailwind's content scanner (tailwind.config.js) does static analysis of
// the source text, so a dynamically-constructed class name is invisible
// to it and gets purged from the production build. Literal class names
// here, using this project's actual design tokens (tailwind.config.js) -
// PrimeVue's 'success'/'warn'/'danger' severity strings (used elsewhere
// for Tag) aren't real Tailwind colors in this project, so they can't be
// reused directly for a plain-text color like this.
function scoreColorClass(score: number): string {
  if (score >= 75) return 'text-teal-dark'
  if (score >= 50) return 'text-amber'
  return 'text-coral'
}
</script>

<template>
  <div class="space-y-4">
    <div class="flex flex-wrap items-center gap-x-3 gap-y-2">
      <span class="font-display text-3xl font-bold" :class="scoreColorClass(props.score.score)">
        {{ score.score }}<span class="text-base font-normal text-slate">/100</span>
      </span>
      <Tag
        v-if="jobDescriptionSource"
        :value="jobDescriptionSource === 'url' ? 'Sourced from job URL' : 'Pasted job description'"
        severity="secondary"
      />
      <span v-if="applicationSummary" class="text-sm text-slate">
        Scored against {{ applicationSummary.company }} — {{ applicationSummary.position }}
      </span>
    </div>

    <p class="text-sm text-ink">{{ score.summary }}</p>

    <div v-if="score.matched_keywords.length > 0">
      <h4 class="mb-2 text-sm font-semibold text-ink">Matched keywords</h4>
      <div class="flex flex-wrap gap-2">
        <Tag
          v-for="keyword in score.matched_keywords"
          :key="keyword"
          :value="keyword"
          severity="success"
        />
      </div>
    </div>

    <div v-if="score.missing_keywords.length > 0">
      <h4 class="mb-2 text-sm font-semibold text-ink">Missing keywords</h4>
      <div class="flex flex-wrap gap-2">
        <Tag
          v-for="keyword in score.missing_keywords"
          :key="keyword"
          :value="keyword"
          severity="danger"
        />
      </div>
    </div>

    <div v-if="score.suggestions.length > 0">
      <h4 class="mb-2 text-sm font-semibold text-ink">Suggestions</h4>
      <ul class="list-inside list-disc space-y-1 text-sm text-ink">
        <li v-for="(suggestion, index) in score.suggestions" :key="index">{{ suggestion }}</li>
      </ul>
    </div>

    <!-- The ground truth of "which job was this scored against" - always
         shown, regardless of source, since a company/position label isn't
         always available (a standalone score with no application_id has
         nothing else to identify the job by). -->
    <div v-if="jobDescription">
      <h4 class="mb-2 text-sm font-semibold text-ink">Job description used</h4>
      <div
        class="max-h-48 overflow-y-auto rounded-card border border-slate/10 bg-paper p-3 text-sm whitespace-pre-wrap text-slate"
      >
        {{ jobDescription }}
      </div>
    </div>
  </div>
</template>
