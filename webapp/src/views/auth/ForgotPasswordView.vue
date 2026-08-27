<script setup lang="ts">
import { ref } from 'vue'
import { RouterLink } from 'vue-router'
import { z } from 'zod'
import Button from 'primevue/button'
import Message from 'primevue/message'
import { toTypedSchema } from '@vee-validate/zod'
import { useForm } from 'vee-validate'

import { useAuthStore } from '@/stores/auth'
import CustomInputText from '@/components/custom_form_fields/CustomInputText.vue'

const auth = useAuthStore()

const schema = toTypedSchema(
  z.object({
    email: z.string().min(1, 'Enter your email address.').email('Enter a valid email address.'),
  }),
)

const { errors, handleSubmit } = useForm({
  validationSchema: schema,
  initialValues: { email: '' },
})

const submitting = ref(false)
const formError = ref<string | null>(null)
const submitted = ref(false)

const onFormSubmit = handleSubmit(async (formValues) => {
  formError.value = null
  submitting.value = true
  try {
    await auth.requestPasswordReset(formValues.email)
    submitted.value = true
  } catch {
    formError.value = auth.error ?? 'Something went wrong. Please try again.'
  } finally {
    submitting.value = false
  }
})
</script>

<template>
  <div v-if="submitted" class="space-y-5">
    <h2 class="font-display text-lg font-bold text-ink">Check your email</h2>
    <p class="text-sm text-slate">
      If an account exists for that email, we've sent a link to reset your password.
    </p>
    <RouterLink to="/login" class="text-sm font-medium text-teal">Back to log in</RouterLink>
  </div>

  <form v-else class="space-y-5" @submit.prevent="onFormSubmit">
    <div>
      <h2 class="font-display text-lg font-bold text-ink">Forgot your password?</h2>
      <p class="mt-1 text-sm text-slate">Enter your email and we'll send you a link to reset it.</p>
    </div>

    <Message v-if="formError" severity="error" :closable="false">
      {{ formError }}
    </Message>

    <div class="flex flex-col gap-1">
      <label for="email" class="text-sm font-medium text-ink">Email</label>
      <CustomInputText
        id="email"
        name="email"
        type="email"
        autocomplete="email"
        :invalid="!!errors.email"
        class="w-full"
      />
    </div>

    <Button
      type="submit"
      :label="submitting ? 'Sending…' : 'Send reset link'"
      class="w-full"
      :loading="submitting"
    />

    <p class="text-center text-sm text-slate">
      <RouterLink to="/login" class="font-medium text-teal">Back to log in</RouterLink>
    </p>
  </form>
</template>
