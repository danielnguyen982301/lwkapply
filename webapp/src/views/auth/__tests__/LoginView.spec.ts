import { describe, expect, it, vi } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import { createTestingPinia } from '@pinia/testing'
import { createRouter, createMemoryHistory } from 'vue-router'
import LoginView from '../LoginView.vue'
import { useAuthStore } from '@/stores/auth'

// A minimal router with just the routes LoginView actually needs
// (useRouter/useRoute/RouterLink all require a real router instance to
// be installed, even in a test) — not the app's full router.
function makeTestRouter(initialPath = '/login') {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/login', name: 'login', component: LoginView },
      { path: '/register', name: 'register', component: { template: '<div />' } },
      { path: '/', name: 'dashboard', component: { template: '<div>dashboard</div>' } },
      { path: '/applications/:id', name: 'application-detail', component: { template: '<div />' } },
    ],
  })
  router.push(initialPath)
  return router
}

async function renderLoginView(initialPath = '/login') {
  const router = makeTestRouter(initialPath)
  await router.isReady()

  const wrapper = mount(LoginView, {
    global: {
      plugins: [
        createTestingPinia({ stubActions: true }), // actions become spies; store logic itself isn't under test here
        router,
      ],
    },
  })

  return { wrapper, router, auth: useAuthStore() }
}

describe('LoginView', () => {
  it('shows field errors and does not call the store when submitted empty', async () => {
    const { wrapper, auth } = await renderLoginView()

    await wrapper.find('form').trigger('submit')

    expect(wrapper.text()).toContain('Enter your email address.')
    expect(wrapper.text()).toContain('Enter your password.')
    expect(auth.login).not.toHaveBeenCalled()
  })

  it('calls auth.login with the entered credentials and redirects to the intended page on success', async () => {
    const { wrapper, router, auth } = await renderLoginView('/login?redirect=%2Fapplications%2F42')
    vi.mocked(auth.login).mockResolvedValueOnce(undefined)

    await wrapper.find('#email').setValue('jane@example.com')
    await wrapper.find('#password').setValue('correct-horse-battery-staple')
    await wrapper.find('form').trigger('submit')
    await flushPromises()

    expect(auth.login).toHaveBeenCalledWith({
      email: 'jane@example.com',
      password: 'correct-horse-battery-staple',
    })
    expect(router.currentRoute.value.fullPath).toBe('/applications/42')
  })

  it('shows the store error message when login fails', async () => {
    const { wrapper, auth } = await renderLoginView()
    auth.error = 'Incorrect email or password'
    vi.mocked(auth.login).mockRejectedValueOnce(new Error('unauthorized'))

    await wrapper.find('#email').setValue('jane@example.com')
    await wrapper.find('#password').setValue('wrong-password')
    await wrapper.find('form').trigger('submit')
    await flushPromises()

    expect(wrapper.text()).toContain('Incorrect email or password')
  })
})
