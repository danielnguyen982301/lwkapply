const VIETNAMWORKS_URL_PATTERN = /^https:\/\/(www\.)?vietnamworks\.com\//

const views = {
  login: document.getElementById('login-view'),
  capture: document.getElementById('capture-view'),
  unsupported: document.getElementById('unsupported-view'),
}
const logoutBtn = document.getElementById('logout-btn')

function showView(name) {
  for (const [key, el] of Object.entries(views)) {
    el.hidden = key !== name
  }
  logoutBtn.hidden = name === 'login'
}

function sendMessage(message) {
  return chrome.runtime.sendMessage(message)
}

function fillForm(job) {
  document.getElementById('field-company').value = job?.company ?? ''
  document.getElementById('field-position').value = job?.position ?? ''
  document.getElementById('field-location').value = job?.location ?? ''
  document.getElementById('field-salary-min').value = job?.salary_min ?? ''
  document.getElementById('field-salary-max').value = job?.salary_max ?? ''
  document.getElementById('field-job-url').value = job?.job_url ?? ''
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

  showView('capture')
  fillForm(job)
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
    job_url: document.getElementById('field-job-url').value || null,
    notes: document.getElementById('field-notes').value || null,
    source: 'vietnamworks',
  }

  const result = await sendMessage({ type: 'CREATE_APPLICATION', payload })

  if (!result.ok) {
    errorEl.textContent = result.error
    errorEl.hidden = false
    return
  }
  successEl.textContent = 'Saved to LwkApply.'
  successEl.hidden = false
})

logoutBtn.addEventListener('click', async () => {
  await sendMessage({ type: 'LOGOUT' })
  showView('login')
})

init()
