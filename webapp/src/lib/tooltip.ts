// Shared preset for `v-tooltip` (PrimeVue's Tooltip directive - registered
// globally in main.ts). Used instead of the native `title` attribute
// wherever a tooltip is the primary affordance for an icon-only control -
// native `title` has a fixed, unstyleable ~1s OS-level show delay that
// makes an icon-only button feel unresponsive on hover. 150ms is fast
// enough to feel immediate without flashing on an incidental mouse pass.
const SHOW_DELAY_MS = 500

export function tooltip(value: string) {
  return { value, showDelay: SHOW_DELAY_MS }
}
