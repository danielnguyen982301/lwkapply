<script setup lang="ts">
// Intentionally minimal: real content (Kanban board, application list,
// stats) lands in Phase 2. This exists so the authenticated shell and
// route guard have somewhere to land right after login.
</script>

<template>
  <div class="rounded-card border border-dashed border-slate/30 p-10 text-center">
    <h2 class="font-display text-lg font-semibold text-ink">No applications yet</h2>
    <p class="mx-auto mt-2 max-w-sm text-sm text-slate">
      Once application tracking ships, your saved roles will show up here as a board you can move
      through each stage of the process.
    </p>
  </div>
</template>
