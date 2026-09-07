import * as auth from './auth.js'
import { parseJsonSafe, firstErrorMessage } from './http.js'

// Popup and content scripts (the VietnamWorks auto-save flow) talk to
// the API only through this router - neither of them ever touches a
// token directly, so a compromised job-site page can't read one via the
// content script's execution context.
chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  handleMessage(message)
    .then(sendResponse)
    .catch((error) => sendResponse({ ok: false, error: error.message }))
  return true // keep the message channel open for the async response
})

async function handleMessage(message) {
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

// --- Network-driven save ------------------------------------------------
//
// Verified against a real save: clicking "Lưu công việc này" on
// VietnamWorks fires POST https://ms.vietnamworks.com/api-gateway/v1.0/
// save-job, returning {"meta":{"code":200,"message":"success"}} on
// success. The whole point of keying off this instead of the page's
// visible text/aria-label was to stop depending on VietnamWorks' DOM at
// all for Save - so nothing here identifies *which button* was clicked.
// This listener is the entire trigger: a confirmed 2xx on that tab is
// enough on its own to ask that tab's content script what job is on the
// page right now (reusing the existing SCRAPE_JOB handler, built
// originally for the popup) and save it. No click listener, no
// aria-label matching, no per-click "arming" - if this endpoint fires
// for a tab, something on that page just got saved.
//
// Apply has no verified network endpoint yet, so it's still the
// DOM-heuristic click listener in vietnamworks.js.
const SAVE_JOB_ENDPOINT = 'https://ms.vietnamworks.com/api-gateway/v1.0/save-job*'
const CAPTURED_JOBS_KEY = 'lwkapply_captured_jobs' // must match the content script's key
const MAX_TRACKED_JOBS = 500

chrome.webRequest.onCompleted.addListener(
  (details) => {
    if (details.method !== 'POST') return
    if (details.statusCode < 200 || details.statusCode >= 300) return
    if (details.tabId < 0) return // not associated with a tab - nothing to scrape
    handleConfirmedSave(details.tabId)
  },
  { urls: [SAVE_JOB_ENDPOINT] },
)

async function handleConfirmedSave(tabId) {
  if (!(await auth.isLoggedIn())) {
    notifyTab(tabId, {
      type: 'AUTO_SAVE_RESULT',
      ok: false,
      error: 'Log in to LwkApply (click the toolbar icon) to auto-save this.',
    })
    return
  }

  let scraped
  try {
    scraped = await chrome.tabs.sendMessage(tabId, { type: 'SCRAPE_JOB' })
  } catch {
    return // no content script alive in this tab - nothing to scrape
  }
  const job = scraped?.job
  if (!job?.company || !job?.position) return // not enough to satisfy the backend

  if (await getCapturedJob(job.job_url)) return // already tracked

  const result = await createApplication({
    company: job.company,
    position: job.position,
    location: job.location,
    salary_min: job.salary_min,
    salary_max: job.salary_max,
    job_url: job.job_url,
    notes: null,
    source: 'vietnamworks',
  })
  if (!result.ok) {
    notifyTab(tabId, { type: 'AUTO_SAVE_RESULT', ok: false, error: result.error })
    return
  }

  await setCapturedJob(job.job_url, { applicationId: result.application.id, status: 'saved' })
  notifyTab(tabId, {
    type: 'AUTO_SAVE_RESULT',
    ok: true,
    message: 'Saved to LwkApply',
    applicationId: result.application.id,
    jobUrl: job.job_url,
  })
}

function notifyTab(tabId, message) {
  // The popup might be the only thing open (no content script alive in
  // this tab to receive it) - a missing receiving end is expected, not
  // an error worth surfacing.
  chrome.tabs.sendMessage(tabId, message).catch(() => {})
}

async function getCapturedJob(jobUrl) {
  const { [CAPTURED_JOBS_KEY]: jobs } = await chrome.storage.local.get(CAPTURED_JOBS_KEY)
  return jobs?.[jobUrl] ?? null
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
