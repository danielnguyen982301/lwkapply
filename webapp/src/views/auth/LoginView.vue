<script setup lang="ts">
import { ref } from 'vue'
import { useRouter, useRoute, RouterLink } from 'vue-router'
import { Form, type FormSubmitEvent } from '@primevue/forms'
import { zodResolver } from '@primevue/forms/resolvers/zod'
import { z } from 'zod'
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import Message from 'primevue/message'
import Password from 'primevue/password'
import { useAuthStore } from '@/stores/auth'

const auth = useAuthStore()
const router = useRouter()
const route = useRoute()

// Keys here must line up with each field's `name` prop below — that's how
// PrimeVue Forms matches values/errors back to inputs.
const initialValues = { email: '', password: '' }

// z.email() (Zod v4's top-level email validator, replacing the deprecated
// z.string().email() chain method) is its own schema, not a ZodString
// method — so .pipe() is what preserves "empty first, bad-format second"
// ordering: the .min(1, ...) check runs first, and .email() only runs if
// that already passed. This is what LoginView.spec.ts expects: an empty
// field reports "Enter your email address.", not "Enter a valid email
// address."
const schema = z.object({
  email: z
    .string()
    .min(1, 'Enter your email address.')
    .pipe(z.email('Enter a valid email address.')),
  password: z.string().min(1, 'Enter your password.'),
})
const resolver = zodResolver(schema)

const submitting = ref(false)
const formError = ref<string | null>(null)

async function onFormSubmit({ valid, values }: FormSubmitEvent) {
  formError.value = null
  if (!valid) return

  submitting.value = true
  try {
    await auth.login({ email: values.email, password: values.password })
    const redirect = typeof route.query.redirect === 'string' ? route.query.redirect : '/'
    await router.push(redirect)
  } catch {
    formError.value = auth.error ?? 'Could not log in. Check your email and password.'
  } finally {
    submitting.value = false
  }
}
</script>

<template>
  <Form
    v-slot="$form"
    :resolver="resolver"
    :initial-values="initialValues"
    :validate-on-value-update="false"
    :validate-on-blur="true"
    class="space-y-5"
    @submit="onFormSubmit"
  >
    <h2 class="font-display text-lg font-bold text-ink">Log in</h2>

    <Message v-if="formError" severity="error" :closable="false">
      {{ formError }}
    </Message>

    <div class="flex flex-col gap-1">
      <label for="email" class="text-sm font-medium text-ink">Email</label>
      <InputText
        id="email"
        name="email"
        type="email"
        autocomplete="email"
        :invalid="$form.email?.invalid"
        :aria-describedby="$form.email?.invalid ? 'email-error' : undefined"
        class="w-full"
      />
      <Message
        v-if="$form.email?.invalid"
        id="email-error"
        severity="error"
        variant="simple"
        size="small"
      >
        {{ $form.email.error?.message }}
      </Message>
    </div>

    <div class="flex flex-col gap-1">
      <label for="password" class="text-sm font-medium text-ink">Password</label>
      <Password
        input-id="password"
        name="password"
        :feedback="false"
        toggle-mask
        autocomplete="current-password"
        :invalid="$form.password?.invalid"
        :aria-describedby="$form.password?.invalid ? 'password-error' : undefined"
        class="w-full"
        :input-props="{ class: 'w-full' }"
      />
      <Message
        v-if="$form.password?.invalid"
        id="password-error"
        severity="error"
        variant="simple"
        size="small"
      >
        {{ $form.password.error?.message }}
      </Message>
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
  </Form>
</template>
