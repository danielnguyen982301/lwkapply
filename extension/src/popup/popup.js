const VIETNAMWORKS_URL_PATTERN = /^https:\/\/(www\.)?vietnamworks\.com\//

const views = {
  login: document.getElementById('login-view'),
  capture: document.getElementById('capture-view'),
  unsupported: document.getElementById('unsupported-view'),
}
const logoutBtn = document.getElementById('logout-btn')
const modeToggle = document.getElementById('mode-toggle')
const modeCapturedBtn = document.getElementById('mode-captured')
const modeManualBtn = document.getElementById('mode-manual')
const jobUrlField = document.getElementById('field-job-url')

function showView(name) {
  for (const [key, el] of Object.entries(views)) {
    el.hidden = key !== name
  }
  logoutBtn.hidden = name === 'login'
}

function sendMessage(message) {
  return chrome.runtime.sendMessage(message)
}

// The last scrape, kept around so switching back to "This job" mode can
// re-fill the form without asking the content script again.
let scrapedJob = null
// 'captured' locks Job URL to the scraped value and identifies the row
// by external_id (upsert semantics - edits apply to an already-tracked
// row via a follow-up update, see the submit handler, but never create
// a second row for the same posting). 'manual' has no external_id at
// all: every field including Job URL is free-form, and submitting
// always creates a brand new row - for a job this extension didn't
// capture, or a deliberate second entry (e.g. re-applying after a
// rejection).
let captureMode = 'captured'
let currentExternalId = null

function fillForm(job) {
  document.getElementById('field-company').value = job?.company ?? ''
  document.getElementById('field-position').value = job?.position ?? ''
  document.getElementById('field-location').value = job?.location ?? ''
  document.getElementById('field-salary-min').value = job?.salary_min ?? ''
  document.getElementById('field-salary-max').value = job?.salary_max ?? ''
  jobUrlField.value = job?.job_url ?? ''
}

function clearForm() {
  document.getElementById('field-company').value = ''
  document.getElementById('field-position').value = ''
  document.getElementById('field-location').value = ''
  document.getElementById('field-salary-min').value = ''
  document.getElementById('field-salary-max').value = ''
  jobUrlField.value = ''
  document.getElementById('field-notes').value = ''
}

function setMode(mode) {
  captureMode = mode
  modeCapturedBtn.setAttribute('aria-pressed', String(mode === 'captured'))
  modeManualBtn.setAttribute('aria-pressed', String(mode === 'manual'))
  jobUrlField.readOnly = mode === 'captured'

  if (mode === 'captured') {
    fillForm(scrapedJob)
    currentExternalId = scrapedJob?.external_id ?? null
  } else {
    clearForm()
    currentExternalId = null
  }
}

function numberOrNull(value) {
  return value === '' ? null : Number(value)
}

async function loadCaptureView() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true })

  if (!tab?.url || !VIETNAMWORKS_URL_PATTERN.test(tab.url)) {
    showView('unsupported')
    return
  }

  let job = null
  try {
    const response = await chrome.tabs.sendMessage(tab.id, { type: 'SCRAPE_JOB' })
    job = response?.job ?? null
  } catch {
    // Content script isn't loaded on this tab yet - most likely the page
    // was open before the extension was installed/reloaded. Reloading
    // the tab would fix it; either way there's nothing to prefill from.
  }

  scrapedJob = job
  showView('capture')

  // Only offer "This job" when there's a real id to lock it to - on a
  // VietnamWorks page that isn't a job detail page (or one whose URL
  // didn't match the expected shape), there's nothing captured to
  // offer as an alternative to entering it manually.
  if (job?.external_id) {
    modeToggle.hidden = false
    setMode('captured')
  } else {
    modeToggle.hidden = true
    setMode('manual')
  }
}

async function init() {
  const { loggedIn } = await sendMessage({ type: 'GET_AUTH_STATE' })
  if (!loggedIn) {
    showView('login')
    return
  }
  await loadCaptureView()
}

document.getElementById('login-form').addEventListener('submit', async (event) => {
  event.preventDefault()
  const errorEl = document.getElementById('login-error')
  errorEl.hidden = true

  const result = await sendMessage({
    type: 'LOGIN',
    email: document.getElementById('login-email').value,
    password: document.getElementById('login-password').value,
  })

  if (!result.ok) {
    errorEl.textContent = result.error
    errorEl.hidden = false
    return
  }
  await loadCaptureView()
})

modeCapturedBtn.addEventListener('click', () => setMode('captured'))
modeManualBtn.addEventListener('click', () => setMode('manual'))

document.getElementById('capture-form').addEventListener('submit', async (event) => {
  event.preventDefault()
  const errorEl = document.getElementById('capture-error')
  const successEl = document.getElementById('capture-success')
  errorEl.hidden = true
  successEl.hidden = true

  const payload = {
    company: document.getElementById('field-company').value,
    position: document.getElementById('field-position').value,
    location: document.getElementById('field-location').value || null,
    salary_min: numberOrNull(document.getElementById('field-salary-min').value),
    salary_max: numberOrNull(document.getElementById('field-salary-max').value),
    job_url: jobUrlField.value || null,
    notes: document.getElementById('field-notes').value || null,
    source: 'vietnamworks',
  }

  let result
  if (captureMode === 'captured' && currentExternalId) {
    result = await sendMessage({
      type: 'UPSERT_BY_EXTERNAL_ID',
      payload: { ...payload, external_id: currentExternalId },
    })

    if (result.ok && result.action === 'unchanged') {
      // The upsert intentionally never overwrites an already-tracked
      // row (the auto-detected Save/Apply flows depend on that to
      // avoid clobbering edits made elsewhere with a thinner re-scrape)
      // - so applying what the user typed in *this* form needs an
      // explicit follow-up update, or their edits would silently vanish.
      const updateResult = await sendMessage({
        type: 'UPDATE_APPLICATION',
        applicationId: result.application.id,
        updates: {
          company: payload.company,
          position: payload.position,
          location: payload.location,
          salary_min: payload.salary_min,
          salary_max: payload.salary_max,
          notes: payload.notes,
        },
      })
      result = updateResult.ok
        ? { ok: true, application: updateResult.application, action: 'updated' }
        : updateResult
    }
  } else {
    // Manual mode, or "captured" mode without a usable id (shouldn't
    // happen - the toggle is hidden in that case - but fall back to a
    // plain create rather than silently doing nothing).
    result = await sendMessage({ type: 'CREATE_APPLICATION', payload })
  }

  if (!result.ok) {
    errorEl.textContent = result.error
    errorEl.hidden = false
    return
  }
  successEl.textContent =
    result.action === 'updated' ? 'Updated the saved application.' : 'Saved to LwkApply.'
  successEl.hidden = false
})

logoutBtn.addEventListener('click', async () => {
  await sendMessage({ type: 'LOGOUT' })
  showView('login')
})

init()
