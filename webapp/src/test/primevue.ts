import PrimeVue from 'primevue/config'
import Aura from '@primevue/themes/aura'
import type { App } from 'vue'

/** Installs PrimeVue with the same Aura theme the app uses in main.ts. */
export function installPrimeVue(app: App) {
  app.use(PrimeVue, {
    theme: {
      preset: Aura,
      options: { darkModeSelector: false },
    },
  })
}
