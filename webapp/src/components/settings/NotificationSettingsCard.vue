<script setup lang="ts">
import { onMounted, ref, watch } from 'vue'
import Button from 'primevue/button'
import InputNumber from 'primevue/inputnumber'
import Message from 'primevue/message'
import ProgressSpinner from 'primevue/progressspinner'
import ToggleSwitch from 'primevue/toggleswitch'

import { useUserSettingsStore } from '@/stores/userSettings'

const settingsStore = useUserSettingsStore()

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
</script>

<template>
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
</template>
