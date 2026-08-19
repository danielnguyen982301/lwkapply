<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import Avatar from 'primevue/avatar'
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import Message from 'primevue/message'
import Select from 'primevue/select'
import { useConfirm } from 'primevue/useconfirm'
import { toTypedSchema } from '@vee-validate/zod'
import z from 'zod'
import { useForm } from 'vee-validate'

import { useAuthStore } from '@/stores/auth'
import { timezoneOptions } from '@/lib/timezone'
import CustomInputText from '@/components/custom_form_fields/CustomInputText.vue'
import type { ProfileUpdatePayload } from '@/types/auth'

// first_name/last_name/avatar/timezone are editable here — email isn't
// client-settable (UserProfileUpdate has no email field on the backend),
// so it's shown read-only.
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

// Timezone is plain state, not part of the vee-validate form above - it's
// nullable (clearing the Select means "resume auto-detecting", not "this
// field is invalid"), and only gets sent when actually changed from what's
// saved (see onProfileSubmit) - a shape that doesn't fit useField() any
// more cleanly than NotificationSettingsCard.vue's own toggles did.
const timezoneValue = ref<string | null>(null)
const savedTimezone = ref<string | null>(null)
const timezoneDirty = computed(() => timezoneValue.value !== savedTimezone.value)
const timezoneOptionsList = timezoneOptions()

watch(
  () => auth.user,
  (user) => {
    if (!user) return
    resetProfileForm({ values: { first_name: user.first_name, last_name: user.last_name } })
    timezoneValue.value = user.timezone
    savedTimezone.value = user.timezone
  },
  { immediate: true },
)

const profileSuccess = ref(false)

const onProfileSubmit = handleProfileSubmit(async (formValues) => {
  profileSuccess.value = false
  try {
    const payload: ProfileUpdatePayload = {
      first_name: formValues.first_name.trim(),
      last_name: formValues.last_name.trim(),
    }
    // Omitted entirely when unchanged - PATCH /users/me only touches
    // timezone_is_manual when the "timezone" key is present at all (see
    // UserProfileUpdate), so resaving the name fields alone must never
    // silently re-lock an auto-detected timezone.
    if (timezoneDirty.value) payload.timezone = timezoneValue.value

    await auth.updateProfile(payload)
    savedTimezone.value = timezoneValue.value
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
        :icon="auth.user?.avatar_url || avatarInitials ? undefined : 'pi pi-user'"
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

      <div class="flex flex-col gap-1">
        <label for="settings-timezone" class="text-sm font-medium text-ink">Timezone</label>
        <Select
          v-model="timezoneValue"
          input-id="settings-timezone"
          :options="timezoneOptionsList"
          option-label="label"
          option-value="value"
          filter
          show-clear
          placeholder="Auto-detect from browser"
          class="w-full"
        />
        <p class="text-xs text-slate">
          <template v-if="auth.user?.timezone_is_manual">
            Manually set — used to localize interview reminder times. Clear the field to resume
            auto-detecting from your browser.
          </template>
          <template v-else-if="auth.user?.timezone">
            Auto-detected from your browser ({{ auth.user.timezone }}) — used to localize interview
            reminder times.
          </template>
          <template v-else> Used to localize interview reminder times. </template>
        </p>
      </div>

      <div class="flex justify-end border-t border-slate/10 pt-4">
        <Button
          type="submit"
          :label="auth.profileStatus === 'loading' ? 'Saving…' : 'Save profile'"
          :loading="auth.profileStatus === 'loading'"
          :disabled="(!profileMeta.dirty && !timezoneDirty) || auth.profileStatus === 'loading'"
        />
      </div>
    </form>
  </section>
</template>
