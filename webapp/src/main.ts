import { createApp } from "vue";
import PrimeVue from "primevue/config";
import Aura from "@primevue/themes/aura";
import { createPinia } from "pinia";

import App from "./App.vue";
import router from "./router";
import { useAuthStore } from "./stores/auth";
import "./style.css";

const app = createApp(App);

app.use(createPinia());
const auth = useAuthStore();
await auth.bootstrap();

app.use(router);
app.use(PrimeVue, {
  theme: {
    preset: Aura,
    options: { darkModeSelector: false }, // dark mode: revisit post-MVP
  },
});

app.mount("#app");
