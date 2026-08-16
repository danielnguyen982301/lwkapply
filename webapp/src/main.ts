import { createApp } from 'vue'
import PrimeVue from 'primevue/config'
import ConfirmationService from 'primevue/confirmationservice'
import Tooltip from 'primevue/tooltip'
import Aura from '@primevue/themes/aura'
import { createPinia } from 'pinia'

import App from './App.vue'
import router from './router'
import 'primeicons/primeicons.css'
import './style.css'

const app = createApp(App)

app.use(createPinia())

app.use(router)
app.use(PrimeVue, {
  theme: {
    preset: Aura,
    options: { darkModeSelector: false }, // dark mode: revisit post-MVP
  },
})
app.use(ConfirmationService)
// Registered globally so any `v-tooltip` usage works without a per-file
// import - used instead of the native `title` attribute anywhere a fast,
// consistent show delay matters (native title's ~1s OS-level delay isn't
// controllable). See lib/tooltip.ts for the shared fast-show-delay preset.
app.directive('tooltip', Tooltip)

app.mount('#app')
