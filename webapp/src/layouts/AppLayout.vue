<script setup lang="ts">
import { useAuthStore } from "@/stores/auth";
import { useRouter } from "vue-router";

const auth = useAuthStore();
const router = useRouter();

const navItems = [
  { name: "dashboard", label: "Dashboard", to: "/" },
  // Remaining items are placeholders until their views land later in
  // Phase 2 (Applications/Kanban) and Phase 4 (Interviews/Contacts).
  { name: "applications", label: "Applications", to: "/", disabled: true },
  { name: "interviews", label: "Interviews", to: "/", disabled: true },
  { name: "contacts", label: "Contacts", to: "/", disabled: true },
  { name: "documents", label: "Documents", to: "/", disabled: true },
];

async function handleLogout() {
  auth.logout();
  await router.push({ name: "login" });
}
</script>

<template>
  <div class="flex min-h-screen">
    <aside
      class="w-60 shrink-0 bg-ink text-paper flex flex-col"
      aria-label="Primary navigation"
    >
      <div class="px-6 py-5">
        <span class="font-display text-lg font-bold tracking-tight"
          >LwkApply</span
        >
      </div>
      <nav class="flex-1 px-3 space-y-1">
        <RouterLink
          v-for="item in navItems"
          :key="item.name"
          :to="item.to"
          :aria-disabled="item.disabled"
          class="flex items-center rounded-card px-3 py-2 text-sm font-medium transition-colors"
          :class="
            item.disabled
              ? 'opacity-40 pointer-events-none'
              : 'hover:bg-white/10 aria-[current=page]:bg-teal aria-[current=page]:text-ink'
          "
        >
          {{ item.label }}
          <span v-if="item.disabled" class="ml-auto text-xs text-slate-light"
            >Soon</span
          >
        </RouterLink>
      </nav>
    </aside>

    <div class="flex-1 flex flex-col">
      <header
        class="flex items-center justify-between border-b border-slate/10 bg-white px-6 py-3"
      >
        <h1 class="font-display text-base font-medium">
          Welcome back{{ auth.user ? `, ${auth.user.first_name}` : "" }}
        </h1>
        <button
          type="button"
          class="text-sm font-medium text-slate hover:text-ink"
          @click="handleLogout"
        >
          Log out
        </button>
      </header>

      <main class="flex-1 p-6">
        <RouterView />
      </main>
    </div>
  </div>
</template>
