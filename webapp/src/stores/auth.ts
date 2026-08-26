import { defineStore } from 'pinia'
import { api, extractErrorMessage } from '@/lib/api'
import { getBrowserTimezone } from '@/lib/timezone'
import type {
  AccessTokenResponse,
  AccountDeletePayload,
  LoginPayload,
  PasswordChangePayload,
  ProfileUpdatePayload,
  RegisterPayload,
  User,
} from '@/types/auth'

type RequestStatus = 'idle' | 'loading' | 'error'

interface AuthState {
  user: User | null
  accessToken: string | null
  // In-memory only, same reasoning/lifetime as accessToken — sourced
  // from the login/refresh response body (see lib/api.ts's request
  // interceptor, which echoes this back as X-CSRF-Token on unsafe
  // requests) rather than read from the csrf_token cookie directly,
  // since that cookie lives on the API's origin (Vercel vs Render),
  // which this page's own JS can never read via document.cookie.
  csrfToken: string | null
  status: 'idle' | 'loading' | 'error'
  error: string | null
  /** Set once the initial bootstrap() attempt has finished, success or
   * not, so the router guard and App shell know whether "not logged in"
   * is a confirmed fact yet or still pending. */
  bootstrapped: boolean

  // Separate status/error per settings-page mutation, not reuse of
  // `status`/`error` above — those are login/register-flow only, and
  // e.g. a failed avatar upload shouldn't make LoginView think a login
  // attempt errored.
  profileStatus: RequestStatus
  profileError: string | null

  avatarStatus: RequestStatus
  avatarError: string | null

  passwordStatus: RequestStatus
  passwordError: string | null

  deleteAccountStatus: RequestStatus
  deleteAccountError: string | null
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
    csrfToken: null,
    status: 'idle',
    error: null,
    bootstrapped: false,

    profileStatus: 'idle',
    profileError: null,

    avatarStatus: 'idle',
    avatarError: null,

    passwordStatus: 'idle',
    passwordError: null,

    deleteAccountStatus: 'idle',
    deleteAccountError: null,
  }),

  getters: {
    isAuthenticated: (state) => Boolean(state.accessToken && state.user),
  },

  actions: {
    async login(payload: LoginPayload) {
      this.status = 'loading'
      this.error = null
      try {
        const { data } = await api.post<AccessTokenResponse>('/auth/login', {
          ...payload,
          timezone: getBrowserTimezone(),
        })
        this.accessToken = data.access_token
        this.csrfToken = data.csrf_token
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
        await api.post('/auth/register', { ...payload, timezone: getBrowserTimezone() })
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
        this.csrfToken = null
        this.user = null
      } finally {
        this.bootstrapped = true
      }
    },

    async refreshAccessToken(): Promise<string> {
      const { data } = await api.post<AccessTokenResponse>('/auth/refresh', {
        timezone: getBrowserTimezone(),
      })
      this.accessToken = data.access_token
      this.csrfToken = data.csrf_token
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
      this.csrfToken = null
    },

    // --- Account settings ------------------------------------------------
    // These all mutate `this.user` in place on success rather than living
    // in a separate settings store — the account-settings screen and
    // anywhere else `auth.user` is read (e.g. AppLayout.vue's greeting)
    // need to see the update immediately, with no extra sync step.

    async updateProfile(payload: ProfileUpdatePayload) {
      this.profileStatus = 'loading'
      this.profileError = null
      try {
        const { data } = await api.patch<User>('/users/me', payload)
        this.user = data
        this.profileStatus = 'idle'
      } catch (err) {
        this.profileStatus = 'error'
        this.profileError = extractErrorMessage(err)
        throw err
      }
    },

    async uploadAvatar(file: File) {
      this.avatarStatus = 'loading'
      this.avatarError = null
      const formData = new FormData()
      formData.append('file', file)
      try {
        const { data } = await api.post<User>('/users/me/avatar', formData, {
          headers: { 'Content-Type': 'multipart/form-data' },
        })
        this.user = data
        this.avatarStatus = 'idle'
      } catch (err) {
        this.avatarStatus = 'error'
        this.avatarError = extractErrorMessage(err)
        throw err
      }
    },

    async deleteAvatar() {
      this.avatarStatus = 'loading'
      this.avatarError = null
      try {
        const { data } = await api.delete<User>('/users/me/avatar')
        this.user = data
        this.avatarStatus = 'idle'
      } catch (err) {
        this.avatarStatus = 'error'
        this.avatarError = extractErrorMessage(err)
        throw err
      }
    },

    async changePassword(payload: PasswordChangePayload) {
      this.passwordStatus = 'loading'
      this.passwordError = null
      try {
        await api.post('/users/me/password', payload)
        this.passwordStatus = 'idle'
      } catch (err) {
        this.passwordStatus = 'error'
        this.passwordError = extractErrorMessage(err)
        throw err
      }
    },

    /** Permanently deletes the account. Clears local session state on
     * success — the backend already cleared the refresh-token cookie —
     * so the caller just needs to redirect to /login afterward. */
    async deleteAccount(payload: AccountDeletePayload) {
      this.deleteAccountStatus = 'loading'
      this.deleteAccountError = null
      try {
        await api.delete('/users/me', { data: payload })
        this.user = null
        this.accessToken = null
        this.deleteAccountStatus = 'idle'
      } catch (err) {
        this.deleteAccountStatus = 'error'
        this.deleteAccountError = extractErrorMessage(err)
        throw err
      }
    },
  },
})
