<script setup lang="ts">
import { reactive, ref } from 'vue'
import { useRouter, RouterLink } from 'vue-router'
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

    <p v-if="formError" role="alert" class="rounded-card bg-coral/10 px-3 py-2 text-sm text-coral">
      {{ formError }}
    </p>

    <div class="grid grid-cols-2 gap-3">
      <div>
        <label for="firstName" class="mb-1 block text-sm font-medium text-ink">First name</label>
        <input
          id="firstName"
          v-model="form.firstName"
          type="text"
          autocomplete="given-name"
          class="w-full rounded-card border border-slate/20 px-3 py-2 text-sm focus:border-teal"
          :aria-invalid="Boolean(fieldErrors.firstName)"
        />
        <p v-if="fieldErrors.firstName" class="mt-1 text-sm text-coral">
          {{ fieldErrors.firstName }}
        </p>
      </div>
      <div>
        <label for="lastName" class="mb-1 block text-sm font-medium text-ink">Last name</label>
        <input
          id="lastName"
          v-model="form.lastName"
          type="text"
          autocomplete="family-name"
          class="w-full rounded-card border border-slate/20 px-3 py-2 text-sm focus:border-teal"
          :aria-invalid="Boolean(fieldErrors.lastName)"
        />
        <p v-if="fieldErrors.lastName" class="mt-1 text-sm text-coral">
          {{ fieldErrors.lastName }}
        </p>
      </div>
    </div>

    <div>
      <label for="email" class="mb-1 block text-sm font-medium text-ink">Email</label>
      <input
        id="email"
        v-model="form.email"
        type="email"
        autocomplete="email"
        class="w-full rounded-card border border-slate/20 px-3 py-2 text-sm focus:border-teal"
        :aria-invalid="Boolean(fieldErrors.email)"
      />
      <p v-if="fieldErrors.email" class="mt-1 text-sm text-coral">
        {{ fieldErrors.email }}
      </p>
    </div>

    <div>
      <label for="password" class="mb-1 block text-sm font-medium text-ink">Password</label>
      <input
        id="password"
        v-model="form.password"
        type="password"
        autocomplete="new-password"
        class="w-full rounded-card border border-slate/20 px-3 py-2 text-sm focus:border-teal"
        :aria-invalid="Boolean(fieldErrors.password)"
        :aria-describedby="fieldErrors.password ? 'password-error' : 'password-hint'"
      />
      <p v-if="fieldErrors.password" id="password-error" class="mt-1 text-sm text-coral">
        {{ fieldErrors.password }}
      </p>
      <p v-else id="password-hint" class="mt-1 text-sm text-slate">At least 8 characters.</p>
    </div>

    <button
      type="submit"
      class="w-full rounded-card bg-teal py-2 text-sm font-semibold text-white transition-opacity hover:opacity-90 disabled:opacity-50"
      :disabled="submitting"
    >
      {{ submitting ? 'Creating account…' : 'Create account' }}
    </button>

    <p class="text-center text-sm text-slate">
      Already have an account?
      <RouterLink to="/login" class="font-medium text-teal"> Log in </RouterLink>
    </p>
  </form>
</template>
