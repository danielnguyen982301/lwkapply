<script setup lang="ts">
import Card from 'primevue/card'
</script>

<template>
  <div class="flex min-h-screen items-center justify-center bg-paper px-4">
    <div class="w-full max-w-sm">
      <p class="mb-8 text-center font-display text-xl font-bold text-ink">LwkApply</p>
      <Card>
        <template #content>
          <RouterView />
        </template>
      </Card>
    </div>
  </div>
</template>
