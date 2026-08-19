<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { useNotificationsStore } from '@/stores/notifications'
import { useRouter } from 'vue-router'
import Avatar from 'primevue/avatar'
import Menu from 'primevue/menu'
import Tag from 'primevue/tag'
import type { MenuItem } from 'primevue/menuitem'
import NotificationBell from '@/components/notifications/NotificationBell.vue'

type NavItem = {
  name: string
  label: string
  to: string
  disabled?: boolean
}

const auth = useAuthStore()
const notifications = useNotificationsStore()
const router = useRouter()

const navItems: NavItem[] = [
  { name: 'dashboard', label: 'Dashboard', to: '/' },
  { name: 'applications', label: 'Applications', to: '/applications' },
  { name: 'interviews', label: 'Interviews', to: '/interviews' },
  { name: 'contacts', label: 'Contacts', to: '/contacts' },
  { name: 'documents', label: 'Documents', to: '/documents' },
  { name: 'analytics', label: 'Analytics', to: '/analytics' },
  { name: 'ai-tools', label: 'AI Tools', to: '/resume-analyses' },
]

// AppLayout stays mounted for the whole authenticated session (only its
// RouterView child swaps between pages), so one poll loop here covers the
// header bell on every page rather than each view starting its own.
onMounted(() => {
  notifications.startPolling()
})

onBeforeUnmount(() => {
  notifications.stopPolling()
})

async function handleLogout() {
  notifications.stopPolling()
  await auth.logout()
  await router.push({ name: 'login' })
}

// --- Account menu (bottom of nav) ---------------------------------------
// The sole entry point for both "Account settings" and "Log out" now —
// the old standalone header Log out button and Settings nav item are
// gone, so there's exactly one place to find either action.
const userInitials = computed(() => {
  const first = auth.user?.first_name?.[0] ?? ''
  const last = auth.user?.last_name?.[0] ?? ''
  return (first + last).toUpperCase() || undefined
})

const userMenu = ref<InstanceType<typeof Menu> | null>(null)

function toggleUserMenu(event: Event) {
  userMenu.value?.toggle(event)
}

// Every user is on the free tier for now (see AI rate limiting notes) —
// hardcoded rather than read off User, which has no plan/tier field yet.
const userMenuItems: MenuItem[] = [
  {
    label: 'Account settings',
    icon: 'pi pi-cog',
    command: () => router.push({ name: 'settings' }),
  },
  { separator: true },
  {
    label: 'Log out',
    icon: 'pi pi-sign-out',
    // `!` (Tailwind's important modifier) is required here, not optional —
    // PrimeVue's own itemLink class sets `color` directly on this same `<a>`
    // (see the #item slot below), and a plain utility class loses to that
    // on source order alone (same specificity). Same reasoning
    // WEBAPP_SUMMARY.md notes for ApplicationFormView's `.p-inputtext`
    // override.
    class: '!text-coral',
    command: handleLogout,
  },
]
</script>

<template>
  <div class="flex min-h-screen">
    <aside
      class="sticky top-0 flex h-screen w-60 shrink-0 flex-col bg-ink text-paper"
      aria-label="Primary navigation"
    >
      <div class="px-6 py-5">
        <span class="font-display text-lg font-bold tracking-tight">LwkApply</span>
      </div>
      <nav class="flex-1 space-y-1 overflow-y-auto px-3">
        <RouterLink
          v-for="item in navItems"
          :key="item.name"
          :to="item.to"
          :aria-disabled="item.disabled"
          class="flex items-center rounded-card px-3 py-2 text-sm font-medium transition-colors"
          :class="
            item.disabled
              ? 'pointer-events-none opacity-40'
              : 'hover:bg-white/10 aria-[current=page]:bg-teal aria-[current=page]:text-ink'
          "
        >
          {{ item.label }}
          <Tag v-if="item.disabled" value="Soon" severity="secondary" class="ml-auto text-xs" />
        </RouterLink>
      </nav>

      <div class="shrink-0 border-t border-white/10 p-3">
        <button
          type="button"
          class="flex w-full items-center gap-2 rounded-card px-2 py-2 text-left transition-colors hover:bg-white/10"
          aria-haspopup="true"
          aria-label="Account menu"
          @click="toggleUserMenu"
        >
          <Avatar
            :image="auth.user?.avatar_url ?? undefined"
            :label="auth.user?.avatar_url ? undefined : userInitials"
            icon="pi pi-user"
            shape="circle"
            class="shrink-0"
          />
          <span class="min-w-0 flex-1 truncate text-sm font-medium">
            {{ auth.user?.first_name }} {{ auth.user?.last_name }}
            <span class="font-normal text-paper/60">· Free</span>
          </span>
          <i class="pi pi-chevron-down shrink-0 text-xs text-paper/60" aria-hidden="true" />
        </button>
      </div>
    </aside>

    <Menu ref="userMenu" :model="userMenuItems" :popup="true">
      <template #item="{ item, props }">
        <a v-bind="props.action" :class="item.class">
          <span v-if="item.icon" v-bind="props.icon" />
          <span v-bind="props.label">{{ item.label }}</span>
        </a>
      </template>
    </Menu>

    <div class="flex min-w-0 flex-1 flex-col">
      <header class="flex items-center justify-end border-b border-slate/10 bg-white px-6 py-3">
        <NotificationBell />
      </header>

      <main class="min-w-0 flex-1 overflow-x-hidden p-6">
        <RouterView />
      </main>
    </div>
  </div>
</template>
