<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { RouterLink } from 'vue-router'
import Button from 'primevue/button'
import Column from 'primevue/column'
import DataTable from 'primevue/datatable'
import IconField from 'primevue/iconfield'
import InputIcon from 'primevue/inputicon'
import InputText from 'primevue/inputtext'
import Message from 'primevue/message'
import Paginator from 'primevue/paginator'
import ProgressSpinner from 'primevue/progressspinner'

import { useContactDirectoryStore } from '@/stores/contactDirectory'
import ApplicationStatusTag from '@/components/applications/ApplicationStatusTag.vue'
import type { ContactWithApplication } from '@/types/contact'

const store = useContactDirectoryStore()

// Seeded from the store so returning to this view keeps whatever search
// was active, same convention as ApplicationListView.vue.
const searchInput = ref(store.search)

const hasActiveSearch = computed(() => !!store.search)

let debounceTimer: ReturnType<typeof setTimeout> | undefined

function handleSearchInput() {
  if (debounceTimer) clearTimeout(debounceTimer)
  debounceTimer = setTimeout(() => {
    store.setSearch(searchInput.value).catch(() => {})
  }, 350)
}

function clearSearch() {
  if (debounceTimer) clearTimeout(debounceTimer)
  searchInput.value = ''
  store.setSearch('').catch(() => {})
}

onBeforeUnmount(() => {
  if (debounceTimer) clearTimeout(debounceTimer)
})

onMounted(() => {
  store.fetchContacts().catch(() => {})
})

const paginatorFirst = computed(() => (store.page - 1) * store.pageSize)

async function onPageChange(event: { first: number; rows: number }) {
  const page = Math.floor(event.first / event.rows) + 1
  await store.fetchContacts({ page }).catch(() => {})
}
</script>

<template>
  <div class="space-y-4">
    <div class="flex items-center justify-between">
      <h1 class="font-display text-xl font-semibold text-ink">Contacts</h1>
    </div>

    <p class="max-w-2xl text-sm text-slate">
      Every recruiter, hiring manager, and interviewer across all your applications, in one place.
      To add or edit a contact, open the application they belong to.
    </p>

    <div class="flex flex-wrap items-center gap-3">
      <IconField class="min-w-[220px] max-w-sm flex-1">
        <InputIcon class="pi pi-search" />
        <InputText
          v-model="searchInput"
          type="search"
          placeholder="Search by name or company…"
          class="w-full"
          aria-label="Search contacts by name or company"
          @input="handleSearchInput"
        />
      </IconField>
    </div>

    <Message v-if="store.listStatus === 'error'" severity="error" :closable="false">
      <span>{{ store.listError }}</span>
      <Button
        label="Retry"
        link
        size="small"
        class="ml-2"
        @click="store.fetchContacts().catch(() => {})"
      />
    </Message>

    <div
      v-else-if="store.listStatus === 'loading' && store.items.length === 0"
      aria-live="polite"
      class="flex justify-center rounded-card border border-slate/10 bg-white p-10"
    >
      <ProgressSpinner aria-label="Loading contacts" />
    </div>

    <div
      v-else-if="store.items.length === 0"
      class="rounded-card border border-dashed border-slate/30 p-10 text-center"
    >
      <h2 class="font-display text-lg font-semibold text-ink">
        {{ hasActiveSearch ? 'No matching contacts' : 'No contacts yet' }}
      </h2>
      <p class="mx-auto mt-2 max-w-sm text-sm text-slate">
        <template v-if="hasActiveSearch">Try a different name or company.</template>
        <template v-else>
          Add recruiters, hiring managers, or interviewers from within an application's detail page
          and they'll show up here.
        </template>
      </p>
      <Button v-if="hasActiveSearch" label="Clear search" link class="mt-4" @click="clearSearch" />
    </div>

    <div v-else class="space-y-0">
      <DataTable
        :value="store.items"
        :loading="store.listStatus === 'loading'"
        size="small"
        striped-rows
        aria-label="All your contacts"
      >
        <Column field="name" header="Name">
          <template #body="{ data }: { data: ContactWithApplication }">
            <span class="font-medium text-ink">{{ data.name }}</span>
          </template>
        </Column>
        <Column header="Company">
          <template #body="{ data }: { data: ContactWithApplication }">
            <RouterLink
              :to="{ name: 'application-detail', params: { id: data.application.id } }"
              class="text-ink hover:underline"
            >
              {{ data.application.company }}
            </RouterLink>
          </template>
        </Column>
        <Column header="Position">
          <template #body="{ data }: { data: ContactWithApplication }">
            {{ data.application.position }}
          </template>
        </Column>
        <Column header="Status">
          <template #body="{ data }: { data: ContactWithApplication }">
            <ApplicationStatusTag :status="data.application.status" />
          </template>
        </Column>
        <Column field="title" header="Title">
          <template #body="{ data }: { data: ContactWithApplication }">
            {{ data.title ?? '—' }}
          </template>
        </Column>
        <Column header="Email">
          <template #body="{ data }: { data: ContactWithApplication }">
            <a
              v-if="data.email"
              :href="`mailto:${data.email}`"
              class="text-slate hover:text-ink hover:underline"
            >
              {{ data.email }}
            </a>
            <span v-else>—</span>
          </template>
        </Column>
        <Column header="LinkedIn">
          <template #body="{ data }: { data: ContactWithApplication }">
            <a
              v-if="data.linkedin_url"
              :href="data.linkedin_url"
              target="_blank"
              rel="noopener noreferrer"
              class="text-slate hover:text-ink hover:underline"
            >
              View profile
            </a>
            <span v-else>—</span>
          </template>
        </Column>
      </DataTable>

      <Paginator
        :rows="store.pageSize"
        :total-records="store.total"
        :first="paginatorFirst"
        template="FirstPageLink PrevPageLink CurrentPageReport NextPageLink LastPageLink"
        current-page-report-template="Page {currentPage} of {totalPages}"
        class="border-x border-b border-slate/10 bg-white"
        @page="onPageChange"
      />
    </div>
  </div>
</template>
