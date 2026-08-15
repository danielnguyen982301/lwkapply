<script setup lang="ts">
import { ref } from 'vue'
import AutoComplete from 'primevue/autocomplete'
import Tag from 'primevue/tag'
import { useApplicationsStore } from '@/stores/applications'
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
</script>

<template>
  <AutoComplete
    v-model="model"
    :suggestions="suggestions"
    option-label="company"
    placeholder="Search your tracked applications…"
    class="w-full"
    fluid
    @complete="onComplete"
  >
    <template #option="{ option }: { option: Application }">
      <div class="flex items-center justify-between gap-3 py-1">
        <div class="flex flex-col">
          <span class="font-medium text-ink">{{ option.company }}</span>
          <span class="text-xs text-slate">{{ option.position }}</span>
        </div>
        <!-- job_url drives ATS Score's auto-fetch path (see AtsScoresView.vue) -
             surfacing it here up front avoids a later "no job_url" 422 surprise. -->
        <Tag
          :value="option.job_url ? 'Has job URL' : 'No job URL'"
          :severity="option.job_url ? 'success' : 'secondary'"
          class="shrink-0 text-xs"
        />
      </div>
    </template>
  </AutoComplete>
</template>
