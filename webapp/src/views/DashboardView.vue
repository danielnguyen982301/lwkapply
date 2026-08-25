<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { RouterLink } from 'vue-router'
import Button from 'primevue/button'

import { useAuthStore } from '@/stores/auth'
import { useAnalyticsStore } from '@/stores/analytics'
import { useApplicationsStore } from '@/stores/applications'
import { extractErrorMessage } from '@/lib/api'
import { formatPercent } from '@/lib/analytics-ui'
import { formatDateTime } from '@/lib/date-utils'
import AnalyticsSection from '@/components/analytics/AnalyticsSection.vue'
import StatCard from '@/components/analytics/StatCard.vue'
import ApplicationStatusTag from '@/components/applications/ApplicationStatusTag.vue'
import type { Application } from '@/types/application'

const auth = useAuthStore()
const analytics = useAnalyticsStore()
const applicationsStore = useApplicationsStore()

const RECENT_LIMIT = 5

// Isolated fetch, same reasoning as ApplicationPicker.vue's use of
// searchApplications() - a plain local ref rather than the applications
// store's shared `items`/`listStatus`, so landing on the dashboard doesn't
// clobber whatever page/filters the Applications List view already had.
const recent = ref<Application[]>([])
const recentStatus = ref<'idle' | 'loading' | 'error'>('idle')
const recentError = ref<string | null>(null)

async function loadRecent() {
  recentStatus.value = 'loading'
  recentError.value = null
  try {
    // No query -> every application, already ordered most-recently-updated
    // first by the backend; just take the top slice for a "recent" list.
    const items = await applicationsStore.searchApplications('')
    recent.value = items.slice(0, RECENT_LIMIT)
    recentStatus.value = 'idle'
  } catch (err) {
    recentStatus.value = 'error'
    recentError.value = extractErrorMessage(err)
  }
}

onMounted(() => {
  analytics.fetchSummary().catch(() => {})
  loadRecent()
})

// Same shape as AnalyticsDashboardView's summaryCards - deliberately not
// shared/extracted, since the two views are free to diverge (e.g. this one
// dropping a card) without that becoming a breaking change to the other.
const summaryCards = computed(() => {
  const s = analytics.summary
  return [
    { label: 'Total Applications', value: s ? String(s.total_applications) : '—' },
    { label: 'Active', value: s ? String(s.active_applications) : '—' },
    { label: 'Offers Received', value: s ? String(s.offers_received) : '—' },
    { label: 'Interviews Scheduled', value: s ? String(s.interviews_scheduled) : '—' },
    {
      label: 'Response Rate',
      value: s ? formatPercent(s.response_rate) : '—',
      hint: 'Moved past "applied"',
    },
  ]
})
</script>

<template>
  <div class="space-y-6">
    <div class="flex items-center justify-between gap-3">
      <div>
        <h1 class="font-display text-xl font-semibold text-ink">
          Welcome back{{ auth.user?.first_name ? `, ${auth.user.first_name}` : '' }}
        </h1>
        <p class="mt-1 text-sm text-slate">Here's where your job search stands.</p>
      </div>
      <Button label="New Application" as="RouterLink" :to="{ name: 'application-new' }" />
    </div>

    <AnalyticsSection
      title="Overview"
      :status="analytics.summaryStatus"
      :error="analytics.summaryError"
      :has-data="!!analytics.summary"
      @retry="analytics.fetchSummary().catch(() => {})"
    >
      <div class="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
        <StatCard
          v-for="card in summaryCards"
          :key="card.label"
          :label="card.label"
          :value="card.value"
          :hint="card.hint"
        />
      </div>
      <p class="mt-3 text-right">
        <RouterLink :to="{ name: 'analytics' }" class="text-sm text-teal-dark hover:underline">
          View full analytics →
        </RouterLink>
      </p>
    </AnalyticsSection>

    <AnalyticsSection
      title="Recent Applications"
      :status="recentStatus"
      :error="recentError"
      :has-data="recent.length > 0"
      @retry="loadRecent"
    >
      <div v-if="recent.length === 0" class="py-6 text-center">
        <p class="text-sm text-slate">Once you save or apply to a role, it'll show up here.</p>
        <Button
          label="Add your first application"
          link
          class="mt-1"
          as="RouterLink"
          :to="{ name: 'application-new' }"
        />
      </div>
      <template v-else>
        <ul class="divide-y divide-slate/10">
          <li v-for="app in recent" :key="app.id">
            <RouterLink
              :to="{ name: 'application-detail', params: { id: app.id } }"
              class="flex items-center justify-between gap-3 py-3 transition-colors hover:bg-paper"
            >
              <div class="min-w-0">
                <p class="truncate text-sm font-medium text-ink">{{ app.company }}</p>
                <p class="truncate text-sm text-slate">{{ app.position }}</p>
              </div>
              <div class="flex shrink-0 items-center gap-3">
                <span class="text-xs text-slate">{{ formatDateTime(app.updated_at) }}</span>
                <ApplicationStatusTag :status="app.status" />
              </div>
            </RouterLink>
          </li>
        </ul>
        <p class="mt-3 text-right">
          <RouterLink :to="{ name: 'applications' }" class="text-sm text-teal-dark hover:underline">
            View all applications →
          </RouterLink>
        </p>
      </template>
    </AnalyticsSection>
  </div>
</template>
