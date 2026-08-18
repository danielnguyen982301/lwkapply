<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import Avatar from 'primevue/avatar'
import Button from 'primevue/button'
import InputNumber from 'primevue/inputnumber'
import InputText from 'primevue/inputtext'
import Message from 'primevue/message'
import ProgressSpinner from 'primevue/progressspinner'
import ToggleSwitch from 'primevue/toggleswitch'
import { useConfirm } from 'primevue/useconfirm'
import { toTypedSchema } from '@vee-validate/zod'
import z from 'zod'
import { useForm } from 'vee-validate'

import { useAuthStore } from '@/stores/auth'
import { useUserSettingsStore } from '@/stores/userSettings'
import CustomInputText from '@/components/custom_form_fields/CustomInputText.vue'
import CustomPassword from '@/components/custom_form_fields/CustomPassword.vue'
import DeleteAccountDialog from '@/components/settings/DeleteAccountDialog.vue'

const auth = useAuthStore()
const settingsStore = useUserSettingsStore()
const confirm = useConfirm()

// --- Profile -------------------------------------------------------------
// Only first_name/last_name/avatar are editable here — email isn't
// client-settable (UserProfileUpdate has no email field on the backend),
// so it's shown read-only. There's no timezone control either: UserRead
// doesn't return the stored timezone, so a picker here would have nothing
// real to prefill and could silently misrepresent what's actually saved.

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

// --- Password --------------------------------------------------------------

interface PasswordFormValues {
  current_password: string
  new_password: string
  confirm_password: string
}

const passwordValidationSchema = toTypedSchema(
  z
    .object({
      current_password: z.string().min(1, 'Enter your current password.'),
      new_password: z.string().min(8, 'Use at least 8 characters.').max(128),
      confirm_password: z.string().min(1, 'Confirm your new password.'),
    })
    .refine((values) => values.new_password === values.confirm_password, {
      message: "Passwords don't match.",
      path: ['confirm_password'],
    }),
)

const {
  errors: passwordErrors,
  handleSubmit: handlePasswordSubmit,
  resetForm: resetPasswordForm,
} = useForm<PasswordFormValues>({
  validationSchema: passwordValidationSchema,
  initialValues: { current_password: '', new_password: '', confirm_password: '' },
})

const passwordSuccess = ref(false)

const onPasswordSubmit = handlePasswordSubmit(async (formValues) => {
  passwordSuccess.value = false
  try {
    await auth.changePassword({
      current_password: formValues.current_password,
      new_password: formValues.new_password,
    })
    resetPasswordForm()
    passwordSuccess.value = true
  } catch {
    // auth.passwordError is already set and rendered below.
  }
})

// --- Notification preferences --------------------------------------------
// Plain reactive state rather than vee-validate — three booleans and one
// bounded number (enforced by InputNumber's own min/max) don't need a
// validation layer, and mixing ToggleSwitch into a vee-validate form would
// mean giving every toggle its own useField() for no real benefit.

const notificationsEnabled = ref(true)
const emailNotificationsEnabled = ref(true)
const pushNotificationsEnabled = ref(true)
const useCustomReminderLeadHours = ref(false)
const reminderLeadHours = ref<number | null>(24)

const DEFAULT_REMINDER_LEAD_HOURS = 24

watch(
  () => settingsStore.settings,
  (settings) => {
    if (!settings) return
    notificationsEnabled.value = settings.notifications_enabled
    emailNotificationsEnabled.value = settings.email_notifications_enabled
    pushNotificationsEnabled.value = settings.push_notifications_enabled
    useCustomReminderLeadHours.value = settings.reminder_lead_hours !== null
    reminderLeadHours.value = settings.reminder_lead_hours ?? DEFAULT_REMINDER_LEAD_HOURS
  },
  { immediate: true },
)

onMounted(() => {
  settingsStore.fetchSettings().catch(() => {})
})

const settingsSuccess = ref(false)

async function handleSettingsSubmit() {
  settingsSuccess.value = false
  try {
    await settingsStore.updateSettings({
      notifications_enabled: notificationsEnabled.value,
      email_notifications_enabled: emailNotificationsEnabled.value,
      push_notifications_enabled: pushNotificationsEnabled.value,
      reminder_lead_hours: useCustomReminderLeadHours.value ? reminderLeadHours.value : null,
    })
    settingsSuccess.value = true
  } catch {
    // settingsStore.mutationError is already set and rendered below.
  }
}

// --- Danger zone -----------------------------------------------------------

const deleteDialogVisible = ref(false)
</script>

