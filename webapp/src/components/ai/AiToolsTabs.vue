<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import TabMenu from 'primevue/tabmenu'
import type { MenuItem } from 'primevue/menuitem'

// Mirrors components/applications/ViewTabs.vue's List/Board toggle exactly
// - same shape, different two routes. See webapp/src/types/ai.ts's plan
// context: "AI Tools" is one nav item over two separate routes/stores
// (Resume Analyses, ATS Scores), joined by this tab bar, not one combined
// view holding both resource types.
const route = useRoute()
const router = useRouter()

const items = ref<MenuItem[]>([
  { label: 'Resume Analyses', command: () => router.push({ name: 'resume-analyses' }) },
  { label: 'ATS Scores', command: () => router.push({ name: 'ats-scores' }) },
])

const activeIndex = ref(0)

watch(
  () => route.name,
  (name) => {
    activeIndex.value = name === 'ats-scores' ? 1 : 0
  },
  { immediate: true },
)

const tabModel = computed(() => items.value)
</script>

<template>
  <TabMenu v-model:active-index="activeIndex" :model="tabModel" aria-label="AI Tools view" />
</template>
