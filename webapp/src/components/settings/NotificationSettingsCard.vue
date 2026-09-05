<script setup lang="ts">
import { onMounted, ref, watch } from 'vue'
import Button from 'primevue/button'
import Message from 'primevue/message'
import ProgressSpinner from 'primevue/progressspinner'
import { toTypedSchema } from '@vee-validate/zod'
import z from 'zod'
import { useField, useForm } from 'vee-validate'

import { useUserSettingsStore } from '@/stores/userSettings'
import CustomInputNumber from '@/components/custom_form_fields/CustomInputNumber.vue'
import CustomToggleSwitch from '@/components/custom_form_fields/CustomToggleSwitch.vue'

const settingsStore = useUserSettingsStore()

const DEFAULT_REMINDER_LEAD_HOURS = 24

// A real vee-validate form now, not a pile of standalone booleans - this
// only has one number field today (reminder_lead_hours), but it won't
// stay that way as more preferences land here, and every one of them
// would otherwise need its own single-purpose ref. PATCH
// /users/me/settings applies every field uniformly via exclude_unset
// (no per-field side effect like ProfileSettingsCard.vue's
// timezone_is_manual), so unlike that form, there's no need to track
// which individual field changed - the whole form's own `meta.dirty`
// is enough to gate the Save button, and every submit just resends the
// full current state.
interface NotificationSettingsFormValues {
  notifications_enabled: boolean
  email_notifications_enabled: boolean
  push_notifications_enabled: boolean
  use_custom_reminder_lead_hours: boolean
  reminder_lead_hours: number
}

const notificationSettingsValidationSchema = toTypedSchema(
  z.object({
    notifications_enabled: z.boolean(),
    email_notifications_enabled: z.boolean(),
    push_notifications_enabled: z.boolean(),
    use_custom_reminder_lead_hours: z.boolean(),
    reminder_lead_hours: z.number().min(1).max(168),
  }),
)

const {
  handleSubmit: handleSettingsSubmit,
  meta: settingsMeta,
  resetForm: resetSettingsForm,
} = useForm<NotificationSettingsFormValues>({
  validationSchema: notificationSettingsValidationSchema,
  initialValues: {
    notifications_enabled: true,
    email_notifications_enabled: true,
    push_notifications_enabled: true,
    use_custom_reminder_lead_hours: false,
    reminder_lead_hours: DEFAULT_REMINDER_LEAD_HOURS,
  },
})

// Read directly (alongside the CustomToggleSwitch.vue below that also
// binds them) purely for template conditionals - disabling the
// email/push toggles, and showing the lead-time InputNumber. Same
// shared-field-state pattern ProfileSettingsCard.vue uses for
// auto_detect_timezone.
const { value: notificationsEnabled } = useField<boolean>('notifications_enabled')
const { value: useCustomReminderLeadHours } = useField<boolean>('use_custom_reminder_lead_hours')

watch(
  () => settingsStore.settings,
  (settings) => {
    if (!settings) return
    resetSettingsForm({
      values: {
        notifications_enabled: settings.notifications_enabled,
        email_notifications_enabled: settings.email_notifications_enabled,
        push_notifications_enabled: settings.push_notifications_enabled,
        use_custom_reminder_lead_hours: settings.reminder_lead_hours !== null,
        reminder_lead_hours: settings.reminder_lead_hours ?? DEFAULT_REMINDER_LEAD_HOURS,
      },
    })
  },
  { immediate: true },
)

onMounted(() => {
  settingsStore.fetchSettings().catch(() => {})
})

const settingsSuccess = ref(false)

const onSettingsSubmit = handleSettingsSubmit(async (formValues) => {
  settingsSuccess.value = false
  try {
    await settingsStore.updateSettings({
      notifications_enabled: formValues.notifications_enabled,
      email_notifications_enabled: formValues.email_notifications_enabled,
      push_notifications_enabled: formValues.push_notifications_enabled,
      reminder_lead_hours: formValues.use_custom_reminder_lead_hours
        ? formValues.reminder_lead_hours
        : null,
    })
    settingsSuccess.value = true
  } catch {
    // settingsStore.mutationError is already set and rendered below.
  }
})
</script>

<template>
  <section class="rounded-card border border-slate/10 bg-paper p-4">
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

    <form v-else class="mt-4 space-y-4" @submit.prevent="onSettingsSubmit">
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
        <CustomToggleSwitch name="notifications_enabled" aria-label="Enable notifications" />
      </div>

      <div
        class="flex items-center justify-between pl-1"
        :class="!notificationsEnabled && 'opacity-50'"
      >
        <div>
          <p class="text-sm font-medium text-ink">Email</p>
          <p class="text-sm text-slate">Send reminders by email.</p>
        </div>
        <CustomToggleSwitch
          name="email_notifications_enabled"
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
        <CustomToggleSwitch
          name="push_notifications_enabled"
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
          <CustomToggleSwitch
            name="use_custom_reminder_lead_hours"
            aria-label="Use a custom reminder lead time"
          />
        </div>
        <div v-if="useCustomReminderLeadHours" class="mt-3 flex items-center gap-2">
          <CustomInputNumber
            name="reminder_lead_hours"
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
          :disabled="!settingsMeta.dirty || settingsStore.mutationStatus === 'loading'"
        />
      </div>
    </form>
  </section>
</template>
