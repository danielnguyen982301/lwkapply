import * as auth from './auth.js'
import { parseJsonSafe, firstErrorMessage } from './http.js'

// Popup and content scripts (the VietnamWorks auto-save flow) talk to
// the API only through this router - neither of them ever touches a
// token directly, so a compromised job-site page can't read one via the
// content script's execution context.
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  handleMessage(message, sender)
    .then(sendResponse)
    .catch((error) => sendResponse({ ok: false, error: error.message }))
  return true // keep the message channel open for the async response
})

async function handleMessage(message, sender) {
  switch (message.type) {
    case 'GET_AUTH_STATE':
      return { ok: true, loggedIn: await auth.isLoggedIn() }

    case 'LOGIN':
      await auth.login(message.email, message.password)
      return { ok: true }

    case 'LOGOUT':
      await auth.logout()
      return { ok: true }

    case 'CREATE_APPLICATION':
      return createApplication(message.payload)

    case 'UPDATE_APPLICATION':
      return updateApplication(message.applicationId, message.updates)

    case 'DELETE_APPLICATION':
      return deleteApplication(message.applicationId)

    case 'ARM_SAVE_WATCH': {
      const tabId = sender.tab?.id
      if (tabId == null) return { ok: false, error: 'No tab context for this request.' }
      armSaveWatch(tabId, message.payload)
      return { ok: true }
    }

    default:
      return { ok: false, error: `Unknown message type: ${message.type}` }
  }
}

async function createApplication(payload) {
  const response = await auth.apiFetch('/applications', {
    method: 'POST',
    body: JSON.stringify(payload),
  })
  const body = await parseJsonSafe(response)
  if (!response.ok) return { ok: false, error: firstErrorMessage(body) }
  if (!body) return { ok: false, error: 'Unexpected response from server.' }
  return { ok: true, application: body }
}

async function updateApplication(applicationId, updates) {
  const response = await auth.apiFetch(`/applications/${applicationId}`, {
    method: 'PATCH',
    body: JSON.stringify(updates),
  })
  const body = await parseJsonSafe(response)
  if (!response.ok) return { ok: false, error: firstErrorMessage(body) }
  if (!body) return { ok: false, error: 'Unexpected response from server.' }
  return { ok: true, application: body }
}

async function deleteApplication(applicationId) {
  const response = await auth.apiFetch(`/applications/${applicationId}`, { method: 'DELETE' })
  if (!response.ok) {
    const body = await parseJsonSafe(response)
    return { ok: false, error: firstErrorMessage(body) }
  }
  return { ok: true }
}

// --- Network-confirmed save --------------------------------------------
//
// Verified against a real save: clicking "Lưu công việc
// này" on VietnamWorks fires POST https://ms.vietnamworks.com/api-gateway/
// v1.0/save-job, returning {"meta":{"code":200,"message":"success"}} on
// success. That's a far more reliable signal than matching page text
// (language-independent, immune to copy changes) - so unlike the Apply
// flow (still DOM-heuristic in the content script; no network info for
// it yet), Save is confirmed here via chrome.webRequest instead.
//
// Coordination: the content script scrapes eagerly on click and arms a
// watch (ARM_SAVE_WATCH) *before* the request completes, keyed by
// tabId; onCompleted below only creates the application once that
// specific tab's save-job POST actually succeeds. Kept as a plain
// in-memory Map rather than chrome.storage.session - the window between
// arming and the request completing is at most a couple of seconds, well
// within a service worker's normal event-driven lifetime, so the small
// risk of losing a pending entry to an untimely worker restart is an
// accepted tradeoff for not needing an extra async storage round-trip
// here.
// Trailing "*" so this still matches if a query string ever gets
// appended (not observed, but a match pattern without a wildcard only
// matches that exact path with no query string at all).
const SAVE_JOB_ENDPOINT = 'https://ms.vietnamworks.com/api-gateway/v1.0/save-job*'
const PENDING_SAVE_TTL_MS = 15_000
const CAPTURED_JOBS_KEY = 'lwkapply_captured_jobs' // must match the content script's key
const MAX_TRACKED_JOBS = 500

const pendingSaves = new Map() // tabId -> { payload, armedAt }

function armSaveWatch(tabId, payload) {
  pendingSaves.set(tabId, { payload, armedAt: Date.now() })
}

chrome.webRequest.onCompleted.addListener(
  (details) => {
    if (details.method !== 'POST') return
    if (details.statusCode < 200 || details.statusCode >= 300) return
    const pending = pendingSaves.get(details.tabId)
    if (!pending) return
    pendingSaves.delete(details.tabId)
    if (Date.now() - pending.armedAt > PENDING_SAVE_TTL_MS) return // stale - ignore
    finalizeSave(details.tabId, pending.payload)
  },
  { urls: [SAVE_JOB_ENDPOINT] },
)

async function finalizeSave(tabId, payload) {
  const result = await createApplication(payload)
  if (!result.ok) {
    notifyTab(tabId, { type: 'AUTO_SAVE_RESULT', ok: false, error: result.error })
    return
  }
  await setCapturedJob(payload.job_url, { applicationId: result.application.id, status: 'saved' })
  notifyTab(tabId, {
    type: 'AUTO_SAVE_RESULT',
    ok: true,
    message: 'Saved to LwkApply',
    applicationId: result.application.id,
    jobUrl: payload.job_url,
  })
}

function notifyTab(tabId, message) {
  // The popup might be the only thing open (no content script alive in
  // this tab to receive it) - a missing receiving end is expected, not
  // an error worth surfacing.
  chrome.tabs.sendMessage(tabId, message).catch(() => {})
}

async function setCapturedJob(jobUrl, entry) {
  const { [CAPTURED_JOBS_KEY]: jobs } = await chrome.storage.local.get(CAPTURED_JOBS_KEY)
  const next = { ...(jobs ?? {}), [jobUrl]: entry }
  const keys = Object.keys(next)
  if (keys.length > MAX_TRACKED_JOBS) {
    for (const key of keys.slice(0, keys.length - MAX_TRACKED_JOBS)) delete next[key]
  }
  await chrome.storage.local.set({ [CAPTURED_JOBS_KEY]: next })
}
