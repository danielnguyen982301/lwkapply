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

    // Used by the popup's manual "This job" capture mode - the
    // network-driven Save/Unsave/Apply flows below call
    // upsertByExternalId/applyByExternalId directly instead, no message
    // round-trip needed since they're already in this same context.
    case 'UPSERT_BY_EXTERNAL_ID':
      return upsertByExternalId(message.payload)

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

// PUT/PATCH/DELETE /applications/by-external-id - the backend is the
// only thing that knows whether a (source, external_id) row already
// exists, so these are the real dedup mechanism; nothing here or in
// the content script keeps its own copy of that answer any more (see
// the network-driven save/unsave section below for why job_url alone
// was never trustworthy for this).
async function upsertByExternalId(payload) {
  const response = await auth.apiFetch('/applications/by-external-id', {
    method: 'PUT',
    body: JSON.stringify(payload),
  })
  const body = await parseJsonSafe(response)
  if (!response.ok) return { ok: false, error: firstErrorMessage(body) }
  if (!body) return { ok: false, error: 'Unexpected response from server.' }
  return { ok: true, application: body.application, action: body.action }
}

async function applyByExternalId(payload) {
  const response = await auth.apiFetch('/applications/by-external-id', {
    method: 'PATCH',
    body: JSON.stringify(payload),
  })
  const body = await parseJsonSafe(response)
  if (!response.ok) return { ok: false, error: firstErrorMessage(body) }
  if (!body) return { ok: false, error: 'Unexpected response from server.' }
  return { ok: true, application: body.application, action: body.action }
}

async function deleteByExternalId(source, externalId) {
  const query = new URLSearchParams({ source, external_id: externalId })
  const response = await auth.apiFetch(`/applications/by-external-id?${query}`, {
    method: 'DELETE',
  })
  const body = await parseJsonSafe(response)
  if (!response.ok) return { ok: false, error: firstErrorMessage(body) }
  if (!body) return { ok: false, error: 'Unexpected response from server.' }
  return { ok: true, action: body.action }
}

// --- Network-driven save/unsave ------------------------------------------
//
// Verified against real clicks: "Lưu công việc này" (Save) fires POST
// .../save-job, and the same toggle again ("Unsave") fires POST
// .../unsave-job - both with a JSON body of {"jobId": <number>}, which
// is VietnamWorks' own internal identifier for the posting (confirmed
// against a real request; it matches the numeric id in that job's URL,
// e.g. .../senior-web-developer-...-2094252-jv -> jobId 2094252). This
// is a far better identity than job_url: the same posting's URL varies
// by referral query string (?source=searchResults&...), and even its
// slug could change someday while the id stays put - see
// app/models/application.py::Application.external_id's docstring on
// the backend for the same reasoning.
//
// Reading it needs a second webRequest event: onCompleted (used below
// to confirm success) never exposes what was *sent*, only the
// response's status code. onBeforeRequest with the "requestBody" extra
// info does expose it - correlated to the matching onCompleted call via
// requestId, the one field guaranteed stable across a single request's
// lifecycle events.
//
// Apply (Nộp đơn) works the same way, verified against a real
// submission: POST .../v2.0/job/apply-multiple, form-encoded (not JSON
// like save/unsave) with a jobIds[] field - "apply-multiple" suggests
// VietnamWorks built this to submit several jobs in one call (a
// "quick-apply to similar jobs" style flow), which this deliberately
// does not attempt to handle: with more than one id in the array there
// is no single job on the current page to scrape data for, so it's
// skipped rather than guessed at (see extractSingleJobIdFromFormData).
const SAVE_JOB_ENDPOINT = 'https://ms.vietnamworks.com/api-gateway/v1.0/save-job*'
const UNSAVE_JOB_ENDPOINT = 'https://ms.vietnamworks.com/api-gateway/v1.0/unsave-job*'
const APPLY_JOB_ENDPOINT = 'https://ms.vietnamworks.com/api-gateway/v2.0/job/apply-multiple*'
const SOURCE = 'vietnamworks'

const pendingJobIds = new Map() // requestId -> jobId

chrome.webRequest.onBeforeRequest.addListener(
  (details) => {
    const jobId = extractJobIdFromJsonBody(details.requestBody)
    if (jobId != null) pendingJobIds.set(details.requestId, jobId)
  },
  { urls: [SAVE_JOB_ENDPOINT, UNSAVE_JOB_ENDPOINT] },
  ['requestBody'],
)

chrome.webRequest.onBeforeRequest.addListener(
  (details) => {
    const jobId = extractSingleJobIdFromFormData(details.requestBody)
    if (jobId != null) pendingJobIds.set(details.requestId, jobId)
  },
  { urls: [APPLY_JOB_ENDPOINT] },
  ['requestBody'],
)

function extractJobIdFromJsonBody(requestBody) {
  try {
    const bytes = requestBody?.raw?.[0]?.bytes
    if (!bytes) return null
    const text = new TextDecoder().decode(bytes)
    const jobId = JSON.parse(text)?.jobId
    return jobId == null ? null : String(jobId)
  } catch {
    return null // not JSON, or no jobId in it - nothing usable
  }
}

function extractSingleJobIdFromFormData(requestBody) {
  const values = requestBody?.formData?.['jobIds[]']
  if (!Array.isArray(values) || values.length !== 1) return null
  return values[0]
}

