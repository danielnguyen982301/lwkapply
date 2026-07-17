<script setup lang="ts">
import { reactive, ref } from 'vue'
import { useRouter, RouterLink } from 'vue-router'
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import Message from 'primevue/message'
import Password from 'primevue/password'

import { useAuthStore } from '@/stores/auth'

const auth = useAuthStore()
const router = useRouter()

const form = reactive({ firstName: '', lastName: '', email: '', password: '' })
const fieldErrors = reactive<Record<string, string | undefined>>({})
const submitting = ref(false)
const formError = ref<string | null>(null)

function validate(): boolean {
  fieldErrors.firstName = form.firstName ? undefined : 'Enter your first name.'
  fieldErrors.lastName = form.lastName ? undefined : 'Enter your last name.'
  fieldErrors.email = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(form.email)
    ? undefined
    : 'Enter a valid email address.'
  fieldErrors.password = form.password.length >= 8 ? undefined : 'Use at least 8 characters.'

  return Object.values(fieldErrors).every((error) => !error)
}

async function handleSubmit() {
  formError.value = null
  if (!validate()) return

  submitting.value = true
  try {
    await auth.register({
      email: form.email,
      password: form.password,
      first_name: form.firstName,
      last_name: form.lastName,
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
  <form novalidate class="space-y-5" @submit.prevent="handleSubmit">
    <h2 class="font-display text-lg font-bold text-ink">Create your account</h2>

    <Message v-if="formError" severity="error" :closable="false">
      {{ formError }}
    </Message>

    <div class="grid grid-cols-2 gap-3">
      <div class="flex flex-col gap-1">
        <label for="firstName" class="text-sm font-medium text-ink">First name</label>
        <InputText
          id="firstName"
          v-model="form.firstName"
          autocomplete="given-name"
          :invalid="Boolean(fieldErrors.firstName)"
          class="w-full"
        />
        <Message v-if="fieldErrors.firstName" severity="error" variant="simple" size="small">
          {{ fieldErrors.firstName }}
        </Message>
      </div>
      <div class="flex flex-col gap-1">
        <label for="lastName" class="text-sm font-medium text-ink">Last name</label>
        <InputText
          id="lastName"
          v-model="form.lastName"
          autocomplete="family-name"
          :invalid="Boolean(fieldErrors.lastName)"
          class="w-full"
        />
        <Message v-if="fieldErrors.lastName" severity="error" variant="simple" size="small">
          {{ fieldErrors.lastName }}
        </Message>
      </div>
    </div>

    <div class="flex flex-col gap-1">
      <label for="email" class="text-sm font-medium text-ink">Email</label>
      <InputText
        id="email"
        v-model="form.email"
        type="email"
        autocomplete="email"
        :invalid="Boolean(fieldErrors.email)"
        class="w-full"
      />
      <Message v-if="fieldErrors.email" severity="error" variant="simple" size="small">
        {{ fieldErrors.email }}
      </Message>
    </div>

    <div class="flex flex-col gap-1">
      <label for="password" class="text-sm font-medium text-ink">Password</label>
      <Password
        v-model="form.password"
        input-id="password"
        :feedback="false"
        toggle-mask
        autocomplete="new-password"
        :invalid="Boolean(fieldErrors.password)"
        :aria-describedby="fieldErrors.password ? 'password-error' : 'password-hint'"
        class="w-full"
        :input-props="{ class: 'w-full' }"
      />
      <Message
        v-if="fieldErrors.password"
        id="password-error"
        severity="error"
        variant="simple"
        size="small"
      >
        {{ fieldErrors.password }}
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
  </form>
</template>
