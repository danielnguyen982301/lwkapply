<script setup lang="ts">
import { onMounted, reactive } from 'vue'
import { RouterLink } from 'vue-router'
import { VueDraggable, type DraggableEvent } from 'vue-draggable-plus'
import Badge from 'primevue/badge'
import Button from 'primevue/button'
import Card from 'primevue/card'
import Message from 'primevue/message'
import ProgressSpinner from 'primevue/progressspinner'
import Select from 'primevue/select'

import { useApplicationsStore } from '@/stores/applications'
import ViewTabs from '@/components/applications/ViewTabs.vue'
import { applicationStatusOptions } from '@/lib/application-ui'
import {
  APPLICATION_STATUSES,
  APPLICATION_STATUS_LABELS,
  type Application,
  type ApplicationStatus,
} from '@/types/application'

const store = useApplicationsStore()
const statusSelectOptions = applicationStatusOptions()

const columnLists = reactive<Record<ApplicationStatus, Application[]>>(
  Object.fromEntries(APPLICATION_STATUSES.map((status) => [status, [] as Application[]])) as Record<
    ApplicationStatus,
    Application[]
  >,
)

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

async function onStatusSelect(app: Application, newStatus: ApplicationStatus) {
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
      <Button label="New Application" as="RouterLink" :to="{ name: 'application-new' }" />
    </div>

    <ViewTabs />

    <Message v-if="store.boardTruncated" severity="warn" :closable="false">
      Showing {{ store.boardItems.length }} of {{ store.boardTotal }} applications. The board
      doesn't yet page through everything — use the List view's search/filter to find the rest.
    </Message>

    <Message v-if="store.mutationStatus === 'error'" severity="error" :closable="false">
      {{ store.mutationError }}
    </Message>

    <Message v-if="store.boardStatus === 'error'" severity="error" :closable="false">
      <span>{{ store.boardError }}</span>
      <Button label="Retry" link size="small" class="ml-2" @click="loadBoard" />
    </Message>

    <div
      v-else-if="store.boardStatus === 'loading' && store.boardItems.length === 0"
      aria-live="polite"
      class="flex justify-center rounded-card border border-slate/10 bg-white p-10"
    >
      <ProgressSpinner aria-label="Loading board" />
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
      <Card
        v-for="status in APPLICATION_STATUSES"
        :key="status"
        class="flex w-64 flex-none flex-col"
        :pt="{
          body: { class: 'p-0 flex flex-col flex-1 min-h-0' },
          content: { class: 'p-0 flex flex-col flex-1 min-h-0' },
        }"
      >
        <template #title>
          <div class="flex items-center justify-between gap-2">
            <span class="text-sm">{{ APPLICATION_STATUS_LABELS[status] }}</span>
            <Badge :value="columnLists[status].length" severity="secondary" />
          </div>
        </template>
        <template #content>
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

            <Card
              v-for="app in columnLists[status]"
              :key="app.id"
              class="cursor-grab active:cursor-grabbing"
              :pt="{ body: { class: 'p-3' }, content: { class: 'p-0 space-y-1' } }"
            >
              <template #content>
                <RouterLink
                  :to="{ name: 'application-detail', params: { id: app.id } }"
                  class="no-drag font-medium text-ink hover:underline"
                >
                  {{ app.company }}
                </RouterLink>
                <p class="text-xs text-slate">{{ app.position }}</p>
                <p v-if="formatSalary(app.salary_min, app.salary_max)" class="text-xs text-slate">
                  {{ formatSalary(app.salary_min, app.salary_max) }}
                </p>

                <Select
                  :model-value="app.status"
                  :options="statusSelectOptions"
                  option-label="label"
                  option-value="value"
                  :aria-label="`Move ${app.company} — ${app.position} to a different status`"
                  class="no-drag mt-2 w-full"
                  size="small"
                  @update:model-value="onStatusSelect(app, $event as ApplicationStatus)"
                />
              </template>
            </Card>
          </VueDraggable>
        </template>
      </Card>
    </div>
  </div>
</template>
