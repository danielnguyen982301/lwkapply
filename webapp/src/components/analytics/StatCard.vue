<script setup lang="ts">
defineProps<{
  label: string
  value: string
  hint?: string
}>()
</script>

<template>
  <div class="rounded-card border border-slate/10 bg-paper p-4">
    <p class="text-xs font-medium uppercase tracking-wide text-slate">{{ label }}</p>
    <p class="mt-1 font-display text-2xl font-semibold text-ink">{{ value }}</p>
    <p v-if="hint" class="mt-1 text-xs text-slate">{{ hint }}</p>
  </div>
</template>
