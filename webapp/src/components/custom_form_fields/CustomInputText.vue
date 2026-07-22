<script setup lang="ts">
import { InputText, Message } from 'primevue'
import { useField } from 'vee-validate'
import { useAttrs } from 'vue'

const props = defineProps<{ name: string }>()
const attrs = useAttrs()

const { value, errorMessage } = useField<string | null>(() => props.name)
</script>

<template>
  <InputText v-model="value" v-bind="attrs" />
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
