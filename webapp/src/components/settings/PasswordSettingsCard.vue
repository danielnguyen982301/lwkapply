<script setup lang="ts">
import { ref } from 'vue'
import Button from 'primevue/button'
import Message from 'primevue/message'

import { useAuthStore } from '@/stores/auth'

const auth = useAuthStore()
const sent = ref(false)

async function onRequestReset() {
  sent.value = false
  try {
    await auth.requestOwnPasswordReset()
    sent.value = true
  } catch {
    // auth.passwordError is already set and rendered below.
  }
}
</script>

<template>
  <section class="rounded-card border border-slate/10 bg-paper p-4">
    <h2 class="font-display text-sm font-semibold text-ink">Password</h2>
    <p class="mt-1 text-sm text-slate">We'll email you a link to set a new password.</p>

    <div class="mt-4 space-y-4">
      <Message v-if="auth.passwordStatus === 'error'" severity="error" :closable="false">
        {{ auth.passwordError }}
      </Message>
      <Message v-else-if="sent" severity="success" :closable="true" @close="sent = false">
        Check your email for a reset link.
      </Message>

      <div class="flex justify-end border-t border-slate/10 pt-4">
        <Button
          :label="auth.passwordStatus === 'loading' ? 'Sending…' : 'Reset password'"
          :loading="auth.passwordStatus === 'loading'"
          @click="onRequestReset"
        />
      </div>
    </div>
  </section>
</template>
