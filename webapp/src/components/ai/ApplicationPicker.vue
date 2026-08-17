<script setup lang="ts">
import { ref } from 'vue'
import AutoComplete from 'primevue/autocomplete'
import Tag from 'primevue/tag'
import TruncatedText from '@/components/common/TruncatedText.vue'
import { useApplicationsStore } from '@/stores/applications'
import { formatDate } from '@/lib/date-utils'
import type { Application } from '@/types/application'

// Plain v-model, same reasoning as ResumeDocumentPicker.vue.
const model = defineModel<Application | null>({ default: null })

const store = useApplicationsStore()
const suggestions = ref<Application[]>([])

// searchApplications() is the isolated variant of fetchApplications() -
// see stores/applications.ts - so typing here never disturbs the
// Applications List view's own filters/pagination.
let debounceTimer: ReturnType<typeof setTimeout> | undefined

function onComplete(event: { query: string }) {
  if (debounceTimer) clearTimeout(debounceTimer)
  debounceTimer = setTimeout(() => {
    store
      .searchApplications(event.query)
      .then((results) => {
        suggestions.value = results
      })
      .catch(() => {
        suggestions.value = []
      })
  }, 300)
}

// applied_date is a backend `date`, not a `datetime` - formatDate (not
// formatDateTime) matches that.
const formatAppliedDate = formatDate
</script>

<template>
  <AutoComplete
    v-model="model"
    :suggestions="suggestions"
    option-label="company"
    placeholder="Search your tracked applications…"
    class="w-full"
    fluid
    complete-on-focus
    @complete="onComplete"
  >
    <template #option="{ option }: { option: Application }">
      <div class="flex items-center justify-between gap-3 py-1">
        <div class="flex min-w-0 flex-col">
          <span class="font-medium text-ink">{{ option.company }}</span>
          <span class="text-xs text-slate">{{ option.position }}</span>
          <TruncatedText
            v-if="option.application_name"
            :text="option.application_name"
            max-width="12rem"
            class="text-xs text-slate italic"
          />
          <span v-if="option.applied_date" class="text-xs text-slate">
            Applied {{ formatAppliedDate(option.applied_date) }}
          </span>
        </div>
        <!-- AtsScoresView.vue reads this application's job_url client-side
             and sends it as ATS Score's job_url (which then drives the
             backend's auto-fetch path) - surfacing it here up front avoids
             a later "no job_url" 422 surprise. -->
        <Tag
          :value="option.job_url ? 'Has job URL' : 'No job URL'"
          :severity="option.job_url ? 'success' : 'secondary'"
          class="shrink-0 text-xs"
        />
      </div>
    </template>
  </AutoComplete>
</template>
