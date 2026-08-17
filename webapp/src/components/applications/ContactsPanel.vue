<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref, watch } from 'vue'
import Button from 'primevue/button'
import Card from 'primevue/card'
import Message from 'primevue/message'
import ProgressSpinner from 'primevue/progressspinner'
import { useConfirm } from 'primevue/useconfirm'

import { tooltip } from '@/lib/tooltip'
import { useContactsStore } from '@/stores/contacts'
import ContactFormDialog from '@/components/contacts/ContactFormDialog.vue'
import type { Contact } from '@/types/contact'

const props = defineProps<{ applicationId: string }>()

const store = useContactsStore()
const confirm = useConfirm()

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
    message: `Remove ${contact.name} from this application's contacts? This can't be undone.`,
    header: 'Confirm removal',
    icon: 'pi pi-exclamation-triangle',
    rejectLabel: 'Cancel',
    acceptLabel: 'Remove',
    rejectProps: { label: 'Cancel', severity: 'secondary', outlined: true },
    acceptProps: { label: 'Remove', severity: 'danger' },
    accept: () => {
      store.deleteContact(props.applicationId, contact.id).catch(() => {})
    },
  })
}

function loadContacts() {
  store.fetchContacts(props.applicationId).catch(() => {})
}

onMounted(loadContacts)

watch(
  () => props.applicationId,
  (newId, oldId) => {
    if (newId && newId !== oldId) loadContacts()
  },
)

onBeforeUnmount(() => {
  store.reset()
})
</script>

<template>
  <Card>
    <template #content>
      <div class="space-y-4">
        <div class="flex items-center justify-between">
          <h2 class="font-display text-lg font-semibold text-ink">Contacts</h2>
          <Button label="Add contact" icon="pi pi-plus" size="small" @click="openAddDialog" />
        </div>

        <Message v-if="store.mutationStatus === 'error'" severity="error" :closable="false">
          {{ store.mutationError }}
        </Message>

        <Message v-if="store.listStatus === 'error'" severity="error" :closable="false">
          <span>{{ store.listError }}</span>
          <Button label="Retry" link size="small" class="ml-2" @click="loadContacts" />
        </Message>

        <div
          v-else-if="store.listStatus === 'loading' && store.items.length === 0"
          aria-live="polite"
          class="flex justify-center py-8"
        >
          <ProgressSpinner aria-label="Loading contacts" style="width: 2rem; height: 2rem" />
        </div>

        <div
          v-else-if="store.items.length === 0"
          class="rounded-card border border-dashed border-slate/30 p-6 text-center"
        >
          <p class="text-sm text-slate">
            No contacts yet. Add recruiters, hiring managers, or interviewers tied to this
            application.
          </p>
        </div>

        <ul v-else class="divide-y divide-slate/10">
          <li
            v-for="contact in store.items"
            :key="contact.id"
            class="flex items-center justify-between gap-4 py-3"
          >
            <div class="min-w-0">
              <p class="truncate font-medium text-ink">{{ contact.name }}</p>
              <p v-if="contact.title" class="truncate text-sm text-slate">{{ contact.title }}</p>
              <div class="mt-1 flex flex-wrap gap-x-3 text-sm">
                <a
                  v-if="contact.email"
                  :href="`mailto:${contact.email}`"
                  class="text-slate hover:text-ink hover:underline"
                >
                  {{ contact.email }}
                </a>
                <a
                  v-if="contact.linkedin_url"
                  :href="contact.linkedin_url"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="text-slate hover:text-ink hover:underline"
                >
                  LinkedIn
                </a>
              </div>
            </div>
            <div class="flex shrink-0 gap-1">
              <Button
                v-tooltip.bottom="tooltip('Edit contact')"
                icon="pi pi-pencil"
                aria-label="Edit contact"
                link
                size="small"
                @click="openEditDialog(contact)"
              />
              <Button
                v-tooltip.bottom="tooltip('Remove contact')"
                icon="pi pi-trash"
                aria-label="Remove contact"
                text
                severity="danger"
                size="small"
                @click="confirmDelete(contact)"
              />
            </div>
          </li>
        </ul>
      </div>
    </template>
  </Card>

  <ContactFormDialog
    v-model:visible="dialogVisible"
    :application-id="props.applicationId"
    :contact="editingContact"
  />
</template>