chrome.webRequest.onCompleted.addListener(
  (details) => onConfirmedPost(details, handleConfirmedSave),
  { urls: [SAVE_JOB_ENDPOINT] },
)

chrome.webRequest.onCompleted.addListener(
  (details) => onConfirmedPost(details, handleConfirmedUnsave),
  { urls: [UNSAVE_JOB_ENDPOINT] },
)

chrome.webRequest.onCompleted.addListener(
  (details) => onConfirmedPost(details, handleConfirmedApply),
  { urls: [APPLY_JOB_ENDPOINT] },
)

function onConfirmedPost(details, handler) {
  const jobId = pendingJobIds.get(details.requestId)
  pendingJobIds.delete(details.requestId)
  if (details.method !== 'POST') return
  if (details.statusCode < 200 || details.statusCode >= 300) return
  if (details.tabId < 0) return // not associated with a tab - nothing to scrape
  if (jobId == null) return // couldn't read jobId from this request - nothing to key by
  handler(details.tabId, jobId)
}

async function scrapeTab(tabId) {
  try {
    const response = await chrome.tabs.sendMessage(tabId, { type: 'SCRAPE_JOB' })
    return response?.job ?? null
  } catch {
    return null // no content script alive in this tab
  }
}

async function handleConfirmedSave(tabId, jobId) {
  if (!(await auth.isLoggedIn())) {
    notifyTab(tabId, {
      type: 'AUTO_SAVE_RESULT',
      ok: false,
      error: 'Log in to LwkApply (click the toolbar icon) to auto-save this.',
    })
    return
  }

  const job = await scrapeTab(tabId)
  if (!job?.company || !job?.position) return // not enough to satisfy the backend

  const payload = {
    company: job.company,
    position: job.position,
    location: job.location,
    salary_min: job.salary_min,
    salary_max: job.salary_max,
    ...(job.salary_currency ? { salary_currency: job.salary_currency } : {}),
    job_url: job.job_url,
    notes: null,
    source: SOURCE,
    external_id: jobId,
  }

  const result = await upsertByExternalId(payload)
  if (!result.ok) {
    notifyTab(tabId, {
      type: 'AUTO_SAVE_RESULT',
      ok: false,
      error: `Couldn't save to LwkApply: ${result.error}`,
    })
    return
  }
  if (result.action === 'unchanged') return // already tracked - nothing new happened

  notifyTab(tabId, { type: 'AUTO_SAVE_RESULT', ok: true, message: 'Saved to LwkApply' })
}

// Only removes what's tracked as "saved" (the backend enforces this,
// not this handler - see DELETE /applications/by-external-id). A job
// already marked "applied" (or any other status) stays untouched:
// unsaving on VietnamWorks says nothing about withdrawing an
// application. A job never tracked at all is likewise a no-op.
async function handleConfirmedUnsave(tabId, jobId) {
  if (!(await auth.isLoggedIn())) {
    notifyTab(tabId, {
      type: 'AUTO_SAVE_RESULT',
      ok: false,
      error: 'Log in to LwkApply (click the toolbar icon) to sync this removal.',
    })
    return
  }

  const result = await deleteByExternalId(SOURCE, jobId)
  if (!result.ok) {
    notifyTab(tabId, {
      type: 'AUTO_SAVE_RESULT',
      ok: false,
      error: `Couldn't remove from LwkApply: ${result.error}`,
    })
    return
  }
  if (result.action !== 'deleted') return // nothing tracked, or kept as-is - nothing to announce

  notifyTab(tabId, { type: 'AUTO_SAVE_RESULT', ok: true, message: 'Removed from LwkApply' })
}

// Mirrors upsertByExternalId's shape, but calls applyByExternalId
// (PATCH), which - like the backend endpoint it wraps - makes the
// entire "saved -> applied, other status -> leave alone, nothing
// tracked -> create fresh as applied" decision itself. This function
// only has to report whichever of those already happened.
async function handleConfirmedApply(tabId, jobId) {
  if (!(await auth.isLoggedIn())) {
    notifyTab(tabId, {
      type: 'AUTO_SAVE_RESULT',
      ok: false,
      error: 'Log in to LwkApply (click the toolbar icon) to auto-save this.',
    })
    return
  }

  const job = await scrapeTab(tabId)
  if (!job?.company || !job?.position) return // not enough to satisfy the backend

  const payload = {
    company: job.company,
    position: job.position,
    location: job.location,
    salary_min: job.salary_min,
    salary_max: job.salary_max,
    ...(job.salary_currency ? { salary_currency: job.salary_currency } : {}),
    job_url: job.job_url,
    notes: null,
    source: SOURCE,
    external_id: jobId,
  }

  const result = await applyByExternalId(payload)
  if (!result.ok) {
    notifyTab(tabId, {
      type: 'AUTO_SAVE_RESULT',
      ok: false,
      error: `Couldn't update LwkApply: ${result.error}`,
    })
    return
  }
  if (result.action === 'unchanged') return // already applied, or some other status - left alone

  const message =
    result.action === 'created' ? 'Saved to LwkApply as Applied' : 'Marked as Applied on LwkApply'
  notifyTab(tabId, { type: 'AUTO_SAVE_RESULT', ok: true, message })
}

function notifyTab(tabId, message) {
  // The popup might be the only thing open (no content script alive in
  // this tab to receive it) - a missing receiving end is expected, not
  // an error worth surfacing.
  chrome.tabs.sendMessage(tabId, message).catch(() => {})
}
