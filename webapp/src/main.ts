import { createApp } from 'vue'
import PrimeVue from 'primevue/config'
import ConfirmationService from 'primevue/confirmationservice'
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

app.mount('#app')
