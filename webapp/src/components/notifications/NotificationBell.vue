<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import Badge from 'primevue/badge'
import Button from 'primevue/button'
import Message from 'primevue/message'
import Popover from 'primevue/popover'
import ProgressSpinner from 'primevue/progressspinner'
import Tab from 'primevue/tab'
import TabList from 'primevue/tablist'
import Tabs from 'primevue/tabs'

import { useNotificationsStore } from '@/stores/notifications'
import { formatDateTime } from '@/lib/date-utils'
import type { Notification, NotificationStatusFilter } from '@/types/notification'

// Header bell icon — AppLayout.vue starts/stops the store's unread-count
// poll for the whole authenticated session; this component only owns the
// popover's own Unread/Read tabs and their infinite-scroll list.
const store = useNotificationsStore()
const router = useRouter()
const popover = ref<InstanceType<typeof Popover> | null>(null)
const listEl = ref<HTMLUListElement | null>(null)

function toggle(event: Event) {
  popover.value?.toggle(event)
  if (!store.items.length) {
    store.fetchNotifications().catch(() => {})
  }
}

function handleTabChange(value: string | number) {
  store.fetchNotifications(value as NotificationStatusFilter).catch(() => {})
}

// Fires on every scroll of the (short, fixed-height) list — cheap enough
// not to bother debouncing. 48px lead so the next page starts loading
// just before the user actually hits bottom, not exactly on it.
function handleListScroll() {
  const el = listEl.value
  if (!el) return
  const nearBottom = el.scrollTop + el.clientHeight >= el.scrollHeight - 48
  if (nearBottom) {
    store.loadMore().catch(() => {})
  }
}

async function handleNotificationClick(notification: Notification) {
  if (!notification.read_at) {
    store.markRead(notification.id).catch(() => {})
  }
  if (notification.application_id) {
    // Deliberately doesn't close the popover - navigating to check one
    // notification shouldn't lose your place in the list underneath it.
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
    <div class="px-1 pb-2">
      <Tabs :value="store.activeStatus" class="w-full" @update:value="handleTabChange">
        <TabList class="w-full">
          <Tab value="unread" class="flex-1 justify-center">Unread</Tab>
          <Tab value="read" class="flex-1 justify-center">Read</Tab>
        </TabList>
      </Tabs>
      <div
        v-if="store.activeStatus === 'unread' && store.unreadCount > 0"
        class="flex justify-end pt-2"
      >
        <Button
          label="Mark all read"
          link
          size="small"
          :loading="store.mutationStatus === 'loading'"
          @click="handleMarkAllRead"
        />
      </div>
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
      {{ store.activeStatus === 'unread' ? "You're all caught up." : 'No read notifications yet.' }}
    </p>

    <ul
      v-else
      ref="listEl"
      class="-mx-1 max-h-96 divide-y divide-slate/10 overflow-y-auto"
      @scroll="handleListScroll"
    >
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

      <li v-if="store.loadMoreStatus === 'loading'" class="flex justify-center py-3">
        <ProgressSpinner
          aria-label="Loading more notifications"
          style="width: 1.5rem; height: 1.5rem"
        />
      </li>
      <li v-else-if="store.loadMoreStatus === 'error'" class="px-2 py-3 text-center">
        <span class="text-xs text-coral">{{ store.loadMoreError }}</span>
        <Button
          label="Retry"
          link
          size="small"
          class="ml-1"
          @click="store.loadMore().catch(() => {})"
        />
      </li>
    </ul>
  </Popover>
</template>
