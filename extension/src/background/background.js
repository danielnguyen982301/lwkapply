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
  if (!response.ok) return { ok: false, status: response.status, error: firstErrorMessage(body) }
  if (!body) return { ok: false, error: 'Unexpected response from server.' }
  return { ok: true, application: body }
}

async function deleteApplication(applicationId) {
  const response = await auth.apiFetch(`/applications/${applicationId}`, { method: 'DELETE' })
  if (!response.ok) {
    const body = await parseJsonSafe(response)
    return { ok: false, status: response.status, error: firstErrorMessage(body) }
  }
  return { ok: true }
}

// Bare status check against a cached applicationId - used to tell a
// genuinely-still-tracked row (200) apart from one that's been deleted
// through some other channel since we last saw it, e.g. the web app
// (404), without fetching/discarding the full body either way.
async function getApplicationStatus(applicationId) {
  const response = await auth.apiFetch(`/applications/${applicationId}`, { method: 'GET' })
  return response.status
}

// --- Network-driven save/unsave ------------------------------------------
//
// Verified against real clicks: "Lưu công việc này" (Save) fires POST
// .../save-job, and clicking the same toggle again ("Unsave") fires
// POST .../unsave-job - both return {"meta":{"code":200,...}} on
// success. Neither listener below identifies *which element* was
// clicked; a confirmed 2xx on either endpoint, for a given tab, is by
// itself a complete signal of what just happened on that page. Each one
// asks that tab's content script what job is on the page right now
// (reusing the existing SCRAPE_JOB handler, built originally for the
// popup) and acts on that - no click listener, no DOM matching, no
// per-click coordination state.
//
// Apply has no verified network endpoint yet, so it's still the
// DOM-heuristic click listener in vietnamworks.js.
const SAVE_JOB_ENDPOINT = 'https://ms.vietnamworks.com/api-gateway/v1.0/save-job*'
const UNSAVE_JOB_ENDPOINT = 'https://ms.vietnamworks.com/api-gateway/v1.0/unsave-job*'
const CAPTURED_JOBS_KEY = 'lwkapply_captured_jobs' // must match the content script's key
const MAX_TRACKED_JOBS = 500

chrome.webRequest.onCompleted.addListener(
  (details) => onConfirmedPost(details, handleConfirmedSave),
  { urls: [SAVE_JOB_ENDPOINT] },
)

chrome.webRequest.onCompleted.addListener(
  (details) => onConfirmedPost(details, handleConfirmedUnsave),
  { urls: [UNSAVE_JOB_ENDPOINT] },
)

function onConfirmedPost(details, handler) {
  if (details.method !== 'POST') return
  if (details.statusCode < 200 || details.statusCode >= 300) return
  if (details.tabId < 0) return // not associated with a tab - nothing to scrape
  handler(details.tabId)
}

async function scrapeTab(tabId) {
  try {
    const response = await chrome.tabs.sendMessage(tabId, { type: 'SCRAPE_JOB' })
    return response?.job ?? null
  } catch {
    return null // no content script alive in this tab
  }
}

async function handleConfirmedSave(tabId) {
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

  const existing = await getCapturedJob(job.job_url)
  if (existing) {
    const status = await getApplicationStatus(existing.applicationId)
    if (status === 200) return // still tracked for real - skip
    if (status === 404) {
      // Deleted through some other channel (the web app, another
      // device) since we last saw it - the cache is stale, not the
      // save. Clear it and fall through to create a fresh one.
      await deleteCapturedJob(job.job_url)
    } else {
      return // couldn't verify (auth/network hiccup) - skip rather than risk a duplicate
    }
  }

  const payload = {
    company: job.company,
    position: job.position,
    location: job.location,
    salary_min: job.salary_min,
    salary_max: job.salary_max,
    // Omitted entirely when unknown - ApplicationCreate's
    // salary_currency has no None branch, it just defaults to USD when
    // the key is absent.
    ...(job.salary_currency ? { salary_currency: job.salary_currency } : {}),
    job_url: job.job_url,
    notes: null,
    source: 'vietnamworks',
  }

  const result = await createApplication(payload)
  if (!result.ok) {
    notifyTab(tabId, {
      type: 'AUTO_SAVE_RESULT',
      ok: false,
      error: `Couldn't save to LwkApply: ${result.error}`,
    })
    return
  }

  await setCapturedJob(job.job_url, { applicationId: result.application.id, status: 'saved' })
  notifyTab(tabId, {
    type: 'AUTO_SAVE_RESULT',
    ok: true,
    message: 'Saved to LwkApply',
    undo: { kind: 'delete', applicationId: result.application.id, jobUrl: job.job_url },
  })
}

// Only removes what we're tracking as "saved". A job already marked
// "applied" (or in any other status) stays untouched - unsaving on
// VietnamWorks says nothing about withdrawing an application, so it
// must never delete or otherwise touch a row past the saved stage. A
// job we never tracked at all (saved outside the extension, or already
// removed) is likewise left alone.
async function handleConfirmedUnsave(tabId) {
  const job = await scrapeTab(tabId)
  if (!job?.job_url) return

  const existing = await getCapturedJob(job.job_url)
  if (!existing || existing.status !== 'saved') return

  if (!(await auth.isLoggedIn())) {
    notifyTab(tabId, {
      type: 'AUTO_SAVE_RESULT',
      ok: false,
      error: 'Log in to LwkApply (click the toolbar icon) to sync this removal.',
    })
    return
  }

  const result = await deleteApplication(existing.applicationId)
  if (!result.ok) {
    if (result.status === 404) {
      // Already gone - deleted through some other channel (the web
      // app, another device) since we last saw it. The tracked
      // reference was stale, not a real failure: clear it so future
      // Save/Unsave clicks on this job start fresh instead of hitting
      // this same 404 forever. Deliberately no "Undo" here - offering
      // to recreate would resurrect a row the user removed elsewhere
      // on purpose.
      await deleteCapturedJob(job.job_url)
      notifyTab(tabId, { type: 'AUTO_SAVE_RESULT', ok: true, message: 'Removed from LwkApply' })
      return
    }
    notifyTab(tabId, {
      type: 'AUTO_SAVE_RESULT',
      ok: false,
      error: `Couldn't remove from LwkApply: ${result.error}`,
    })
    return
  }

  await deleteCapturedJob(job.job_url)
  notifyTab(tabId, {
    type: 'AUTO_SAVE_RESULT',
    ok: true,
    message: 'Removed from LwkApply',
    undo: {
      kind: 'recreate',
      jobUrl: job.job_url,
      payload: {
        company: job.company,
        position: job.position,
        location: job.location,
        salary_min: job.salary_min,
        salary_max: job.salary_max,
        ...(job.salary_currency ? { salary_currency: job.salary_currency } : {}),
        job_url: job.job_url,
        notes: null,
        source: 'vietnamworks',
      },
    },
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

async function deleteCapturedJob(jobUrl) {
  const { [CAPTURED_JOBS_KEY]: jobs } = await chrome.storage.local.get(CAPTURED_JOBS_KEY)
  if (!jobs?.[jobUrl]) return
  const next = { ...jobs }
  delete next[jobUrl]
  await chrome.storage.local.set({ [CAPTURED_JOBS_KEY]: next })
}
