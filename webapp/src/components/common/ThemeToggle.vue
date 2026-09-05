<script setup lang="ts">
import { computed, ref } from 'vue'
import Button from 'primevue/button'
import Popover from 'primevue/popover'
import { useThemeStore, type ThemeMode } from '@/stores/theme'
import { tooltip } from '@/lib/tooltip'

// Header icon button (next to NotificationBell) — same trigger-Button +
// ref-toggled-Popover shape NotificationBell.vue uses. Reflects the
// current *effective* theme (not just `mode`), so 'system' shows whichever
// icon actually matches what's on screen right now.
const theme = useThemeStore()
const popover = ref<InstanceType<typeof Popover> | null>(null)

const icon = computed(() => (theme.isDark ? 'pi pi-moon' : 'pi pi-sun'))

const options: { mode: ThemeMode; label: string; icon: string }[] = [
  { mode: 'system', label: 'System', icon: 'pi pi-desktop' },
  { mode: 'light', label: 'Light', icon: 'pi pi-sun' },
  { mode: 'dark', label: 'Dark', icon: 'pi pi-moon' },
]

function toggle(event: Event) {
  popover.value?.toggle(event)
}

function select(mode: ThemeMode) {
  theme.setMode(mode)
  popover.value?.hide()
}
</script>

<template>
  <Button
    v-tooltip.bottom="tooltip('Theme')"
    :icon="icon"
    severity="secondary"
    text
    rounded
    aria-label="Theme"
    @click="toggle"
  />

  <Popover ref="popover">
    <div class="flex w-40 flex-col gap-0.5 p-1">
      <button
        v-for="option in options"
        :key="option.mode"
        type="button"
        class="flex items-center gap-2 rounded-card px-3 py-2 text-left text-sm transition-colors hover:bg-paper"
        :class="option.mode === theme.mode ? 'font-medium text-teal' : 'text-ink'"
        @click="select(option.mode)"
      >
        <i :class="option.icon" aria-hidden="true" />
        {{ option.label }}
        <i
          v-if="option.mode === theme.mode"
          class="pi pi-check ml-auto text-xs"
          aria-hidden="true"
        />
      </button>
    </div>
  </Popover>
</template>
