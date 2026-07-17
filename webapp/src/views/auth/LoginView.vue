<script setup lang="ts">
import { reactive, ref } from 'vue'
import { useRouter, useRoute, RouterLink } from 'vue-router'
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import Message from 'primevue/message'
import Password from 'primevue/password'
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

    <Message v-if="formError" severity="error" :closable="false">
      {{ formError }}
    </Message>

    <div class="flex flex-col gap-1">
      <label for="email" class="text-sm font-medium text-ink">Email</label>
      <InputText
        id="email"
        v-model="form.email"
        type="email"
        autocomplete="email"
        :invalid="Boolean(fieldErrors.email)"
        :aria-describedby="fieldErrors.email ? 'email-error' : undefined"
        class="w-full"
      />
      <Message
        v-if="fieldErrors.email"
        id="email-error"
        severity="error"
        variant="simple"
        size="small"
      >
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
        autocomplete="current-password"
        :invalid="Boolean(fieldErrors.password)"
        :aria-describedby="fieldErrors.password ? 'password-error' : undefined"
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
