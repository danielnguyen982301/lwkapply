<script setup lang="ts">
// Root component intentionally stays empty of layout/markup — each route
// picks its own layout (AppLayout for authenticated pages, AuthLayout for
// login/register), so nothing about a "shell" should live here.
</script>

<template>
  <RouterView />
</template>
