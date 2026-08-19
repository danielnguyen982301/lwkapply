<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import Avatar from 'primevue/avatar'
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import Message from 'primevue/message'
import { useConfirm } from 'primevue/useconfirm'
import { toTypedSchema } from '@vee-validate/zod'
import z from 'zod'
import { useForm } from 'vee-validate'

import { useAuthStore } from '@/stores/auth'
import CustomInputText from '@/components/custom_form_fields/CustomInputText.vue'

// Only first_name/last_name/avatar are editable here — email isn't
// client-settable (UserProfileUpdate has no email field on the backend),
// so it's shown read-only. There's no timezone control either: UserRead
// doesn't return the stored timezone, so a picker here would have nothing
// real to prefill and could silently misrepresent what's actually saved.
const auth = useAuthStore()
const confirm = useConfirm()

interface ProfileFormValues {
  first_name: string
  last_name: string
}

const profileValidationSchema = toTypedSchema(
  z.object({
    first_name: z.string().trim().min(1, 'First name is required.').max(100),
    last_name: z.string().trim().min(1, 'Last name is required.').max(100),
  }),
)

const {
  errors: profileErrors,
  handleSubmit: handleProfileSubmit,
  meta: profileMeta,
  resetForm: resetProfileForm,
} = useForm<ProfileFormValues>({
  validationSchema: profileValidationSchema,
  initialValues: { first_name: '', last_name: '' },
})

watch(
  () => auth.user,
  (user) => {
    if (user)
      resetProfileForm({ values: { first_name: user.first_name, last_name: user.last_name } })
  },
  { immediate: true },
)

const profileSuccess = ref(false)

const onProfileSubmit = handleProfileSubmit(async (formValues) => {
  profileSuccess.value = false
  try {
    await auth.updateProfile({
      first_name: formValues.first_name.trim(),
      last_name: formValues.last_name.trim(),
    })
    profileSuccess.value = true
  } catch {
    // auth.profileError is already set and rendered below.
  }
})

const avatarInitials = computed(() => {
  const first = auth.user?.first_name?.[0] ?? ''
  const last = auth.user?.last_name?.[0] ?? ''
  return (first + last).toUpperCase() || undefined
})

const avatarFileInput = ref<HTMLInputElement | null>(null)

function triggerAvatarPicker() {
  avatarFileInput.value?.click()
}

async function onAvatarFileChange(event: Event) {
  const target = event.target as HTMLInputElement
  const file = target.files?.[0] ?? null
  target.value = ''
  if (!file) return
  await auth.uploadAvatar(file).catch(() => {})
}

function confirmRemoveAvatar() {
  confirm.require({
    message: 'Remove your profile photo?',
    header: 'Remove photo',
    icon: 'pi pi-exclamation-triangle',
    rejectProps: { label: 'Cancel', severity: 'secondary', outlined: true },
    acceptProps: { label: 'Remove', severity: 'danger' },
    accept: () => {
      auth.deleteAvatar().catch(() => {})
    },
  })
}
</script>

<template>
  <section class="rounded-card border border-slate/10 bg-white p-4">
    <h2 class="font-display text-sm font-semibold text-ink">Profile</h2>

    <div class="mt-4 flex items-center gap-4">
      <Avatar
        :image="auth.user?.avatar_url ?? undefined"
        :label="auth.user?.avatar_url ? undefined : avatarInitials"
        icon="pi pi-user"
        shape="circle"
        size="xlarge"
        class="shrink-0"
      />
      <div class="flex flex-col gap-1">
        <input
          ref="avatarFileInput"
          type="file"
          class="hidden"
          accept="image/png,image/jpeg,image/webp"
          @change="onAvatarFileChange"
        />
        <div class="flex gap-3">
          <Button
            label="Change photo"
            severity="secondary"
            outlined
            size="small"
            type="button"
            :loading="auth.avatarStatus === 'loading'"
            @click="triggerAvatarPicker"
          />
          <Button
            v-if="auth.user?.avatar_url"
            label="Remove"
            link
            size="small"
            type="button"
            @click="confirmRemoveAvatar"
          />
        </div>
        <Message
          v-if="auth.avatarStatus === 'error'"
          severity="error"
          variant="simple"
          size="small"
        >
          {{ auth.avatarError }}
        </Message>
      </div>
    </div>

    <form class="mt-5 space-y-4" @submit.prevent="onProfileSubmit">
      <Message v-if="auth.profileStatus === 'error'" severity="error" :closable="false">
        {{ auth.profileError }}
      </Message>
      <Message
        v-else-if="profileSuccess"
        severity="success"
        :closable="true"
        @close="profileSuccess = false"
      >
        Profile updated.
      </Message>

      <div class="grid grid-cols-2 gap-3">
        <div class="flex flex-col gap-1">
          <label for="settings-first-name" class="text-sm font-medium text-ink"> First name </label>
          <CustomInputText
            id="settings-first-name"
            name="first_name"
            autocomplete="given-name"
            :invalid="!!profileErrors.first_name"
            class="w-full"
          />
        </div>
        <div class="flex flex-col gap-1">
          <label for="settings-last-name" class="text-sm font-medium text-ink"> Last name </label>
          <CustomInputText
            id="settings-last-name"
            name="last_name"
            autocomplete="family-name"
            :invalid="!!profileErrors.last_name"
            class="w-full"
          />
        </div>
      </div>

      <div class="flex flex-col gap-1">
        <label for="settings-email" class="text-sm font-medium text-ink">Email</label>
        <InputText
          id="settings-email"
          :model-value="auth.user?.email"
          readonly
          aria-readonly="true"
          class="w-full"
        />
      </div>

      <div class="flex justify-end border-t border-slate/10 pt-4">
        <Button
          type="submit"
          :label="auth.profileStatus === 'loading' ? 'Saving…' : 'Save profile'"
          :loading="auth.profileStatus === 'loading'"
          :disabled="!profileMeta.dirty || auth.profileStatus === 'loading'"
        />
      </div>
    </form>
  </section>
</template>
