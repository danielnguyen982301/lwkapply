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
import { useField, useForm } from 'vee-validate'

import { useAuthStore } from '@/stores/auth'
import { timezoneOptions } from '@/lib/timezone'
import CustomInputText from '@/components/custom_form_fields/CustomInputText.vue'
import CustomToggleSwitch from '@/components/custom_form_fields/CustomToggleSwitch.vue'
import type { ProfileUpdatePayload } from '@/types/auth'

// first_name/last_name/avatar/timezone are editable here — email isn't
// client-settable (UserProfileUpdate has no email field on the backend),
// so it's shown read-only.
const auth = useAuthStore()
const confirm = useConfirm()

interface ProfileFormValues {
  first_name: string
  last_name: string
  auto_detect_timezone: boolean
  timezone: string | null
}

const profileValidationSchema = toTypedSchema(
  z
    .object({
      first_name: z.string().trim().min(1, 'First name is required.').max(100),
      last_name: z.string().trim().min(1, 'Last name is required.').max(100),
      auto_detect_timezone: z.boolean(),
      timezone: z.string().nullable(),
    })
    .refine((values) => values.auto_detect_timezone || !!values.timezone, {
      message: 'Choose a timezone, or turn auto-detect back on.',
      path: ['timezone'],
    }),
)

const {
  errors: profileErrors,
  handleSubmit: handleProfileSubmit,
  meta: profileMeta,
  resetForm: resetProfileForm,
} = useForm<ProfileFormValues>({
  validationSchema: profileValidationSchema,
  initialValues: {
    first_name: '',
    last_name: '',
    auto_detect_timezone: true,
    timezone: null,
  },
})

// auto_detect_timezone renders through CustomToggleSwitch.vue below (its
// own internal useField() call shares this same field's state - vee-validate
// keys field state by name within a form, same as CustomInputText.vue
// already does for first_name/last_name), but is also read here directly
// for its current value/meta. `timezone` stays a direct useField() call
// with no Custom*.vue wrapper - CustomSelect.vue's useField<string>() has
// no `null` in its type, which "off, nothing picked yet" needs. Each
// field's own `meta.dirty` (not the top-level form's) is what decides
// whether to actually include `timezone` in the PATCH payload below -
// PATCH /users/me flips timezone_is_manual purely from the *presence* of
// that key, so resaving the name fields alone must never resend an
// unchanged timezone and silently re-lock it.
const { value: autoDetectTimezone, meta: autoDetectMeta } =
  useField<boolean>('auto_detect_timezone')
const {
  value: timezoneValue,
  meta: timezoneFieldMeta,
  errorMessage: timezoneError,
} = useField<string | null>('timezone')
const timezoneSectionDirty = computed(() => autoDetectMeta.dirty || timezoneFieldMeta.dirty)
const timezoneOptionsList = timezoneOptions()

watch(
  () => auth.user,
  (user) => {
    if (!user) return
    resetProfileForm({
      values: {
        first_name: user.first_name,
        last_name: user.last_name,
        auto_detect_timezone: !user.timezone_is_manual,
        timezone: user.timezone,
      },
    })
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
    if (timezoneSectionDirty.value) {
      payload.timezone = formValues.auto_detect_timezone ? null : formValues.timezone
    }

    await auth.updateProfile(payload)
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
  <section class="rounded-card border border-slate/10 bg-paper p-4">
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

      <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
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

      <div class="flex flex-col gap-2 border-t border-slate/10 pt-4">
        <div class="flex items-center justify-between">
          <div>
            <p class="text-sm font-medium text-ink">Auto-detect timezone</p>
            <p class="text-sm text-slate">
              Kept in sync with your browser on login — used to localize interview reminder times.
            </p>
          </div>
          <CustomToggleSwitch name="auto_detect_timezone" aria-label="Auto-detect timezone" />
        </div>

        <div v-if="!autoDetectTimezone" class="flex flex-col gap-1 pl-1">
          <label for="settings-timezone" class="text-sm font-medium text-ink">
            Choose your own timezone
          </label>
          <Select
            v-model="timezoneValue"
            input-id="settings-timezone"
            :options="timezoneOptionsList"
            option-label="label"
            option-value="value"
            filter
            placeholder="Select a timezone"
            :invalid="!!timezoneError"
            class="w-full"
          />
          <Message v-if="timezoneError" severity="error" variant="simple" size="small">
            {{ timezoneError }}
          </Message>
        </div>
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
