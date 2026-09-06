import { API_BASE_URL, CLIENT_PLATFORM_HEADER } from './config.js'

const STORAGE_KEY = 'lwkapply_auth'

async function getStoredAuth() {
  const { [STORAGE_KEY]: auth } = await chrome.storage.local.get(STORAGE_KEY)
  return auth ?? null
}

async function setStoredAuth(auth) {
  await chrome.storage.local.set({ [STORAGE_KEY]: auth })
}

async function clearStoredAuth() {
  await chrome.storage.local.remove(STORAGE_KEY)
}

function firstErrorMessage(body, fallback) {
  if (typeof body?.detail === 'string') return body.detail
  if (Array.isArray(body?.detail) && body.detail[0]?.msg) return body.detail[0].msg
  return fallback
}

export async function login(email, password) {
  const response = await fetch(`${API_BASE_URL}/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...CLIENT_PLATFORM_HEADER },
    body: JSON.stringify({ email, password }),
  })
  const body = await response.json()
  if (!response.ok) {
    throw new Error(firstErrorMessage(body, 'Incorrect email or password'))
  }
  await setStoredAuth({
    accessToken: body.access_token,
    refreshToken: body.refresh_token,
  })
}

// Single-flight guard so concurrent 401s from apiFetch don't each kick
// off their own refresh call and race the backend's refresh-token
// rotation - mirrors webapp's src/lib/api.ts response interceptor.
let refreshPromise = null

async function refresh() {
  const auth = await getStoredAuth()
  if (!auth?.refreshToken) throw new Error('Not logged in')

  const response = await fetch(`${API_BASE_URL}/auth/refresh`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...CLIENT_PLATFORM_HEADER },
    body: JSON.stringify({ refresh_token: auth.refreshToken }),
  })
  const body = await response.json()
  if (!response.ok) {
    await clearStoredAuth()
    throw new Error('Session expired - please log in again')
  }
  await setStoredAuth({
    accessToken: body.access_token,
    refreshToken: body.refresh_token,
  })
  return body.access_token
}

export async function logout() {
  const auth = await getStoredAuth()
  await clearStoredAuth()
  if (!auth?.refreshToken) return
  try {
    await fetch(`${API_BASE_URL}/auth/logout`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', ...CLIENT_PLATFORM_HEADER },
      body: JSON.stringify({ refresh_token: auth.refreshToken }),
    })
  } catch {
    // Best-effort, same reasoning as the mobile client's logout(): the
    // local copy is already cleared above, and a stale refresh token
    // left on the server expires on its own.
  }
}

export async function isLoggedIn() {
  const auth = await getStoredAuth()
  return Boolean(auth?.accessToken)
}

// Authenticated fetch for every non-auth endpoint. Transparently retries
// once after a silent token refresh on a 401.
export async function apiFetch(path, options = {}) {
  const auth = await getStoredAuth()
  if (!auth?.accessToken) throw new Error('Not logged in')

  const doFetch = (accessToken) =>
    fetch(`${API_BASE_URL}${path}`, {
      ...options,
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${accessToken}`,
        ...CLIENT_PLATFORM_HEADER,
        ...options.headers,
      },
    })

  let response = await doFetch(auth.accessToken)

  if (response.status === 401) {
    if (!refreshPromise) {
      refreshPromise = refresh().finally(() => {
        refreshPromise = null
      })
    }
    const newAccessToken = await refreshPromise
    response = await doFetch(newAccessToken)
  }

  return response
}
