import { createRouter, createWebHistory, type RouteLocationNormalized } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

declare module 'vue-router' {
  interface RouteMeta {
    requiresAuth?: boolean
    /** Routes only a logged-out visitor should see (login/register). */
    guestOnly?: boolean
  }
}

// Pulled out as a plain function (rather than left inline in
// router.beforeEach) so it's testable without spinning up a full router
// instance — see src/router/__tests__/authGuard.spec.ts.
export function authGuard(to: RouteLocationNormalized, isAuthenticated: boolean) {
  if (to.meta.requiresAuth && !isAuthenticated) {
    return { name: 'login', query: { redirect: to.fullPath } }
  }

  if (to.meta.guestOnly && isAuthenticated) {
    return { name: 'dashboard' }
  }

  return true
}

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    {
      path: '/',
      component: () => import('@/layouts/AppLayout.vue'),
      meta: { requiresAuth: true },
      children: [
        {
          path: '',
          name: 'dashboard',
          component: () => import('@/views/DashboardView.vue'),
        },
        {
          path: 'applications',
          name: 'applications',
          component: () => import('@/views/applications/ApplicationListView.vue'),
        },
        {
          path: 'applications/board',
          name: 'application-board',
          component: () => import('@/views/applications/ApplicationBoardView.vue'),
        },
        {
          path: 'applications/new',
          name: 'application-new',
          component: () => import('@/views/applications/ApplicationFormView.vue'),
        },
        {
          path: 'applications/:id',
          name: 'application-detail',
          component: () => import('@/views/applications/ApplicationFormView.vue'),
        },
        {
          path: 'contacts',
          name: 'contacts',
          component: () => import('@/views/contacts/ContactDirectoryView.vue'),
        },
        {
          path: 'interviews',
          name: 'interviews',
          component: () => import('@/views/interviews/InterviewDirectoryView.vue'),
        },
      ],
    },
    {
      path: '/',
      component: () => import('@/layouts/AuthLayout.vue'),
      meta: { guestOnly: true },
      children: [
        {
          path: 'login',
          name: 'login',
          component: () => import('@/views/auth/LoginView.vue'),
        },
        {
          path: 'register',
          name: 'register',
          component: () => import('@/views/auth/RegisterView.vue'),
        },
      ],
    },
    {
      path: '/:pathMatch(.*)*',
      name: 'not-found',
      component: () => import('@/views/NotFoundView.vue'),
    },
  ],
})

router.beforeEach(async (to) => {
  const auth = useAuthStore()

  if (!auth.bootstrapped) {
    await auth.bootstrap()
  }

  return authGuard(to, auth.isAuthenticated)
})

export default router