<template>
  <div class="max-w-2xl space-y-6">
    <div>
      <h1 class="font-display text-xl font-semibold text-ink">Account settings</h1>
      <p class="mt-1 text-sm text-slate">Manage your profile, password, and notifications.</p>
    </div>

    <!-- Profile -->
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
            <label for="settings-first-name" class="text-sm font-medium text-ink">
              First name
            </label>
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

    <!-- Password -->
    <section class="rounded-card border border-slate/10 bg-white p-4">
      <h2 class="font-display text-sm font-semibold text-ink">Password</h2>

      <form class="mt-4 space-y-4" @submit.prevent="onPasswordSubmit">
        <Message v-if="auth.passwordStatus === 'error'" severity="error" :closable="false">
          {{ auth.passwordError }}
        </Message>
        <Message
          v-else-if="passwordSuccess"
          severity="success"
          :closable="true"
          @close="passwordSuccess = false"
        >
          Password changed.
        </Message>

        <div class="flex flex-col gap-1">
          <label for="settings-current-password" class="text-sm font-medium text-ink">
            Current password
          </label>
          <CustomPassword
            input-id="settings-current-password"
            name="current_password"
            :feedback="false"
            toggle-mask
            autocomplete="current-password"
            :invalid="!!passwordErrors.current_password"
            class="w-full"
            :input-props="{ class: 'w-full' }"
          />
        </div>

        <div class="grid grid-cols-2 gap-3">
          <div class="flex flex-col gap-1">
            <label for="settings-new-password" class="text-sm font-medium text-ink">
              New password
            </label>
            <CustomPassword
              input-id="settings-new-password"
              name="new_password"
              :feedback="false"
              toggle-mask
              autocomplete="new-password"
              :invalid="!!passwordErrors.new_password"
              class="w-full"
              :input-props="{ class: 'w-full' }"
              hint="At least 8 characters."
            />
          </div>
          <div class="flex flex-col gap-1">
            <label for="settings-confirm-password" class="text-sm font-medium text-ink">
              Confirm new password
            </label>
            <CustomPassword
              input-id="settings-confirm-password"
              name="confirm_password"
              :feedback="false"
              toggle-mask
              autocomplete="new-password"
              :invalid="!!passwordErrors.confirm_password"
              class="w-full"
              :input-props="{ class: 'w-full' }"
            />
          </div>
        </div>

        <div class="flex justify-end border-t border-slate/10 pt-4">
          <Button
            type="submit"
            :label="auth.passwordStatus === 'loading' ? 'Changing…' : 'Change password'"
            :loading="auth.passwordStatus === 'loading'"
          />
        </div>
      </form>
    </section>

    <!-- Notification preferences -->
    <section class="rounded-card border border-slate/10 bg-white p-4">
      <h2 class="font-display text-sm font-semibold text-ink">Notification preferences</h2>
      <p class="mt-1 text-sm text-slate">
        Interview reminders — how far ahead, and where they show up.
      </p>

      <div
        v-if="settingsStore.fetchStatus === 'loading' && !settingsStore.settings"
        class="flex justify-center py-8"
      >
        <ProgressSpinner
          aria-label="Loading notification preferences"
          style="width: 2.5rem; height: 2.5rem"
        />
      </div>

      <Message v-else-if="settingsStore.fetchStatus === 'error'" severity="error" :closable="false">
        <span>{{ settingsStore.fetchError }}</span>
        <Button
          label="Retry"
          link
          size="small"
          class="ml-2"
          @click="settingsStore.fetchSettings().catch(() => {})"
        />
      </Message>

      <form v-else class="mt-4 space-y-4" @submit.prevent="handleSettingsSubmit">
        <Message v-if="settingsStore.mutationStatus === 'error'" severity="error" :closable="false">
          {{ settingsStore.mutationError }}
        </Message>
        <Message
          v-else-if="settingsSuccess"
          severity="success"
          :closable="true"
          @close="settingsSuccess = false"
        >
          Preferences saved.
        </Message>

        <div class="flex items-center justify-between">
          <div>
            <p class="text-sm font-medium text-ink">Notifications</p>
            <p class="text-sm text-slate">Master switch for interview reminders.</p>
          </div>
          <ToggleSwitch v-model="notificationsEnabled" aria-label="Enable notifications" />
        </div>

        <div
          class="flex items-center justify-between pl-1"
          :class="!notificationsEnabled && 'opacity-50'"
        >
          <div>
            <p class="text-sm font-medium text-ink">Email</p>
            <p class="text-sm text-slate">Send reminders by email.</p>
          </div>
          <ToggleSwitch
            v-model="emailNotificationsEnabled"
            :disabled="!notificationsEnabled"
            aria-label="Enable email notifications"
          />
        </div>

        <div
          class="flex items-center justify-between pl-1"
          :class="!notificationsEnabled && 'opacity-50'"
        >
          <div>
            <p class="text-sm font-medium text-ink">Push</p>
            <p class="text-sm text-slate">Send reminders to your mobile device.</p>
          </div>
          <ToggleSwitch
            v-model="pushNotificationsEnabled"
            :disabled="!notificationsEnabled"
            aria-label="Enable push notifications"
          />
        </div>

        <div class="border-t border-slate/10 pt-4">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm font-medium text-ink">Reminder lead time</p>
              <p class="text-sm text-slate">
                How long before an interview to send the reminder. Default is
                {{ DEFAULT_REMINDER_LEAD_HOURS }} hours.
              </p>
            </div>
            <ToggleSwitch
              v-model="useCustomReminderLeadHours"
              aria-label="Use a custom reminder lead time"
            />
          </div>
          <div v-if="useCustomReminderLeadHours" class="mt-3 flex items-center gap-2">
            <InputNumber
              v-model="reminderLeadHours"
              input-id="settings-reminder-lead-hours"
              :min="1"
              :max="168"
              suffix=" hours"
              aria-label="Reminder lead time in hours"
              class="w-40"
            />
          </div>
        </div>

        <div class="flex justify-end border-t border-slate/10 pt-4">
          <Button
            type="submit"
            :label="settingsStore.mutationStatus === 'loading' ? 'Saving…' : 'Save preferences'"
            :loading="settingsStore.mutationStatus === 'loading'"
          />
        </div>
      </form>
    </section>

    <!-- Danger zone -->
    <section class="rounded-card border border-coral/30 bg-white p-4">
      <h2 class="font-display text-sm font-semibold text-coral">Danger zone</h2>
      <div class="mt-3 flex items-center justify-between">
        <p class="max-w-md text-sm text-slate">
          Permanently delete your account and everything attached to it — applications, documents,
          interviews, and contacts. This can't be undone.
        </p>
        <Button
          label="Delete account"
          severity="danger"
          outlined
          type="button"
          @click="deleteDialogVisible = true"
        />
      </div>
    </section>
  </div>

  <DeleteAccountDialog v-model:visible="deleteDialogVisible" />
</template>
