<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import Badge from 'primevue/badge'
import Button from 'primevue/button'
import Message from 'primevue/message'
import Popover from 'primevue/popover'
import ProgressSpinner from 'primevue/progressspinner'

import { useNotificationsStore } from '@/stores/notifications'
import { formatDateTime } from '@/lib/date-utils'
import type { Notification } from '@/types/notification'

// Header bell icon — AppLayout.vue starts/stops the store's unread-count
// poll for the whole authenticated session; this component only owns the
// popover's own on-open fetch of the short recent-notifications list (see
// stores/notifications.ts's BELL_PAGE_SIZE — there's no separate "view all
// notifications" page yet, nothing in the plan calls for one).
const store = useNotificationsStore()
const router = useRouter()
const popover = ref<InstanceType<typeof Popover> | null>(null)

function toggle(event: Event) {
  popover.value?.toggle(event)
  if (!store.items.length) {
    store.fetchNotifications().catch(() => {})
  }
}

async function handleNotificationClick(notification: Notification) {
  if (!notification.read_at) {
    store.markRead(notification.id).catch(() => {})
  }
  if (notification.application_id) {
    popover.value?.hide()
    await router.push({ name: 'application-detail', params: { id: notification.application_id } })
  }
}

function handleMarkAllRead() {
  store.markAllRead().catch(() => {})
}
</script>

<template>
  <span class="relative inline-flex">
    <Button
      icon="pi pi-bell"
      severity="secondary"
      text
      rounded
      aria-label="Notifications"
      @click="toggle"
    />
    <Badge
      v-if="store.unreadCount > 0"
      :value="store.unreadCount > 99 ? '99+' : store.unreadCount"
      severity="danger"
      class="pointer-events-none absolute -right-1 -top-1"
    />
  </span>

  <Popover ref="popover" class="w-80">
    <div class="flex items-center justify-between px-1 pb-2">
      <h2 class="font-display text-sm font-semibold text-ink">Notifications</h2>
      <Button
        v-if="store.unreadCount > 0"
        label="Mark all read"
        link
        size="small"
        :loading="store.mutationStatus === 'loading'"
        @click="handleMarkAllRead"
      />
    </div>

    <Message v-if="store.listStatus === 'error'" severity="error" :closable="false">
      {{ store.listError }}
    </Message>

    <div
      v-else-if="store.listStatus === 'loading' && store.items.length === 0"
      class="flex justify-center py-6"
    >
      <ProgressSpinner aria-label="Loading notifications" style="width: 2rem; height: 2rem" />
    </div>

    <p v-else-if="store.items.length === 0" class="px-1 py-4 text-center text-sm text-slate">
      You're all caught up.
    </p>

    <ul v-else class="-mx-1 max-h-96 divide-y divide-slate/10 overflow-y-auto">
      <li v-for="notification in store.items" :key="notification.id">
        <button
          type="button"
          class="flex w-full flex-col gap-0.5 rounded-card px-2 py-2 text-left transition-colors hover:bg-paper"
          :class="!notification.read_at && 'bg-teal/5'"
          @click="handleNotificationClick(notification)"
        >
          <span class="flex items-start justify-between gap-2">
            <span class="text-sm font-medium text-ink">{{ notification.title }}</span>
            <span v-if="!notification.read_at" class="mt-1 size-2 shrink-0 rounded-full bg-teal" />
          </span>
          <span class="text-sm text-slate">{{ notification.body }}</span>
          <span class="text-xs text-slate/70">{{ formatDateTime(notification.created_at) }}</span>
        </button>
      </li>
    </ul>
  </Popover>
</template>
