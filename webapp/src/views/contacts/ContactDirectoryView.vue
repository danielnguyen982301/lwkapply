<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import Button from 'primevue/button'
import Column from 'primevue/column'
import DataTable from 'primevue/datatable'
import IconField from 'primevue/iconfield'
import InputIcon from 'primevue/inputicon'
import InputText from 'primevue/inputtext'
import Message from 'primevue/message'
import Paginator from 'primevue/paginator'
import ProgressSpinner from 'primevue/progressspinner'
import { useConfirm } from 'primevue/useconfirm'

import { useContactsStore } from '@/stores/contacts'
import TruncatedText from '@/components/common/TruncatedText.vue'
import ContactFormDialog from '@/components/contacts/ContactFormDialog.vue'
import { tooltip } from '@/lib/tooltip'
import { formatDate } from '@/lib/date-utils'
import type { Contact } from '@/types/contact'

// The user's whole contact directory - a contact is a top-level, standalone
// resource now (see stores/contacts.ts / BACKEND_SUMMARY.md's "A note on
// Contact / ApplicationContact"), so add/edit/delete all live here rather
// than only on an application's Contacts panel. Attaching an already-added
// contact to a specific application still happens from that application's
// detail page (components/applications/ContactsPanel.vue).
const store = useContactsStore()
const confirm = useConfirm()

// Debounced text search, same shape as DocumentDirectoryView.vue's search
// box - the store itself stays synchronous (fetch-on-call), debouncing is
// purely a view-level concern so it doesn't leak into every other caller
// of fetchContacts().
const searchInput = ref(store.search)
let debounceTimer: ReturnType<typeof setTimeout> | undefined

function handleSearchInput() {
  if (debounceTimer) clearTimeout(debounceTimer)
  debounceTimer = setTimeout(() => {
    store.setSearch(searchInput.value).catch(() => {})
  }, 300)
}

onBeforeUnmount(() => {
  if (debounceTimer) clearTimeout(debounceTimer)
})

const hasActiveSearch = computed(() => store.search !== '')

function clearSearch() {
  searchInput.value = ''
  if (debounceTimer) clearTimeout(debounceTimer)
  store.fetchContacts({ search: null, page: 1 }).catch(() => {})
}

function loadContacts(page = 1) {
  store.fetchContacts({ page }).catch(() => {})
}

onMounted(() => {
  loadContacts()
})

const paginatorFirst = computed(() => (store.page - 1) * store.pageSize)

async function onPageChange(event: { first: number; rows: number }) {
  await store.fetchContacts({ page: Math.floor(event.first / event.rows) + 1 }).catch(() => {})
}

// --- Add / edit dialog ---------------------------------------------------
// Extracted into components/contacts/ so ContactsPanel.vue (application-
// scoped) can reuse the same add/edit UX - see that file for why the
// directory store owns both, regardless of which view opened the dialog.
const dialogVisible = ref(false)
const editingContact = ref<Contact | null>(null)

function openAddDialog() {
  editingContact.value = null
  dialogVisible.value = true
}

function openEditDialog(contact: Contact) {
  editingContact.value = contact
  dialogVisible.value = true
}

function confirmDelete(contact: Contact) {
  confirm.require({
    message: `Permanently delete ${contact.name}? This removes them from every application they're attached to, and can't be undone.`,
    header: 'Confirm deletion',
    icon: 'pi pi-exclamation-triangle',
    rejectLabel: 'Cancel',
    acceptLabel: 'Delete',
    rejectProps: { label: 'Cancel', severity: 'secondary', outlined: true },
    acceptProps: { label: 'Delete', severity: 'danger' },
    accept: () => {
      store.deleteContact(contact.id).catch(() => {})
    },
  })
}
</script>

<template>
  <div class="space-y-4">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <h1 class="font-display text-xl font-semibold text-ink">Contacts</h1>
      <Button label="Add contact" icon="pi pi-plus" size="small" @click="openAddDialog" />
    </div>

    <p class="max-w-2xl text-sm text-slate">
      Every recruiter, hiring manager, and interviewer you've added, independent of any application.
      Attach a contact to as many applications as you like from that application's detail page.
    </p>

    <div class="flex flex-wrap items-center gap-3">
      <IconField class="min-w-[220px] max-w-sm flex-1">
        <InputIcon class="pi pi-search" />
        <InputText
          v-model="searchInput"
          type="search"
          placeholder="Search by name…"
          class="w-full"
          aria-label="Search contacts by name"
          @input="handleSearchInput"
        />
      </IconField>
    </div>

    <Message v-if="store.listStatus === 'error'" severity="error" :closable="false">
      <span>{{ store.listError }}</span>
      <Button label="Retry" link size="small" class="ml-2" @click="loadContacts(store.page)" />
    </Message>

    <div
      v-else-if="store.listStatus === 'loading' && store.items.length === 0"
      aria-live="polite"
      class="flex justify-center rounded-card border border-slate/10 bg-surface p-10"
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
        <template v-if="hasActiveSearch">Try a different name.</template>
        <template v-else>Add a recruiter, hiring manager, or interviewer to get started.</template>
      </p>
      <Button v-if="hasActiveSearch" label="Clear search" link class="mt-4" @click="clearSearch" />
      <Button v-else label="Add contact" link class="mt-4" @click="openAddDialog" />
    </div>

    <div v-else class="space-y-0">
      <div class="overflow-x-auto">
        <DataTable
          :value="store.items"
          :loading="store.listStatus === 'loading'"
          size="small"
          striped-rows
          aria-label="All your contacts"
        >
          <Column header="Name">
            <template #body="{ data }: { data: Contact }">
              <TruncatedText :text="data.name" max-width="12rem" class="font-medium text-ink" />
            </template>
          </Column>
          <Column header="Title">
            <template #body="{ data }: { data: Contact }">
              <TruncatedText :text="data.title" max-width="10rem" />
            </template>
          </Column>
          <Column header="Email">
            <template #body="{ data }: { data: Contact }">
              <a
                v-if="data.email"
                :href="`mailto:${data.email}`"
                class="block max-w-[14rem] truncate text-slate hover:text-ink hover:underline"
                :title="data.email"
              >
                {{ data.email }}
              </a>
              <span v-else>—</span>
            </template>
          </Column>
          <Column header="LinkedIn">
            <template #body="{ data }: { data: Contact }">
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
          <Column header="Added">
            <template #body="{ data }: { data: Contact }">
              {{ formatDate(data.created_at) }}
            </template>
          </Column>
          <Column header="" style="width: 7rem">
            <template #body="{ data }: { data: Contact }">
              <div class="flex justify-end gap-1">
                <Button
                  v-tooltip.bottom="tooltip('Edit contact')"
                  icon="pi pi-pencil"
                  aria-label="Edit contact"
                  link
                  size="small"
                  @click="openEditDialog(data)"
                />
                <Button
                  v-tooltip.bottom="tooltip('Delete contact')"
                  icon="pi pi-trash"
                  aria-label="Delete contact"
                  text
                  severity="danger"
                  size="small"
                  @click="confirmDelete(data)"
                />
              </div>
            </template>
          </Column>
        </DataTable>
      </div>

      <Paginator
        :rows="store.pageSize"
        :total-records="store.total"
        :first="paginatorFirst"
        template="FirstPageLink PrevPageLink CurrentPageReport NextPageLink LastPageLink"
        current-page-report-template="Page {currentPage} of {totalPages}"
        class="border-x border-b border-slate/10 bg-surface"
        @page="onPageChange"
      />
    </div>
  </div>

  <ContactFormDialog v-model:visible="dialogVisible" :contact="editingContact" />
</template>
