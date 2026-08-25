<script setup lang="ts">
import { computed, onMounted } from 'vue'
import { RouterLink } from 'vue-router'
import Button from 'primevue/button'

import { useAuthStore } from '@/stores/auth'
import { useAnalyticsStore } from '@/stores/analytics'
import { formatPercent } from '@/lib/analytics-ui'
import AnalyticsSection from '@/components/analytics/AnalyticsSection.vue'
import StatCard from '@/components/analytics/StatCard.vue'

const auth = useAuthStore()
const analytics = useAnalyticsStore()

onMounted(() => {
  analytics.fetchSummary().catch(() => {})
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
  </div>
</template>
