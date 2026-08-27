<script setup lang="ts">
import { computed, onMounted } from 'vue'
import Chart from 'primevue/chart'
import SelectButton from 'primevue/selectbutton'

import { useAnalyticsStore } from '@/stores/analytics'
import AnalyticsSection from '@/components/analytics/AnalyticsSection.vue'
import StatCard from '@/components/analytics/StatCard.vue'
import {
  formatPercent,
  funnelStageColor,
  funnelStageLabel,
  INTERVIEW_RESULT_COLORS,
  INTERVIEW_RESULT_LABELS,
  INTERVIEW_RESULT_ORDER,
} from '@/lib/analytics-ui'

const store = useAnalyticsStore()

onMounted(() => {
  store.fetchAll()
})

// --- Overview cards ---------------------------------------------------

const summaryCards = computed(() => {
  const s = store.summary
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

// --- Pipeline (funnel) --------------------------------------------------

const funnelChartData = computed(() => {
  const stages = store.funnel?.stages ?? []
  return {
    labels: stages.map((s) => funnelStageLabel(s.status)),
    datasets: [
      {
        data: stages.map((s) => s.count),
        backgroundColor: stages.map((s) => funnelStageColor(s.status)),
        borderRadius: 4,
      },
    ],
  }
})

const funnelChartOptions = {
  indexAxis: 'y' as const,
  plugins: { legend: { display: false } },
  scales: {
    x: { ticks: { precision: 0 }, grid: { display: false } },
    y: { grid: { display: false } },
  },
  maintainAspectRatio: false,
}

const offRamps = computed(() => store.funnel?.off_ramps ?? [])

// --- Interview outcomes ---------------------------------------------------

const interviewChartData = computed(() => {
  const byResult = store.interviews?.by_result
  if (!byResult) return { labels: [], datasets: [{ data: [] }] }
  return {
    labels: INTERVIEW_RESULT_ORDER.map((key) => INTERVIEW_RESULT_LABELS[key]),
    datasets: [
      {
        data: INTERVIEW_RESULT_ORDER.map((key) => byResult[key]),
        backgroundColor: INTERVIEW_RESULT_ORDER.map((key) => INTERVIEW_RESULT_COLORS[key]),
      },
    ],
  }
})

const interviewChartOptions = {
  plugins: { legend: { position: 'bottom' as const, labels: { boxWidth: 10 } } },
  maintainAspectRatio: false,
}

// --- Activity ---------------------------------------------------------------

const MONTH_OPTIONS = [
  { label: '3 mo', value: 3 },
  { label: '6 mo', value: 6 },
  { label: '12 mo', value: 12 },
]

function onMonthsChange(months: number) {
  // SelectButton can emit null if allow-empty were true - it isn't, but
  // guard anyway rather than firing a request with months=null.
  if (months) store.fetchActivity(months).catch(() => {})
}

const activityChartData = computed(() => {
  const buckets = store.activity?.buckets ?? []
  return {
    labels: buckets.map((b) => b.period),
    datasets: [
      {
        label: 'Applications',
        data: buckets.map((b) => b.applications_created),
        backgroundColor: '#2A9D8F',
        borderRadius: 4,
      },
    ],
  }
})

const activityChartOptions = {
  plugins: { legend: { display: false } },
  scales: {
    y: { ticks: { precision: 0 }, grid: { color: '#EEF0F3' } },
    x: { grid: { display: false } },
  },
  maintainAspectRatio: false,
}
</script>

<template>
  <div class="space-y-6">
    <div>
      <h1 class="font-display text-xl font-semibold text-ink">Analytics</h1>
      <p class="mt-1 max-w-2xl text-sm text-slate">
        A snapshot of your job search right now, not a full history — see each section's note for
        exactly what it does and doesn't track.
      </p>
    </div>

    <AnalyticsSection
      title="Overview"
      :status="store.summaryStatus"
      :error="store.summaryError"
      :has-data="!!store.summary"
      @retry="store.fetchSummary().catch(() => {})"
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
    </AnalyticsSection>

    <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
      <AnalyticsSection
        title="Pipeline"
        :status="store.funnelStatus"
        :error="store.funnelError"
        :has-data="!!store.funnel"
        @retry="store.fetchFunnel().catch(() => {})"
      >
        <div
          v-if="store.funnel && store.funnel.total_applications === 0"
          class="py-6 text-center text-sm text-slate"
        >
          No applications yet — your pipeline will show up here once you add one.
        </div>
        <template v-else>
          <div style="height: 260px">
            <Chart type="bar" :data="funnelChartData" :options="funnelChartOptions" />
          </div>
          <p class="mt-3 text-xs text-slate">
            Current status of every application, saved through accepted — not a lifetime funnel. An
            application that reached "Interviewing" before being rejected counts once, under
            Rejected below, not under Interviewing.
          </p>
          <div
            v-if="offRamps.length"
            class="mt-3 flex flex-wrap gap-4 border-t border-slate/10 pt-3 text-sm"
          >
            <span v-for="stage in offRamps" :key="stage.status" class="text-slate">
              {{ funnelStageLabel(stage.status) }}:
              <span class="font-medium text-ink">{{ stage.count }}</span>
            </span>
          </div>
        </template>
      </AnalyticsSection>

      <AnalyticsSection
        title="Interview Outcomes"
        :status="store.interviewsStatus"
        :error="store.interviewsError"
        :has-data="!!store.interviews"
        @retry="store.fetchInterviews().catch(() => {})"
      >
        <div
          v-if="store.interviews && store.interviews.total_interviews === 0"
          class="py-6 text-center text-sm text-slate"
        >
          No interviews logged yet.
        </div>
        <template v-else>
          <div style="height: 220px">
            <Chart type="doughnut" :data="interviewChartData" :options="interviewChartOptions" />
          </div>
          <p class="mt-3 text-sm text-slate">
            Pass rate:
            <span class="font-medium text-ink">{{
              formatPercent(store.interviews?.pass_rate ?? null)
            }}</span>
            <span class="text-xs"> (passed ÷ passed+failed, excludes pending/cancelled)</span>
          </p>
        </template>
      </AnalyticsSection>
    </div>

    <AnalyticsSection
      title="Activity"
      :status="store.activityStatus"
      :error="store.activityError"
      :has-data="!!store.activity"
      @retry="store.fetchActivity().catch(() => {})"
    >
      <div class="mb-3 flex items-center justify-between">
        <p class="text-xs text-slate">Applications created per month (UTC)</p>
        <SelectButton
          :model-value="store.activityMonths"
          :options="MONTH_OPTIONS"
          option-label="label"
          option-value="value"
          :allow-empty="false"
          aria-label="Number of months to show"
          @update:model-value="onMonthsChange"
        />
      </div>
      <div style="height: 240px">
        <Chart type="bar" :data="activityChartData" :options="activityChartOptions" />
      </div>
    </AnalyticsSection>
  </div>
</template>
