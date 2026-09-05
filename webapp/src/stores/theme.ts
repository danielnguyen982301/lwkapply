import { defineStore } from 'pinia'

export type ThemeMode = 'system' | 'light' | 'dark'

const STORAGE_KEY = 'theme-mode'
const DARK_MEDIA_QUERY = '(prefers-color-scheme: dark)'

interface ThemeState {
  mode: ThemeMode
  systemPrefersDark: boolean
}

// Persisted client-side only (localStorage) — this is a per-device display
// preference, not account data, so there's no backend sub-resource for it
// (contrast stores/userSettings.ts, which does sync to the server). First
// localStorage usage in this app; that's fine here, unlike the access token
// stores/auth.ts deliberately keeps out of any storage.
export const useThemeStore = defineStore('theme', {
  state: (): ThemeState => ({
    mode: 'system',
    systemPrefersDark: false,
  }),

  getters: {
    isDark: (state): boolean =>
      state.mode === 'dark' || (state.mode === 'system' && state.systemPrefersDark),
  },

  actions: {
    // Called once from main.ts, before mount — index.html's inline script
    // already applied '.app-dark' synchronously (avoiding a flash of the
    // wrong theme), so this only needs to hydrate reactive state to match
    // and start listening for further changes.
    init() {
      const stored = localStorage.getItem(STORAGE_KEY)
      this.mode = stored === 'light' || stored === 'dark' ? stored : 'system'

      const media = window.matchMedia(DARK_MEDIA_QUERY)
      this.systemPrefersDark = media.matches
      media.addEventListener('change', (event) => {
        this.systemPrefersDark = event.matches
        this.applyClass()
      })

      this.applyClass()
    },

    setMode(mode: ThemeMode) {
      this.mode = mode
      localStorage.setItem(STORAGE_KEY, mode)
      this.applyClass()
    },

    applyClass() {
      document.documentElement.classList.toggle('app-dark', this.isDark)
    },
  },
})
