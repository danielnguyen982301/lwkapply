<script setup lang="ts">
import { ref } from 'vue'
import Button from 'primevue/button'

import ProfileSettingsCard from '@/components/settings/ProfileSettingsCard.vue'
import PasswordSettingsCard from '@/components/settings/PasswordSettingsCard.vue'
import NotificationSettingsCard from '@/components/settings/NotificationSettingsCard.vue'
import DeleteAccountDialog from '@/components/settings/DeleteAccountDialog.vue'

// Each section owns its own form state/store calls (see
// components/settings/*.vue) - this view is just the page shell and the
// section order, plus the one piece of state (the delete dialog) that
// doesn't belong to any single section.
const deleteDialogVisible = ref(false)
</script>

<template>
  <div class="max-w-2xl space-y-6">
    <div>
      <h1 class="font-display text-xl font-semibold text-ink">Account settings</h1>
      <p class="mt-1 text-sm text-slate">Manage your profile, password, and notifications.</p>
    </div>

    <ProfileSettingsCard />
    <PasswordSettingsCard />
    <NotificationSettingsCard />

    <!-- Danger zone -->
    <section class="rounded-card border border-coral/30 bg-surface p-4">
      <h2 class="font-display text-sm font-semibold text-coral">Danger zone</h2>
      <div class="mt-3 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <p class="max-w-md text-sm text-slate">
          Permanently delete your account and everything attached to it — applications, documents,
          interviews, and contacts. This can't be undone.
        </p>
        <Button
          label="Delete account"
          severity="danger"
          outlined
          type="button"
          class="self-start"
          @click="deleteDialogVisible = true"
        />
      </div>
    </section>
  </div>

  <DeleteAccountDialog v-model:visible="deleteDialogVisible" />
</template>
