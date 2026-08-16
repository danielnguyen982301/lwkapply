<script setup lang="ts">
// Shared single-line ellipsis truncation for any free-text table cell
// (company/position/application_name, file_name, contact name/email,
// etc.) - a plain Tailwind `truncate` class does nothing on its own
// inside a DataTable cell, since the <td> grows to fit content in an
// auto-layout table; this pairs it with an explicit max-width so long
// values actually clip instead of blowing out the column. `title` gives
// the full value on hover, since the visible text alone no longer does.
withDefaults(
  defineProps<{
    text: string | null | undefined
    maxWidth?: string
    fallback?: string
  }>(),
  {
    maxWidth: '14rem',
    fallback: '—',
  },
)
</script>

<template>
  <span class="block truncate" :style="{ maxWidth }" :title="text || undefined">{{
    text || fallback
  }}</span>
</template>
