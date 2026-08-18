<script setup lang="ts">
import { useRouter } from 'vue-router'
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import Message from 'primevue/message'
import { toTypedSchema } from '@vee-validate/zod'
import z from 'zod'
import { useForm } from 'vee-validate'

import { useAuthStore } from '@/stores/auth'
import CustomPassword from '@/components/custom_form_fields/CustomPassword.vue'

// Requires re-entering the password (see AccountDeletePayload /
// DELETE /users/me on the backend) — an irreversible action shouldn't be
// possible from just a leaked access token. Resets on every open via
// `visible`, same reasoning as ContactFormDialog.vue's own watcher: PrimeVue
// Dialog unmounts its slot content while hidden, so the field's vee-validate
// state is already fresh on every reopen anyway — this just clears the
// form's *values*, not remounts.
const visible = defineModel<boolean>('visible', { default: false })

const auth = useAuthStore()
const router = useRouter()

const validationSchema = toTypedSchema(
  z.object({
    password: z.string().min(1, 'Enter your password to confirm.'),
  }),
)

const { errors, handleSubmit, resetForm } = useForm({
  validationSchema,
  initialValues: { password: '' },
})

function closeDialog() {
  visible.value = false
  resetForm()
}

const onFormSubmit = handleSubmit(async (formValues) => {
  try {
    await auth.deleteAccount({ password: formValues.password })
    visible.value = false
    await router.push({ name: 'login' })
  } catch {
    // auth.deleteAccountError is already set and rendered below.
  }
})
</script>

<template>
  <Dialog
    v-model:visible="visible"
    header="Delete account"
    modal
    dismissable-mask
    class="w-full max-w-sm"
    @hide="closeDialog"
  >
    <form class="space-y-4" @submit.prevent="onFormSubmit">
      <Message severity="warn" :closable="false">
        This permanently deletes your account, applications, documents, and everything else attached
        to it. This can't be undone.
      </Message>

      <Message v-if="auth.deleteAccountStatus === 'error'" severity="error" :closable="false">
        {{ auth.deleteAccountError }}
      </Message>

      <div class="flex flex-col gap-1">
        <label for="delete-account-password" class="text-sm font-medium text-ink">
          Confirm your password
        </label>
        <CustomPassword
          input-id="delete-account-password"
          name="password"
          :feedback="false"
          toggle-mask
          autocomplete="current-password"
          :invalid="!!errors.password"
          class="w-full"
          :input-props="{ class: 'w-full' }"
          autofocus
        />
      </div>

      <div class="flex items-center justify-end gap-3 border-t border-slate/10 pt-4">
        <Button label="Cancel" severity="secondary" outlined type="button" @click="closeDialog" />
        <Button
          type="submit"
          severity="danger"
          :label="auth.deleteAccountStatus === 'loading' ? 'Deleting…' : 'Delete my account'"
          :loading="auth.deleteAccountStatus === 'loading'"
        />
      </div>
    </form>
  </Dialog>
</template>
