<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, reactive, ref, watch } from 'vue'
import Button from 'primevue/button'
import Card from 'primevue/card'
import Dialog from 'primevue/dialog'
import InputText from 'primevue/inputtext'
import Message from 'primevue/message'
import ProgressSpinner from 'primevue/progressspinner'
import { useConfirm } from 'primevue/useconfirm'

import { useContactsStore } from '@/stores/contacts'
import type { Contact, ContactCreatePayload } from '@/types/contact'

const props = defineProps<{ applicationId: string }>()

const store = useContactsStore()
const confirm = useConfirm()

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

interface FormState {
  name: string
  title: string
  email: string
  linkedin_url: string
}

function blankForm(): FormState {
  return { name: '', title: '', email: '', linkedin_url: '' }
}

const dialogVisible = ref(false)
const editingContact = ref<Contact | null>(null)
const form = reactive<FormState>(blankForm())
const validationErrors = ref<Partial<Record<keyof FormState, string>>>({})

const dialogTitle = computed(() => (editingContact.value ? 'Edit contact' : 'Add contact'))

function openAddDialog() {
  editingContact.value = null
  Object.assign(form, blankForm())
  validationErrors.value = {}
  dialogVisible.value = true
}

function openEditDialog(contact: Contact) {
  editingContact.value = contact
  form.name = contact.name
  form.title = contact.title ?? ''
  form.email = contact.email ?? ''
  form.linkedin_url = contact.linkedin_url ?? ''
  validationErrors.value = {}
  dialogVisible.value = true
}

function closeDialog() {
  dialogVisible.value = false
}

function validate(): boolean {
  const errors: Partial<Record<keyof FormState, string>> = {}
  if (!form.name.trim()) errors.name = 'Name is required.'
  if (form.email.trim() && !EMAIL_PATTERN.test(form.email.trim())) {
    errors.email = 'Enter a valid email address.'
  }
  validationErrors.value = errors
  return Object.keys(errors).length === 0
}

function buildPayload(): ContactCreatePayload {
  return {
    name: form.name.trim(),
    title: form.title.trim() || null,
    email: form.email.trim() || null,
    linkedin_url: form.linkedin_url.trim() || null,
  }
}

async function handleSubmit() {
  if (!validate()) return
  const payload = buildPayload()
  try {
    if (editingContact.value) {
      await store.updateContact(props.applicationId, editingContact.value.id, payload)
    } else {
      await store.createContact(props.applicationId, payload)
    }
    dialogVisible.value = false
  } catch {
    // store.mutationError is already set and rendered in the dialog below.
  }
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
                icon="pi pi-pencil"
                aria-label="Edit contact"
                link
                size="small"
                @click="openEditDialog(contact)"
              />
              <Button
                icon="pi pi-trash"
                aria-label="Remove contact"
                link
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

  <Dialog
    v-model:visible="dialogVisible"
    :header="dialogTitle"
    modal
    class="w-full max-w-md"
    @hide="closeDialog"
  >
    <form class="space-y-4" @submit.prevent="handleSubmit">
      <Message v-if="store.mutationStatus === 'error'" severity="error" :closable="false">
        {{ store.mutationError }}
      </Message>

      <div class="flex flex-col gap-1">
        <label for="contact-name" class="text-sm font-medium text-ink">Name *</label>
        <InputText
          id="contact-name"
          v-model="form.name"
          :invalid="!!validationErrors.name"
          :aria-describedby="validationErrors.name ? 'contact-name-error' : undefined"
          class="w-full"
          autofocus
        />
        <Message
          v-if="validationErrors.name"
          id="contact-name-error"
          severity="error"
          variant="simple"
          size="small"
        >
          {{ validationErrors.name }}
        </Message>
      </div>

      <div class="flex flex-col gap-1">
        <label for="contact-title" class="text-sm font-medium text-ink">Title</label>
        <InputText id="contact-title" v-model="form.title" class="w-full" />
      </div>

      <div class="flex flex-col gap-1">
        <label for="contact-email" class="text-sm font-medium text-ink">Email</label>
        <InputText
          id="contact-email"
          v-model="form.email"
          type="email"
          :invalid="!!validationErrors.email"
          :aria-describedby="validationErrors.email ? 'contact-email-error' : undefined"
          class="w-full"
        />
        <Message
          v-if="validationErrors.email"
          id="contact-email-error"
          severity="error"
          variant="simple"
          size="small"
        >
          {{ validationErrors.email }}
        </Message>
      </div>

      <div class="flex flex-col gap-1">
        <label for="contact-linkedin" class="text-sm font-medium text-ink">LinkedIn URL</label>
        <InputText
          id="contact-linkedin"
          v-model="form.linkedin_url"
          type="url"
          placeholder="https://linkedin.com/in/…"
          class="w-full"
        />
      </div>

      <div class="flex items-center justify-end gap-3 border-t border-slate/10 pt-4">
        <Button label="Cancel" severity="secondary" outlined type="button" @click="closeDialog" />
        <Button
          type="submit"
          :label="
            store.mutationStatus === 'loading'
              ? 'Saving…'
              : editingContact
                ? 'Save changes'
                : 'Add contact'
          "
          :loading="store.mutationStatus === 'loading'"
        />
      </div>
    </form>
  </Dialog>
</template>
