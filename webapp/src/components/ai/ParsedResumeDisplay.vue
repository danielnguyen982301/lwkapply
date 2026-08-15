<script setup lang="ts">
import Tag from 'primevue/tag'
import type { ParsedResume } from '@/types/ai'

defineProps<{ parsed: ParsedResume }>()
</script>

<template>
  <div class="space-y-4">
    <div v-if="parsed.full_name || parsed.email || parsed.phone">
      <p v-if="parsed.full_name" class="font-display text-base font-semibold text-ink">
        {{ parsed.full_name }}
      </p>
      <p v-if="parsed.email || parsed.phone" class="text-sm text-slate">
        <span v-if="parsed.email">{{ parsed.email }}</span>
        <span v-if="parsed.email && parsed.phone"> · </span>
        <span v-if="parsed.phone">{{ parsed.phone }}</span>
      </p>
    </div>

    <p v-if="parsed.summary" class="text-sm text-ink">{{ parsed.summary }}</p>

    <p v-if="parsed.total_years_experience !== null" class="text-sm text-slate">
      {{ parsed.total_years_experience }} years of experience
    </p>

    <div v-if="parsed.skills.length > 0">
      <h4 class="mb-2 text-sm font-semibold text-ink">Skills</h4>
      <div class="flex flex-wrap gap-2">
        <Tag v-for="skill in parsed.skills" :key="skill" :value="skill" severity="secondary" />
      </div>
    </div>

    <div v-if="parsed.work_experience.length > 0">
      <h4 class="mb-2 text-sm font-semibold text-ink">Work Experience</h4>
      <ul class="space-y-3">
        <li v-for="(job, index) in parsed.work_experience" :key="index">
          <p class="text-sm font-medium text-ink">{{ job.title }} · {{ job.company }}</p>
          <p v-if="job.start_date || job.end_date" class="text-xs text-slate">
            {{ job.start_date ?? '?' }} – {{ job.end_date ?? 'Present' }}
          </p>
          <p v-if="job.description" class="mt-1 text-sm text-slate">{{ job.description }}</p>
        </li>
      </ul>
    </div>

    <div v-if="parsed.education.length > 0">
      <h4 class="mb-2 text-sm font-semibold text-ink">Education</h4>
      <ul class="space-y-2">
        <li v-for="(school, index) in parsed.education" :key="index">
          <p class="text-sm font-medium text-ink">{{ school.institution }}</p>
          <p v-if="school.degree || school.field_of_study" class="text-xs text-slate">
            <span v-if="school.degree">{{ school.degree }}</span>
            <span v-if="school.degree && school.field_of_study">, </span>
            <span v-if="school.field_of_study">{{ school.field_of_study }}</span>
          </p>
          <p v-if="school.graduation_date" class="text-xs text-slate">
            {{ school.graduation_date }}
          </p>
        </li>
      </ul>
    </div>
  </div>
</template>
