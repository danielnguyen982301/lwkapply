<script setup lang="ts">
import { ref } from 'vue'
import Button from 'primevue/button'
import Message from 'primevue/message'
import { toTypedSchema } from '@vee-validate/zod'
import z from 'zod'
import { useForm } from 'vee-validate'

import { useAuthStore } from '@/stores/auth'
import CustomPassword from '@/components/custom_form_fields/CustomPassword.vue'

const auth = useAuthStore()

interface PasswordFormValues {
  current_password: string
  new_password: string
  confirm_password: string
}

const passwordValidationSchema = toTypedSchema(
  z
    .object({
      current_password: z.string().min(1, 'Enter your current password.'),
      new_password: z.string().min(8, 'Use at least 8 characters.').max(128),
      confirm_password: z.string().min(1, 'Confirm your new password.'),
    })
    .refine((values) => values.new_password === values.confirm_password, {
      message: "Passwords don't match.",
      path: ['confirm_password'],
    }),
)

const {
  errors: passwordErrors,
  handleSubmit: handlePasswordSubmit,
  resetForm: resetPasswordForm,
} = useForm<PasswordFormValues>({
  validationSchema: passwordValidationSchema,
  initialValues: { current_password: '', new_password: '', confirm_password: '' },
})

const passwordSuccess = ref(false)

const onPasswordSubmit = handlePasswordSubmit(async (formValues) => {
  passwordSuccess.value = false
  try {
    await auth.changePassword({
      current_password: formValues.current_password,
      new_password: formValues.new_password,
    })
    resetPasswordForm()
    passwordSuccess.value = true
  } catch {
    // auth.passwordError is already set and rendered below.
  }
})
</script>

<template>
  <section class="rounded-card border border-slate/10 bg-white p-4">
    <h2 class="font-display text-sm font-semibold text-ink">Password</h2>

    <form class="mt-4 space-y-4" @submit.prevent="onPasswordSubmit">
      <Message v-if="auth.passwordStatus === 'error'" severity="error" :closable="false">
        {{ auth.passwordError }}
      </Message>
      <Message
        v-else-if="passwordSuccess"
        severity="success"
        :closable="true"
        @close="passwordSuccess = false"
      >
        Password changed.
      </Message>

      <div class="flex flex-col gap-1">
        <label for="settings-current-password" class="text-sm font-medium text-ink">
          Current password
        </label>
        <CustomPassword
          input-id="settings-current-password"
          name="current_password"
          :feedback="false"
          toggle-mask
          autocomplete="current-password"
          :invalid="!!passwordErrors.current_password"
          class="w-full"
          :input-props="{ class: 'w-full' }"
        />
      </div>

      <div class="grid grid-cols-2 gap-3">
        <div class="flex flex-col gap-1">
          <label for="settings-new-password" class="text-sm font-medium text-ink">
            New password
          </label>
          <CustomPassword
            input-id="settings-new-password"
            name="new_password"
            :feedback="false"
            toggle-mask
            autocomplete="new-password"
            :invalid="!!passwordErrors.new_password"
            class="w-full"
            :input-props="{ class: 'w-full' }"
            hint="At least 8 characters."
          />
        </div>
        <div class="flex flex-col gap-1">
          <label for="settings-confirm-password" class="text-sm font-medium text-ink">
            Confirm new password
          </label>
          <CustomPassword
            input-id="settings-confirm-password"
            name="confirm_password"
            :feedback="false"
            toggle-mask
            autocomplete="new-password"
            :invalid="!!passwordErrors.confirm_password"
            class="w-full"
            :input-props="{ class: 'w-full' }"
          />
        </div>
      </div>

      <div class="flex justify-end border-t border-slate/10 pt-4">
        <Button
          type="submit"
          :label="auth.passwordStatus === 'loading' ? 'Changing…' : 'Change password'"
          :loading="auth.passwordStatus === 'loading'"
        />
      </div>
    </form>
  </section>
</template>
