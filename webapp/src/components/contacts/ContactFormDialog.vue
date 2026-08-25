<script setup lang="ts">
import { computed, watch } from 'vue'
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import Message from 'primevue/message'
import { toTypedSchema } from '@vee-validate/zod'
import z from 'zod'
import { useForm } from 'vee-validate'

import { useContactsStore } from '@/stores/contacts'
import CustomInputText from '@/components/custom_form_fields/CustomInputText.vue'
import type { Contact, ContactCreatePayload } from '@/types/contact'

interface FormValues {
  name: string
  title: string
  email: string
  linkedin_url: string
}

// Creates/edits a contact straight in the user's contact directory (POST/
// PATCH /contacts - always standalone, never application-scoped; see
// stores/contacts.ts), same shape as DocumentUploadDialog.vue/
// DocumentEditDialog.vue combined into one dialog (add/edit keyed off
// whether `contact` is set). Shared by ContactDirectoryView.vue
// (directory-only add/edit) and ContactsPanel.vue, which also needs a
// freshly-created contact attached to the current application afterward -
// that's deliberately NOT this component's concern: it emits `created`/
// `updated` with the resulting Contact and closes itself, and the caller
// decides what happens next (ContactsPanel attaches a new contact as a
// follow-up call, and patches its own attached-contacts list on an edit -
// see its own attachError handling and `handleUpdated()` for where each
// surfaces, since this dialog is already closed by then).
const visible = defineModel<boolean>('visible', { default: false })
const props = defineProps<{ contact: Contact | null }>()
const emit = defineEmits<{ created: [contact: Contact]; updated: [contact: Contact] }>()

const store = useContactsStore()

function blankForm(): FormValues {
  return { name: '', title: '', email: '', linkedin_url: '' }
}

function populateForm(contact: Contact): FormValues {
  const { name, title, email, linkedin_url } = contact
  return {
    name,
    title: title ?? '',
    email: email ?? '',
    linkedin_url: linkedin_url ?? '',
  }
}

const validationSchema = toTypedSchema(
  z.object({
    name: z.string().trim().min(1, 'Name is required'),
    title: z.string().trim().nullable(),
    email: z.union([z.string().trim().email('Enter a valid email address.'), z.literal('')]),
    linkedin_url: z.string().trim().nullable(),
  }),
)

const { errors, handleSubmit, meta, resetForm } = useForm<FormValues>({
  validationSchema,
  initialValues: { ...blankForm() },
})

const dialogTitle = computed(() => (props.contact ? 'Edit contact' : 'Add contact'))

// Keyed off `visible`, not `props.contact` - PrimeVue's Dialog doesn't
// keep its slot content mounted while hidden, so every close unmounts
// CustomInputText's underlying useField()s and every reopen remounts
// them fresh. Watching `props.contact` instead used to miss resets
// entirely on a same-contact reopen (the prop reference doesn't change),
// and even for a genuinely different contact couldn't be trusted to run
// before the remount. Watching `visible` fires on every single open and,
// via Vue's default pre-flush watch timing, runs before the Dialog's
// content actually remounts - so the freshly-mounted fields always pick
// up the right values instead of vee-validate's post-remount defaults.
watch(
  visible,
  (isVisible) => {
    if (isVisible) {
      resetForm({ values: props.contact ? populateForm(props.contact) : blankForm() })
    }
  },
  { immediate: true },
)

function buildPayload(formValues: FormValues): ContactCreatePayload {
  return {
    name: formValues.name.trim(),
    title: formValues.title.trim() || null,
    email: formValues.email.trim() || null,
    linkedin_url: formValues.linkedin_url.trim() || null,
  }
}

const onFormSubmit = handleSubmit(async (formValues) => {
  const payload = buildPayload(formValues)
  try {
    if (props.contact) {
      const updated = await store.updateContact(props.contact.id, payload)
      visible.value = false
      emit('updated', updated)
    } else {
      const created = await store.createContact(payload)
      visible.value = false
      emit('created', created)
    }
  } catch {
    // store.mutationError is already set and rendered below.
  }
})

function closeDialog() {
  visible.value = false
}
</script>

<template>
  <Dialog
    v-model:visible="visible"
    :header="dialogTitle"
    modal
    dismissable-mask
    class="w-full max-w-md"
    @hide="closeDialog"
  >
    <form class="space-y-4" @submit.prevent="onFormSubmit">
      <Message v-if="store.mutationStatus === 'error'" severity="error" :closable="false">
        {{ store.mutationError }}
      </Message>

      <div class="flex flex-col gap-1">
        <label for="contact-name" class="text-sm font-medium text-ink">Name *</label>
        <CustomInputText
          id="contact-name"
          name="name"
          :invalid="!!errors.name"
          :aria-describedby="!!errors.name ? 'contact-name-error' : undefined"
          class="w-full"
          autofocus
        />
      </div>

      <div class="flex flex-col gap-1">
        <label for="contact-title" class="text-sm font-medium text-ink">Title</label>
        <CustomInputText id="contact-title" name="title" class="w-full" />
      </div>

      <div class="flex flex-col gap-1">
        <label for="contact-email" class="text-sm font-medium text-ink">Email</label>
        <CustomInputText
          id="contact-email"
          name="email"
          type="email"
          :invalid="!!errors.email"
          :aria-describedby="errors.email ? 'contact-email-error' : undefined"
          class="w-full"
        />
      </div>

      <div class="flex flex-col gap-1">
        <label for="contact-linkedin" class="text-sm font-medium text-ink">LinkedIn URL</label>
        <CustomInputText
          id="contact-linkedin"
          name="linkedin_url"
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
              : contact
                ? 'Save changes'
                : 'Add contact'
          "
          :loading="store.mutationStatus === 'loading'"
          :disabled="(!!contact && !meta.dirty) || store.mutationStatus === 'loading'"
        />
      </div>
    </form>
  </Dialog>
</template>
