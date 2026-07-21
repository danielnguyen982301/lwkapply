<script setup lang="ts">
import { ref } from 'vue'
import { useRouter, RouterLink } from 'vue-router'
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

const initialValues = { firstName: '', lastName: '', email: '', password: '' }

// z.email() (Zod v4's top-level email validator) is its own schema, not a
// ZodString method, so .pipe() is what makes .min(1, ...) run first and
// .email() only run if that already passed — giving "Enter your email
// address." for empty vs. "Enter a valid email address." for a bad format,
// rather than the single shared message this form used to show either way.
const schema = z.object({
  firstName: z.string().min(1, 'Enter your first name.'),
  lastName: z.string().min(1, 'Enter your last name.'),
  email: z
    .string()
    .min(1, 'Enter your email address.')
    .pipe(z.email('Enter a valid email address.')),
  password: z.string().min(8, 'Use at least 8 characters.'),
})
const resolver = zodResolver(schema)

const submitting = ref(false)
const formError = ref<string | null>(null)

async function onFormSubmit({ valid, values }: FormSubmitEvent) {
  formError.value = null
  if (!valid) return

  submitting.value = true
  try {
    await auth.register({
      email: values.email,
      password: values.password,
      first_name: values.firstName,
      last_name: values.lastName,
    })
    await router.push('/')
  } catch {
    formError.value = auth.error ?? 'Could not create your account. Please try again.'
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
    <h2 class="font-display text-lg font-bold text-ink">Create your account</h2>

    <Message v-if="formError" severity="error" :closable="false">
      {{ formError }}
    </Message>

    <div class="grid grid-cols-2 gap-3">
      <div class="flex flex-col gap-1">
        <label for="firstName" class="text-sm font-medium text-ink">First name</label>
        <InputText
          id="firstName"
          name="firstName"
          autocomplete="given-name"
          :invalid="$form.firstName?.invalid"
          class="w-full"
        />
        <Message v-if="$form.firstName?.invalid" severity="error" variant="simple" size="small">
          {{ $form.firstName.error?.message }}
        </Message>
      </div>
      <div class="flex flex-col gap-1">
        <label for="lastName" class="text-sm font-medium text-ink">Last name</label>
        <InputText
          id="lastName"
          name="lastName"
          autocomplete="family-name"
          :invalid="$form.lastName?.invalid"
          class="w-full"
        />
        <Message v-if="$form.lastName?.invalid" severity="error" variant="simple" size="small">
          {{ $form.lastName.error?.message }}
        </Message>
      </div>
    </div>

    <div class="flex flex-col gap-1">
      <label for="email" class="text-sm font-medium text-ink">Email</label>
      <InputText
        id="email"
        name="email"
        type="email"
        autocomplete="email"
        :invalid="$form.email?.invalid"
        class="w-full"
      />
      <Message v-if="$form.email?.invalid" severity="error" variant="simple" size="small">
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
        autocomplete="new-password"
        :invalid="$form.password?.invalid"
        :aria-describedby="$form.password?.invalid ? 'password-error' : 'password-hint'"
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
      <Message v-else id="password-hint" severity="secondary" variant="simple" size="small">
        At least 8 characters.
      </Message>
    </div>

    <Button
      type="submit"
      :label="submitting ? 'Creating account…' : 'Create account'"
      class="w-full"
      :loading="submitting"
    />

    <p class="text-center text-sm text-slate">
      Already have an account?
      <RouterLink to="/login" class="font-medium text-teal"> Log in </RouterLink>
    </p>
  </Form>
</template>
