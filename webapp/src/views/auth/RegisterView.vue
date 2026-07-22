<script setup lang="ts">
import { ref } from 'vue'
import { useRouter, RouterLink } from 'vue-router'
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

const initialValues = { firstName: '', lastName: '', email: '', password: '' }

const schema = toTypedSchema(
  z.object({
    firstName: z.string().min(1, 'Enter your first name.'),
    lastName: z.string().min(1, 'Enter your last name.'),
    email: z.string().min(1, 'Enter your email address.').email('Enter a valid email address.'),
    password: z.string().min(8, 'Use at least 8 characters.'),
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
    await auth.register({
      email: formValues.email,
      password: formValues.password,
      first_name: formValues.firstName,
      last_name: formValues.lastName,
    })
    await router.push('/')
  } catch {
    formError.value = auth.error ?? 'Could not create your account. Please try again.'
  } finally {
    submitting.value = false
  }
})
</script>

<template>
  <form class="space-y-5" @submit.prevent="onFormSubmit">
    <h2 class="font-display text-lg font-bold text-ink">Create your account</h2>

    <Message v-if="formError" severity="error" :closable="false">
      {{ formError }}
    </Message>

    <div class="grid grid-cols-2 gap-3">
      <div class="flex flex-col gap-1">
        <label for="firstName" class="text-sm font-medium text-ink">First name</label>
        <CustomInputText
          id="firstName"
          name="firstName"
          autocomplete="given-name"
          :invalid="!!errors.firstName"
          class="w-full"
        />
      </div>
      <div class="flex flex-col gap-1">
        <label for="lastName" class="text-sm font-medium text-ink">Last name</label>
        <CustomInputText
          id="lastName"
          name="lastName"
          autocomplete="family-name"
          :invalid="!!errors.lastName"
          class="w-full"
        />
      </div>
    </div>

    <div class="flex flex-col gap-1">
      <label for="email" class="text-sm font-medium text-ink">Email</label>
      <CustomInputText
        id="email"
        name="email"
        type="email"
        autocomplete="email"
        :invalid="!!errors.email"
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
        autocomplete="new-password"
        :invalid="!!errors.password"
        :aria-describedby="!!errors.password ? 'password-error' : 'password-hint'"
        class="w-full"
        :input-props="{ class: 'w-full' }"
        hint="At least 8 characters."
      />
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
