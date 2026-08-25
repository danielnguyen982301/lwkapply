<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref, watch } from 'vue'
import Button from 'primevue/button'
import Card from 'primevue/card'
import Message from 'primevue/message'
import Paginator from 'primevue/paginator'
import ProgressSpinner from 'primevue/progressspinner'
import { useConfirm } from 'primevue/useconfirm'

import { tooltip } from '@/lib/tooltip'
import { useApplicationContactsStore } from '@/stores/applicationContacts'
import ContactFormDialog from '@/components/contacts/ContactFormDialog.vue'
import ContactAttachDialog from '@/components/contacts/ContactAttachDialog.vue'
import type { Contact } from '@/types/contact'

const props = defineProps<{ applicationId: string }>()

// Attached-to-this-application list/attach/detach vs. the user's whole
// contact directory (add/edit/permanent-delete) - see
// stores/applicationContacts.ts's module docstring for why these are two
// separate stores now that a contact can belong to zero, one, or several
// applications.
const attached = useApplicationContactsStore()
const confirm = useConfirm()

// --- Add dialog (creates in the directory, then attaches here) ---------
// ContactFormDialog.vue only handles the directory create/edit itself -
// the attach-to-this-application step is this panel's own concern (a
// ContactDirectoryView.vue add has no application to attach to), done as
// a follow-up call once the dialog has already closed. A failure here
// surfaces via attached.attachError below, not inside the (by then
// closed) form dialog.
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

function handleCreated(contact: Contact) {
  attached.attach(props.applicationId, contact.id).catch(() => {})
}

// ContactFormDialog.vue patches the directory store's own copy - this
// panel's `attached.items` is a separate store's array, so it needs its
// own patch to stay in sync (same reasoning as the attach-after-create
// split above).
function handleUpdated(contact: Contact) {
  const index = attached.items.findIndex((item) => item.id === contact.id)
  if (index !== -1) attached.items[index] = contact
}

// --- Attach-existing dialog ------------------------------------------
// ContactAttachDialog.vue already updates applicationContacts' own
// items/total on a successful attach - nothing to sync here.
const attachDialogVisible = ref(false)

// --- Detach / list -----------------------------------------------------
function confirmDetach(contact: Contact) {
  confirm.require({
    message: `Remove ${contact.name} from this application? The contact itself won't be deleted - it stays in your contact directory.`,
    header: 'Remove contact',
    icon: 'pi pi-exclamation-triangle',
    rejectLabel: 'Cancel',
    acceptLabel: 'Remove',
    rejectProps: { label: 'Cancel', severity: 'secondary', outlined: true },
    acceptProps: { label: 'Remove', severity: 'danger' },
    accept: () => {
      attached.detach(props.applicationId, contact.id).catch(() => {})
    },
  })
}

function loadContacts(page = 1) {
  attached.fetchAttached(props.applicationId, { page }).catch(() => {})
}

function onPageChange(event: { page: number }) {
  loadContacts(event.page + 1)
}

onMounted(() => loadContacts())

watch(
  () => props.applicationId,
  (newId, oldId) => {
    if (newId && newId !== oldId) loadContacts()
  },
)

onBeforeUnmount(() => {
  attached.reset()
})
</script>

<template>
  <Card>
    <template #content>
      <div class="space-y-4">
        <div class="flex items-center justify-between">
          <h2 class="font-display text-lg font-semibold text-ink">Contacts</h2>
          <div class="flex gap-2">
            <Button
              label="Attach existing"
              icon="pi pi-link"
              severity="secondary"
              outlined
              size="small"
              @click="attachDialogVisible = true"
            />
            <Button label="Add contact" icon="pi pi-plus" size="small" @click="openAddDialog" />
          </div>
        </div>

        <Message v-if="attached.listStatus === 'error'" severity="error" :closable="false">
          <span>{{ attached.listError }}</span>
          <Button
            label="Retry"
            link
            size="small"
            class="ml-2"
            @click="loadContacts(attached.page)"
          />
        </Message>

        <Message
          v-if="attached.attachError"
          severity="error"
          closable
          @close="attached.attachError = null"
        >
          {{ attached.attachError }}
        </Message>

        <Message
          v-if="attached.detachError"
          severity="error"
          closable
          @close="attached.detachError = null"
        >
          {{ attached.detachError }}
        </Message>

        <div
          v-if="attached.listStatus === 'loading' && attached.items.length === 0"
          aria-live="polite"
          class="flex justify-center py-8"
        >
          <ProgressSpinner aria-label="Loading contacts" style="width: 2rem; height: 2rem" />
        </div>

        <div
          v-else-if="attached.items.length === 0"
          class="rounded-card border border-dashed border-slate/30 p-6 text-center"
        >
          <p class="text-sm text-slate">
            No contacts attached yet. Add a new one or attach one already in your contact directory.
          </p>
        </div>

        <ul v-else class="divide-y divide-slate/10">
          <li
            v-for="contact in attached.items"
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
                v-tooltip.bottom="tooltip('Remove from this application')"
                icon="pi pi-times"
                aria-label="Remove from this application"
                text
                severity="danger"
                size="small"
                :loading="attached.detachingId === contact.id"
                @click="confirmDetach(contact)"
              />
            </div>
          </li>
        </ul>

        <Paginator
          v-if="attached.total > attached.pageSize"
          :rows="attached.pageSize"
          :total-records="attached.total"
          :first="(attached.page - 1) * attached.pageSize"
          @page="onPageChange"
        />
      </div>
    </template>
  </Card>

  <ContactFormDialog
    v-model:visible="dialogVisible"
    :contact="editingContact"
    @created="handleCreated"
    @updated="handleUpdated"
  />

  <ContactAttachDialog
    v-model:visible="attachDialogVisible"
    :application-id="props.applicationId"
  />
</template>
