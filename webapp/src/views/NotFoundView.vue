<script setup lang="ts">
import { RouterLink } from 'vue-router'
</script>

<template>
  <div
    class="flex min-h-screen flex-col items-center justify-center gap-3 bg-paper px-4 text-center"
  >
    <p class="font-display text-2xl font-bold text-ink">Page not found</p>
    <p class="text-sm text-slate">The page you're looking for doesn't exist or was moved.</p>
    <RouterLink to="/" class="text-sm font-medium text-teal"> Back to dashboard </RouterLink>
  </div>
</template>
