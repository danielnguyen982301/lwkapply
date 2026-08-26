import axios, { type AxiosError, type InternalAxiosRequestConfig } from 'axios'
import { useAuthStore } from '@/stores/auth'

const UNSAFE_METHODS = new Set(['post', 'put', 'patch', 'delete'])

// Requests go through the Vite dev proxy (see vite.config.ts) so this can
// stay relative in dev and be overridden per-environment in production.
export const api = axios.create({
  baseURL: import.meta.env.VITE_API_BASE_URL ?? '/api/v1',
  timeout: 15_000,
  // Required so the browser sends/receives the httpOnly refresh-token
  // and csrf_token cookies on cross-origin requests (frontend and API
  // are on different domains — Vercel vs Render).
  withCredentials: true,
})

api.interceptors.request.use((config) => {
  const auth = useAuthStore()
  if (auth.accessToken) {
    config.headers.Authorization = `Bearer ${auth.accessToken}`
  }

  // Double-submit CSRF: echo the CSRF token back as a header. Only
  // relevant for /auth/logout, the one remaining endpoint authenticated
  // via cookie rather than the bearer header (see backend
  // verify_csrf's docstring for why /auth/refresh doesn't need this) —
  // but harmless to attach on every unsafe request regardless. Sourced
  // from the auth store (populated from the login/refresh response
  // body), not read from the csrf_token cookie directly — a
  // different-origin frontend's own JS can never read a cookie that
  // belongs to the API's origin, cross-origin Vercel/Render setup
  // included.
  const method = config.method?.toLowerCase()
  if (method && UNSAFE_METHODS.has(method) && auth.csrfToken) {
    config.headers['X-CSRF-Token'] = auth.csrfToken
  }

  return config
})

// --- 401 handling -----------------------------------------------------
// Multiple requests can fail with 401 at once (e.g. a page that fires
// several calls on mount after the access token has expired). Without
// coordination, each one would kick off its own refresh call, racing
// against the backend's refresh-token rotation. This queues concurrent
// 401s behind a single in-flight refresh and replays them once it
// resolves.
let refreshPromise: Promise<string> | null = null

type RetryableConfig = InternalAxiosRequestConfig & { _retried?: boolean }

// Auth endpoints never go through the "401 -> refresh -> retry" flow.
// Without this exclusion, a 401 from /auth/refresh itself (e.g. no
// session cookie yet, or the refresh token is expired/invalid) would be
// treated like any other expired-access-token 401: the interceptor would
// call refreshAccessToken(), which calls /auth/refresh again, which 401s
// again, forever — an infinite loop that never resolves. A 401 on login
// (wrong password) shouldn't trigger a refresh attempt either.
const AUTH_ENDPOINT_PATTERN = /\/auth\/(login|refresh|logout|register)$/

api.interceptors.response.use(
  (response) => response,
  async (error: AxiosError) => {
    const original = error.config as RetryableConfig | undefined
    const status = error.response?.status
    const isAuthEndpoint = original?.url && AUTH_ENDPOINT_PATTERN.test(original.url)

    if (status !== 401 || !original || original._retried || isAuthEndpoint) {
      return Promise.reject(error)
    }

    const auth = useAuthStore()
    original._retried = true

    try {
      if (!refreshPromise) {
        refreshPromise = auth.refreshAccessToken().finally(() => {
          refreshPromise = null
        })
      }
      const newToken = await refreshPromise
      original.headers.Authorization = `Bearer ${newToken}`
      return api(original)
    } catch (refreshError) {
      auth.logout()
      return Promise.reject(refreshError)
    }
  },
)

export function extractErrorMessage(error: unknown): string {
  if (axios.isAxiosError(error)) {
    const detail = error.response?.data?.detail
    if (typeof detail === 'string') return detail
    if (Array.isArray(detail) && detail[0]?.msg) return detail[0].msg
    if (error.code === 'ECONNABORTED') return 'The request timed out. Please try again.'
    if (!error.response) return 'Unable to reach the server. Check your connection.'
  }
  return 'Something went wrong. Please try again.'
}
