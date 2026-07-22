<script setup lang="ts">
import { Message, Password } from 'primevue'
import { useField } from 'vee-validate'
import { useAttrs } from 'vue'

const props = defineProps<{ name: string; hint?: string }>()
const attrs = useAttrs()

const { value, errorMessage } = useField<string>(() => props.name)
</script>

<template>
  <Password v-model="value" v-bind="attrs" />
  <Message
    v-if="!!errorMessage"
    :id="`${attrs.id}-error`"
    severity="error"
    variant="simple"
    size="small"
  >
    {{ errorMessage }}
  </Message>
  <Message
    v-else-if="!!hint"
    :id="`${attrs.id}-hint`"
    severity="secondary"
    variant="simple"
    size="small"
  >
    {{ hint }}
  </Message>
</template>
