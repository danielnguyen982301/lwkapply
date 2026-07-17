<script setup lang="ts">
import { onMounted, reactive } from 'vue'
import { VueDraggable, type DraggableEvent } from 'vue-draggable-plus'
import { useApplicationsStore } from '@/stores/applications'
import ViewTabs from '@/components/applications/ViewTabs.vue'
import {
  APPLICATION_STATUSES,
  APPLICATION_STATUS_LABELS,
  type Application,
  type ApplicationStatus,
} from '@/types/application'

const store = useApplicationsStore()

// Per-column arrays that VueDraggable owns directly via v-model — it
// splices items into/out of whichever array is bound to the column the
// user drags into, so this has to be a real mutable array per column, not
// a computed derived from store.boardItems.
const columnLists = reactive<Record<ApplicationStatus, Application[]>>(
  Object.fromEntries(APPLICATION_STATUSES.map((status) => [status, [] as Application[]])) as Record<
    ApplicationStatus,
    Application[]
  >,
)

// Re-derives every column from the store's last-known-good boardItems.
// Used both after a successful move (to reflect the server-confirmed
// state, since store.updateApplication replaces the item with a fresh
// object from the response) and after a failed one (to snap the card
// back to its original column).
function syncColumnsFromStore() {
  for (const status of APPLICATION_STATUSES) {
    columnLists[status] = store.boardItems.filter((app) => app.status === status)
  }
}

async function loadBoard() {
  await store.fetchBoard().catch(() => {})
  syncColumnsFromStore()
}

onMounted(loadBoard)

function formatSalary(min: number | null, max: number | null): string {
  if (min == null && max == null) return ''
  const fmt = (n: number) => `$${Math.round(n / 1000)}k`
  if (min != null && max != null) return min === max ? fmt(min) : `${fmt(min)}–${fmt(max)}`
  return fmt((min ?? max) as number)
}

/**
 * Fires when a card is dropped into a *different* column (same-column
 * reorders don't fire `add`, and card order isn't persisted anyway, so
 * there's nothing to do for those). VueDraggable has already spliced the
 * card into columnLists[status] by the time this runs — the visual move
 * is instant — this just persists it and re-syncs from the server
 * afterwards, whether it succeeded or not.
 */
async function handleAdd(status: ApplicationStatus, event: DraggableEvent<Application>) {
  const app = event.data
  if (!app || app.status === status) return
  try {
    await store.updateApplication(app.id, { status })
  } catch {
    // store.mutationError is already set and rendered below.
  } finally {
    syncColumnsFromStore()
  }
}

/**
 * The accessible, keyboard/screen-reader-operable way to move a card —
 * dragging (native or library-based) can't be driven without a pointer,
 * so this select is the real control, not a fallback bolted on after
 * the fact.
 */
async function onStatusSelect(app: Application, event: Event) {
  const newStatus = (event.target as HTMLSelectElement).value as ApplicationStatus
  if (newStatus === app.status) return
  try {
    await store.updateApplication(app.id, { status: newStatus })
  } catch {
    // store.mutationError is already set and rendered below.
  } finally {
    syncColumnsFromStore()
  }
}
</script>

<template>
  <div class="space-y-4">
    <div class="flex items-center justify-between">
      <h1 class="font-display text-xl font-semibold text-ink">Applications</h1>
      <RouterLink
        :to="{ name: 'application-new' }"
        class="rounded-card bg-teal px-4 py-2 text-sm font-medium text-white hover:bg-teal-dark"
      >
        New Application
      </RouterLink>
    </div>

    <ViewTabs />

    <div
      v-if="store.boardTruncated"
      class="rounded-card border border-amber/30 bg-amber/5 p-3 text-sm text-ink"
    >
      Showing {{ store.boardItems.length }} of {{ store.boardTotal }} applications. The board
      doesn't yet page through everything — use the List view's search/filter to find the rest.
    </div>

    <div
      v-if="store.mutationStatus === 'error'"
      role="alert"
      class="rounded-card border border-coral/30 bg-coral/5 p-3 text-sm text-coral"
    >
      {{ store.mutationError }}
    </div>

    <div
      v-if="store.boardStatus === 'error'"
      role="alert"
      class="rounded-card border border-coral/30 bg-coral/5 p-4 text-sm text-coral"
    >
      {{ store.boardError }}
      <button type="button" class="ml-2 underline" @click="loadBoard">Retry</button>
    </div>

    <div
      v-else-if="store.boardStatus === 'loading' && store.boardItems.length === 0"
      aria-live="polite"
      class="rounded-card border border-slate/10 bg-white p-10 text-center text-sm text-slate"
    >
      Loading board…
    </div>

    <div
      v-else-if="store.boardItems.length === 0"
      class="rounded-card border border-dashed border-slate/30 p-10 text-center"
    >
      <h2 class="font-display text-lg font-semibold text-ink">No applications yet</h2>
      <p class="mx-auto mt-2 max-w-sm text-sm text-slate">
        Once you save or apply to a role, it'll show up here as a card you can move through each
        stage of the process.
      </p>
    </div>

    <div
      v-else
      class="flex gap-4 overflow-x-auto pb-2"
      :aria-busy="store.boardStatus === 'loading'"
    >
      <div
        v-for="status in APPLICATION_STATUSES"
        :key="status"
        class="flex w-64 flex-none flex-col rounded-card border border-slate/10 bg-paper"
      >
        <div class="flex items-center justify-between border-b border-slate/10 px-3 py-2">
          <h2 class="text-sm font-semibold text-ink">{{ APPLICATION_STATUS_LABELS[status] }}</h2>
          <span class="text-xs text-slate">{{ columnLists[status].length }}</span>
        </div>

        <VueDraggable
          v-model="columnLists[status]"
          group="application-status"
          filter=".no-drag"
          :prevent-on-filter="false"
          ghost-class="opacity-40"
          class="flex min-h-[3rem] max-h-[65vh] flex-col gap-2 overflow-y-auto p-2"
          @add="handleAdd(status, $event)"
        >
          <p
            v-if="columnLists[status].length === 0"
            class="px-2 py-3 text-center text-xs text-slate"
          >
            No applications
          </p>

          <div
            v-for="app in columnLists[status]"
            :key="app.id"
            class="cursor-grab rounded-card border border-slate/10 bg-white p-3 shadow-sm active:cursor-grabbing"
          >
            <RouterLink
              :to="{ name: 'application-detail', params: { id: app.id } }"
              class="no-drag font-medium text-ink hover:underline"
            >
              {{ app.company }}
            </RouterLink>
            <p class="text-xs text-slate">{{ app.position }}</p>
            <p v-if="formatSalary(app.salary_min, app.salary_max)" class="mt-1 text-xs text-slate">
              {{ formatSalary(app.salary_min, app.salary_max) }}
            </p>

            <label :for="`status-${app.id}`" class="sr-only">
              Move {{ app.company }} — {{ app.position }} to a different status
            </label>
            <select
              :id="`status-${app.id}`"
              :value="app.status"
              class="no-drag mt-2 w-full rounded-card border border-slate/20 bg-white px-2 py-1 text-xs text-ink focus:border-teal"
              @change="onStatusSelect(app, $event)"
            >
              <option v-for="s in APPLICATION_STATUSES" :key="s" :value="s">
                {{ APPLICATION_STATUS_LABELS[s] }}
              </option>
            </select>
          </div>
        </VueDraggable>
      </div>
    </div>
  </div>
</template>
