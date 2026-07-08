import { describe, expect, it } from 'vitest'
import type { RouteLocationNormalized } from 'vue-router'
import { authGuard } from '../index'

// Only the fields authGuard actually reads are filled in; the rest of
// RouteLocationNormalized isn't relevant to this logic.
function makeRoute(
  meta: RouteLocationNormalized['meta'],
  fullPath = '/somewhere',
): RouteLocationNormalized {
  return { meta, fullPath } as RouteLocationNormalized
}

describe('authGuard', () => {
  it('redirects an unauthenticated visitor away from a protected route, preserving the intended destination', () => {
    const result = authGuard(makeRoute({ requiresAuth: true }, '/applications/42'), false)
    expect(result).toEqual({ name: 'login', query: { redirect: '/applications/42' } })
  })

  it('lets an authenticated user through a protected route', () => {
    const result = authGuard(makeRoute({ requiresAuth: true }), true)
    expect(result).toBe(true)
  })

  it('redirects an already-authenticated user away from a guest-only route (e.g. /login)', () => {
    const result = authGuard(makeRoute({ guestOnly: true }), true)
    expect(result).toEqual({ name: 'dashboard' })
  })

  it('lets a logged-out visitor through a guest-only route', () => {
    const result = authGuard(makeRoute({ guestOnly: true }), false)
    expect(result).toBe(true)
  })

  it('lets anyone through a route with no auth-related meta at all', () => {
    expect(authGuard(makeRoute({}), false)).toBe(true)
    expect(authGuard(makeRoute({}), true)).toBe(true)
  })
})
