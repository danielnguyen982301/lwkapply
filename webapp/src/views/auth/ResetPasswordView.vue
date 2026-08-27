<script setup lang="ts">
import { ref, computed } from 'vue'
import { useRoute, useRouter, RouterLink } from 'vue-router'
import { z } from 'zod'
import Button from 'primevue/button'
import Message from 'primevue/message'
import { toTypedSchema } from '@vee-validate/zod'
import { useForm } from 'vee-validate'

import { useAuthStore } from '@/stores/auth'
import CustomPassword from '@/components/custom_form_fields/CustomPassword.vue'

const auth = useAuthStore()
const route = useRoute()
const router = useRouter()

// Sourced from the emailed link's ?token= query param (see
// app/services/password_reset.py::_build_reset_email) - never typed in
// by hand, so there's no form field for it.
const token = computed(() => (typeof route.query.token === 'string' ? route.query.token : ''))

const schema = toTypedSchema(
  z
    .object({
      new_password: z.string().min(8, 'Use at least 8 characters.').max(128),
      confirm_password: z.string().min(1, 'Confirm your new password.'),
    })
    .refine((values) => values.new_password === values.confirm_password, {
      message: "Passwords don't match.",
      path: ['confirm_password'],
    }),
)

const { errors, handleSubmit } = useForm({
  validationSchema: schema,
  initialValues: { new_password: '', confirm_password: '' },
})

const submitting = ref(false)
const formError = ref<string | null>(null)
const succeeded = ref(false)

const onFormSubmit = handleSubmit(async (formValues) => {
  formError.value = null
  submitting.value = true
  try {
    await auth.confirmPasswordReset({
      token: token.value,
      new_password: formValues.new_password,
    })
    succeeded.value = true
  } catch {
    formError.value = auth.error ?? 'This reset link is invalid or has expired.'
  } finally {
    submitting.value = false
  }
})
</script>

<template>
  <div v-if="!token" class="space-y-5">
    <h2 class="font-display text-lg font-bold text-ink">Invalid link</h2>
    <p class="text-sm text-slate">This password reset link is missing or malformed.</p>
    <RouterLink to="/forgot-password" class="text-sm font-medium text-teal">
      Request a new link
    </RouterLink>
  </div>

  <div v-else-if="succeeded" class="space-y-5">
    <h2 class="font-display text-lg font-bold text-ink">Password reset</h2>
    <p class="text-sm text-slate">Your password has been changed. You can now log in.</p>
    <Button label="Log in" class="w-full" @click="router.push('/login')" />
  </div>

  <form v-else class="space-y-5" @submit.prevent="onFormSubmit">
    <h2 class="font-display text-lg font-bold text-ink">Reset your password</h2>

    <Message v-if="formError" severity="error" :closable="false">
      {{ formError }}
    </Message>

    <div class="flex flex-col gap-1">
      <label for="new-password" class="text-sm font-medium text-ink">New password</label>
      <CustomPassword
        input-id="new-password"
        name="new_password"
        :feedback="false"
        toggle-mask
        autocomplete="new-password"
        :invalid="!!errors.new_password"
        class="w-full"
        :input-props="{ class: 'w-full' }"
        hint="At least 8 characters."
      />
    </div>

    <div class="flex flex-col gap-1">
      <label for="confirm-password" class="text-sm font-medium text-ink">
        Confirm new password
      </label>
      <CustomPassword
        input-id="confirm-password"
        name="confirm_password"
        :feedback="false"
        toggle-mask
        autocomplete="new-password"
        :invalid="!!errors.confirm_password"
        class="w-full"
        :input-props="{ class: 'w-full' }"
      />
    </div>

    <Button
      type="submit"
      :label="submitting ? 'Resetting…' : 'Reset password'"
      class="w-full"
      :loading="submitting"
    />
  </form>
</template>
