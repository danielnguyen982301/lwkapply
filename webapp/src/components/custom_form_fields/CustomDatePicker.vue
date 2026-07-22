<script setup lang="ts">
import { DatePicker, Message } from 'primevue'
import { useField } from 'vee-validate'
import { useAttrs } from 'vue'

const props = defineProps<{ name: string }>()
const attrs = useAttrs()

const { value, errorMessage } = useField<Date | (Date | null)>(() => props.name)
</script>

<template>
  <DatePicker v-model="value" v-bind="attrs" />
  <Message
    v-if="!!errorMessage"
    :id="`${attrs.id}-error`"
    severity="error"
    variant="simple"
    size="small"
  >
    {{ errorMessage }}
  </Message>
</template>
