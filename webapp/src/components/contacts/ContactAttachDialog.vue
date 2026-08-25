<script setup lang="ts">
import { ref, watch } from 'vue'
import AutoComplete from 'primevue/autocomplete'
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import Message from 'primevue/message'

import { useApplicationContactsStore } from '@/stores/applicationContacts'
import { useContactsStore } from '@/stores/contacts'
import TruncatedText from '@/components/common/TruncatedText.vue'
import type { Contact } from '@/types/contact'

// Attaches an existing contact from the user's directory to one
// application (POST /applications/{application_id}/contacts - see
// stores/applicationContacts.ts). Only used from
// components/applications/ContactsPanel.vue today, but pulled out
// alongside ContactFormDialog.vue for the same reason
// DocumentAttachDialog.vue was: keeps that panel's template down to the
// list it actually owns. attach() already updates applicationContacts'
// own `items`/`total`, so this needs no follow-up sync from the caller.
const visible = defineModel<boolean>('visible', { default: false })
const props = defineProps<{ applicationId: string }>()
const emit = defineEmits<{ attached: [contact: Contact] }>()

const attached = useApplicationContactsStore()
const directory = useContactsStore()

const suggestions = ref<Contact[]>([])
const selectedContact = ref<Contact | null>(null)
let debounceTimer: ReturnType<typeof setTimeout> | undefined

watch(visible, (isVisible) => {
  if (!isVisible) return
  selectedContact.value = null
  suggestions.value = []
})

function onSearch(event: { query: string }) {
  if (debounceTimer) clearTimeout(debounceTimer)
  debounceTimer = setTimeout(() => {
    directory
      .searchContacts(event.query)
      .then((results) => {
        // Already-attached contacts would just 409 on submit - filter
        // them out of the suggestion list rather than let a user pick
        // one and hit an error.
        const attachedIds = new Set(attached.items.map((contact) => contact.id))
        suggestions.value = results.filter((contact) => !attachedIds.has(contact.id))
      })
      .catch(() => {
        suggestions.value = []
      })
  }, 300)
}

async function handleSubmit() {
  if (!selectedContact.value) return
  try {
    const contact = await attached.attach(props.applicationId, selectedContact.value.id)
    visible.value = false
    emit('attached', contact)
  } catch {
    // attached.attachError is already set and rendered below.
  }
}

function closeDialog() {
  visible.value = false
}
</script>

<template>
  <Dialog
    v-model:visible="visible"
    header="Attach an existing contact"
    modal
    dismissable-mask
    class="w-full max-w-md"
    @hide="closeDialog"
  >
    <form class="space-y-4" @submit.prevent="handleSubmit">
      <Message v-if="attached.attachStatus === 'error'" severity="error" :closable="false">
        {{ attached.attachError }}
      </Message>

      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-ink">Contact *</label>
        <AutoComplete
          v-model="selectedContact"
          :suggestions="suggestions"
          option-label="name"
          placeholder="Search your contacts…"
          class="w-full"
          fluid
          complete-on-focus
          @complete="onSearch"
        >
          <template #option="{ option }: { option: Contact }">
            <div class="flex min-w-0 flex-col py-1">
              <TruncatedText :text="option.name" max-width="14rem" class="font-medium text-ink" />
              <span v-if="option.title" class="truncate text-xs text-slate">{{
                option.title
              }}</span>
            </div>
          </template>
        </AutoComplete>
      </div>

      <div class="flex items-center justify-end gap-3 border-t border-slate/10 pt-4">
        <Button label="Cancel" severity="secondary" outlined type="button" @click="closeDialog" />
        <Button
          type="submit"
          :label="attached.attachStatus === 'loading' ? 'Attaching…' : 'Attach'"
          :loading="attached.attachStatus === 'loading'"
          :disabled="!selectedContact"
        />
      </div>
    </form>
  </Dialog>
</template>
