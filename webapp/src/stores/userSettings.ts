import { defineStore } from 'pinia'
import { api, extractErrorMessage } from '@/lib/api'
import type { UserSettings, UserSettingsUpdatePayload } from '@/types/userSettings'

type RequestStatus = 'idle' | 'loading' | 'error'

interface UserSettingsState {
  settings: UserSettings | null
  fetchStatus: RequestStatus
  fetchError: string | null

  mutationStatus: RequestStatus
  mutationError: string | null
}

// Delivery *preferences* for the current user — GET/PATCH /users/me/settings.
// A separate store from auth.ts, unlike the profile fields it patches (see
// stores/auth.ts's updateProfile/etc.) — settings is its own sub-resource
// with its own row (UserSettings), not a field on User itself, so there's
// nothing on the `auth` store's `user` object for this to keep in sync with.
export const useUserSettingsStore = defineStore('userSettings', {
  state: (): UserSettingsState => ({
    settings: null,
    fetchStatus: 'idle',
    fetchError: null,

    mutationStatus: 'idle',
    mutationError: null,
  }),

  actions: {
    async fetchSettings() {
      this.fetchStatus = 'loading'
      this.fetchError = null
      try {
        const { data } = await api.get<UserSettings>('/users/me/settings')
        this.settings = data
        this.fetchStatus = 'idle'
      } catch (err) {
        this.fetchStatus = 'error'
        this.fetchError = extractErrorMessage(err)
        throw err
      }
    },

    async updateSettings(payload: UserSettingsUpdatePayload): Promise<UserSettings> {
      this.mutationStatus = 'loading'
      this.mutationError = null
      try {
        const { data } = await api.patch<UserSettings>('/users/me/settings', payload)
        this.settings = data
        this.mutationStatus = 'idle'
        return data
      } catch (err) {
        this.mutationStatus = 'error'
        this.mutationError = extractErrorMessage(err)
        throw err
      }
    },
  },
})
