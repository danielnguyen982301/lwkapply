<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import TabMenu from 'primevue/tabmenu'
import type { MenuItem } from 'primevue/menuitem'

const route = useRoute()
const router = useRouter()

const items = ref<MenuItem[]>([
  { label: 'List', command: () => router.push({ name: 'applications' }) },
  { label: 'Board', command: () => router.push({ name: 'application-board' }) },
])

const activeIndex = ref(0)

watch(
  () => route.name,
  (name) => {
    activeIndex.value = name === 'application-board' ? 1 : 0
  },
  { immediate: true },
)

const tabModel = computed(() => items.value)
</script>

<template>
  <TabMenu v-model:active-index="activeIndex" :model="tabModel" aria-label="Applications view" />
</template>
