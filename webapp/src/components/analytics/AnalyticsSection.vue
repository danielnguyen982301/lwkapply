<script setup lang="ts">
import Button from 'primevue/button'
import Message from 'primevue/message'
import ProgressSpinner from 'primevue/progressspinner'

defineProps<{
  title: string
  status: 'idle' | 'loading' | 'error'
  error?: string | null
  /** True once this section has data to show, even if a background
   * refetch (e.g. changing the activity window) is in flight - keeps a
   * loaded chart on screen instead of replacing it with a spinner. */
  hasData: boolean
}>()

const emit = defineEmits<{ retry: [] }>()
</script>

<template>
  <section class="rounded-card border border-slate/10 bg-paper p-4">
    <h2 class="font-display text-sm font-semibold text-ink">{{ title }}</h2>

    <Message v-if="status === 'error'" severity="error" :closable="false" class="mt-3">
      <span>{{ error }}</span>
      <Button label="Retry" link size="small" class="ml-2" @click="emit('retry')" />
    </Message>

    <div
      v-else-if="status === 'loading' && !hasData"
      class="flex justify-center py-10"
      aria-live="polite"
    >
      <ProgressSpinner
        :aria-label="`Loading ${title.toLowerCase()}`"
        style="width: 2.5rem; height: 2.5rem"
      />
    </div>

    <div v-else class="mt-3">
      <slot />
    </div>
  </section>
</template>
