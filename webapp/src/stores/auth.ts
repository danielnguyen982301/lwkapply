import { defineStore } from 'pinia'
import { api, extractErrorMessage } from '@/lib/api'
import type { AccessTokenResponse, LoginPayload, RegisterPayload, User } from '@/types/auth'

interface AuthState {
  user: User | null
  accessToken: string | null
  status: 'idle' | 'loading' | 'error'
  error: string | null
  /** Set once the initial bootstrap() attempt has finished, success or
   * not, so the router guard and App shell know whether "not logged in"
   * is a confirmed fact yet or still pending. */
  bootstrapped: boolean
}

// The access token lives in memory only (this store's state) — never
// localStorage — so an XSS payload that can run JS still can't read it
// off disk. The refresh token lives in an httpOnly cookie the backend
// sets on /auth/login and /auth/refresh; JS never sees its value at all,
// which is strictly better than the in-memory-only approach this store
// used before: sessions now survive a hard reload (bootstrap() below
// exchanges the cookie for a fresh access token) without JS ever holding
// the refresh token.
export const useAuthStore = defineStore('auth', {
  state: (): AuthState => ({
    user: null,
    accessToken: null,
    status: 'idle',
    error: null,
    bootstrapped: false,
  }),

  getters: {
    isAuthenticated: (state) => Boolean(state.accessToken && state.user),
  },

  actions: {
    async login(payload: LoginPayload) {
      this.status = 'loading'
      this.error = null
      try {
        const { data } = await api.post<AccessTokenResponse>('/auth/login', payload)
        this.accessToken = data.access_token
        await this.fetchCurrentUser()
        this.status = 'idle'
      } catch (err) {
        this.status = 'error'
        this.error = extractErrorMessage(err)
        throw err
      }
    },

    async register(payload: RegisterPayload) {
      this.status = 'loading'
      this.error = null
      try {
        await api.post('/auth/register', payload)
        await this.login({ email: payload.email, password: payload.password })
      } catch (err) {
        this.status = 'error'
        this.error = extractErrorMessage(err)
        throw err
      }
    },

    async fetchCurrentUser() {
      const { data } = await api.get<User>('/users/me')
      this.user = data
    },

    /** Called once on app boot (see main.ts). The refresh-token cookie,
     * if any, persists across a hard reload — this exchanges it for a
     * fresh access token so the user doesn't have to log in again every
     * time the tab reloads. A failure here is the normal case for a
     * first-time or logged-out visitor, not an error worth surfacing. */
    async bootstrap() {
      try {
        await this.refreshAccessToken()
        await this.fetchCurrentUser()
      } catch {
        this.accessToken = null
        this.user = null
      } finally {
        this.bootstrapped = true
      }
    },

    async refreshAccessToken(): Promise<string> {
      const { data } = await api.post<AccessTokenResponse>('/auth/refresh')
      this.accessToken = data.access_token
      return data.access_token
    },

    async logout() {
      try {
        await api.post('/auth/logout')
      } catch {
        // Clear local state regardless — worst case the cookie lingers
        // server-side until it expires on its own; we still want the UI
        // to reflect "logged out" immediately.
      }
      this.user = null
      this.accessToken = null
    },
  },
})
