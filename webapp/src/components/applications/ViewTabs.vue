<script setup lang="ts">
import { useRoute } from 'vue-router'

const route = useRoute()
</script>

<template>
  <nav class="flex gap-1 border-b border-slate/10" aria-label="Applications view">
    <RouterLink
      :to="{ name: 'applications' }"
      class="border-b-2 px-3 py-2 text-sm font-medium transition-colors"
      :class="
        route.name === 'applications'
          ? 'border-teal text-ink'
          : 'border-transparent text-slate hover:text-ink'
      "
    >
      List
    </RouterLink>
    <RouterLink
      :to="{ name: 'application-board' }"
      class="border-b-2 px-3 py-2 text-sm font-medium transition-colors"
      :class="
        route.name === 'application-board'
          ? 'border-teal text-ink'
          : 'border-transparent text-slate hover:text-ink'
      "
    >
      Board
    </RouterLink>
  </nav>
</template>
