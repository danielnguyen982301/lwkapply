<script setup lang="ts">
import { ref } from 'vue'
import { useRouter, useRoute, RouterLink } from 'vue-router'
import { z } from 'zod'
import Button from 'primevue/button'
import Message from 'primevue/message'
import { toTypedSchema } from '@vee-validate/zod'
import { useForm } from 'vee-validate'

import { useAuthStore } from '@/stores/auth'
import CustomInputText from '@/components/custom_form_fields/CustomInputText.vue'
import CustomPassword from '@/components/custom_form_fields/CustomPassword.vue'

const auth = useAuthStore()
const router = useRouter()
const route = useRoute()

const initialValues = { email: '', password: '' }

const schema = toTypedSchema(
  z.object({
    email: z.string().min(1, 'Enter your email address.').email('Enter a valid email address.'),
    password: z.string().min(1, 'Enter your password.'),
  }),
)

const { errors, handleSubmit } = useForm({
  validationSchema: schema,
  initialValues,
})
const submitting = ref(false)
const formError = ref<string | null>(null)

const onFormSubmit = handleSubmit(async (formValues) => {
  formError.value = null
  submitting.value = true
  try {
    await auth.login({ email: formValues.email, password: formValues.password })
    const redirect = typeof route.query.redirect === 'string' ? route.query.redirect : '/'
    await router.push(redirect)
  } catch {
    formError.value = auth.error ?? 'Could not log in. Check your email and password.'
  } finally {
    submitting.value = false
  }
})
</script>

<template>
  <form class="space-y-5" @submit.prevent="onFormSubmit">
    <h2 class="font-display text-lg font-bold text-ink">Log in</h2>

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
        :aria-describedby="!!errors.email ? 'email-error' : undefined"
        class="w-full"
      />
    </div>

    <div class="flex flex-col gap-1">
      <label for="password" class="text-sm font-medium text-ink">Password</label>
      <CustomPassword
        input-id="password"
        name="password"
        :feedback="false"
        toggle-mask
        autocomplete="current-password"
        :invalid="!!errors.password"
        :aria-describedby="!!errors.password ? 'password-error' : undefined"
        class="w-full"
        :input-props="{ class: 'w-full' }"
      />
    </div>

    <Button
      type="submit"
      :label="submitting ? 'Logging in…' : 'Log in'"
      class="w-full"
      :loading="submitting"
    />

    <p class="text-center text-sm text-slate">
      No account?
      <RouterLink to="/register" class="font-medium text-teal"> Sign up </RouterLink>
    </p>
  </form>
</template>
