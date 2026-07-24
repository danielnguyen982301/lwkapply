<script setup lang="ts">
import { useAuthStore } from '@/stores/auth'
import { useRouter } from 'vue-router'
import Button from 'primevue/button'
import Tag from 'primevue/tag'

type NavItem = {
  name: string
  label: string
  to: string
  disabled?: boolean
}

const auth = useAuthStore()
const router = useRouter()

const navItems: NavItem[] = [
  { name: 'dashboard', label: 'Dashboard', to: '/' },
  { name: 'applications', label: 'Applications', to: '/applications' },
  { name: 'interviews', label: 'Interviews', to: '/interviews' },
  { name: 'contacts', label: 'Contacts', to: '/contacts' },
  { name: 'documents', label: 'Documents', to: '/documents' },
]

async function handleLogout() {
  await auth.logout()
  await router.push({ name: 'login' })
}
</script>

<template>
  <div class="flex min-h-screen">
    <aside class="flex w-60 shrink-0 flex-col bg-ink text-paper" aria-label="Primary navigation">
      <div class="px-6 py-5">
        <span class="font-display text-lg font-bold tracking-tight">LwkApply</span>
      </div>
      <nav class="flex-1 space-y-1 px-3">
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
    </aside>

    <div class="flex min-w-0 flex-1 flex-col">
      <header class="flex items-center justify-between border-b border-slate/10 bg-white px-6 py-3">
        <h1 class="font-display text-base font-medium">
          Welcome back{{ auth.user ? `, ${auth.user.first_name}` : '' }}
        </h1>
        <Button label="Log out" link size="small" @click="handleLogout" />
      </header>

      <main class="min-w-0 flex-1 overflow-x-hidden p-6">
        <RouterView />
      </main>
    </div>
  </div>
</template>
