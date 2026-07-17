<script setup lang="ts">
import Tag from 'primevue/tag'
import { APPLICATION_STATUS_LABELS, type ApplicationStatus } from '@/types/application'
import { applicationStatusSeverity } from '@/lib/application-ui'

defineProps<{ status: ApplicationStatus }>()
</script>

<template>
  <Tag :value="APPLICATION_STATUS_LABELS[status]" :severity="applicationStatusSeverity(status)" />
</template>
