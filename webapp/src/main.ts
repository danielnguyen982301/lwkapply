import { createApp } from 'vue'
import PrimeVue from 'primevue/config'
import Aura from '@primevue/themes/aura'

import App from './App.vue'
import './style.css'

const app = createApp(App)

app.use(PrimeVue, {
  theme: {
    preset: Aura,
    options: { darkModeSelector: false }, // dark mode: revisit post-MVP
  },
})

app.mount('#app')
