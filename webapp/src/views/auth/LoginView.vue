<script setup lang="ts">
import { reactive, ref } from 'vue'
import { useRouter, useRoute, RouterLink } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const auth = useAuthStore()
const router = useRouter()
const route = useRoute()

const form = reactive({ email: '', password: '' })
const fieldErrors = reactive<{ email?: string; password?: string }>({})
const submitting = ref(false)
const formError = ref<string | null>(null)

function validate(): boolean {
  fieldErrors.email = undefined
  fieldErrors.password = undefined

  if (!form.email) {
    fieldErrors.email = 'Enter your email address.'
  } else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(form.email)) {
    fieldErrors.email = 'Enter a valid email address.'
  }

  if (!form.password) {
    fieldErrors.password = 'Enter your password.'
  }

  return !fieldErrors.email && !fieldErrors.password
}

async function handleSubmit() {
  formError.value = null
  if (!validate()) return

  submitting.value = true
  try {
    await auth.login({ email: form.email, password: form.password })
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
  <form novalidate class="space-y-5" @submit.prevent="handleSubmit">
    <h2 class="font-display text-lg font-bold text-ink">Log in</h2>

    <p v-if="formError" role="alert" class="rounded-card bg-coral/10 px-3 py-2 text-sm text-coral">
      {{ formError }}
    </p>

    <div>
      <label for="email" class="mb-1 block text-sm font-medium text-ink">Email</label>
      <input
        id="email"
        v-model="form.email"
        type="email"
        autocomplete="email"
        class="w-full rounded-card border border-slate/20 px-3 py-2 text-sm focus:border-teal"
        :aria-invalid="Boolean(fieldErrors.email)"
        :aria-describedby="fieldErrors.email ? 'email-error' : undefined"
      />
      <p v-if="fieldErrors.email" id="email-error" class="mt-1 text-sm text-coral">
        {{ fieldErrors.email }}
      </p>
    </div>

    <div>
      <label for="password" class="mb-1 block text-sm font-medium text-ink">Password</label>
      <input
        id="password"
        v-model="form.password"
        type="password"
        autocomplete="current-password"
        class="w-full rounded-card border border-slate/20 px-3 py-2 text-sm focus:border-teal"
        :aria-invalid="Boolean(fieldErrors.password)"
        :aria-describedby="fieldErrors.password ? 'password-error' : undefined"
      />
      <p v-if="fieldErrors.password" id="password-error" class="mt-1 text-sm text-coral">
        {{ fieldErrors.password }}
      </p>
    </div>

    <button
      type="submit"
      class="w-full rounded-card bg-teal py-2 text-sm font-semibold text-white transition-opacity hover:opacity-90 disabled:opacity-50"
      :disabled="submitting"
    >
      {{ submitting ? 'Logging in…' : 'Log in' }}
    </button>

    <p class="text-center text-sm text-slate">
      No account?
      <RouterLink to="/register" class="font-medium text-teal"> Sign up </RouterLink>
    </p>
  </form>
</template>
