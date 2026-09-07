// Scraper + auto-save for VietnamWorks job postings.
//
// VietnamWorks renders everything else (salary, location, apply button)
// through styled-components with build-hashed class names like
// "sc-953ea32e-0 eZdGQB" - there is no stable CSS selector for them, and
// one would break on their next deploy anyway. Instead this reads the
// schema.org JobPosting JSON-LD block every listing embeds for Google
// Jobs/SEO (verified against a live posting on 2026-09-06) - a page
// meant to be machine-read, and far less likely to change shape than
// their visual markup.

function readJobPostingJsonLd() {
  const scripts = document.querySelectorAll('script[type="application/ld+json"]')
  for (const script of scripts) {
    try {
      const data = JSON.parse(script.textContent)
      if (data && data['@type'] === 'JobPosting') return data
    } catch {
      // Malformed JSON-LD in this particular script tag - try the rest
      // rather than failing the whole scrape.
    }
  }
  return null
}

// schema.org's BaseSalary can be a single numeric `value`, a
// QuantitativeValue range (minValue/maxValue), or - as VietnamWorks does
// for negotiable postings - a non-numeric string like "Thương lượng"
// sitting in that same `value` slot. Only the numeric shapes map onto
// our salary_min/salary_max.
function parseSalary(baseSalary) {
  const value = baseSalary?.value
  if (value == null) return { salary_min: null, salary_max: null }

  if (typeof value === 'number') {
    return { salary_min: value, salary_max: value }
  }

  if (typeof value === 'object') {
    const min = typeof value.minValue === 'number' ? value.minValue : null
    const max = typeof value.maxValue === 'number' ? value.maxValue : null
    if (min != null || max != null) {
      return { salary_min: min, salary_max: max ?? min }
    }
    if (typeof value.value === 'number') {
      return { salary_min: value.value, salary_max: value.value }
    }
  }

  return { salary_min: null, salary_max: null }
}

function scrapeJob() {
  const jobPosting = readJobPostingJsonLd()

  if (jobPosting) {
    return {
      company: jobPosting.hiringOrganization?.name ?? null,
      position: jobPosting.title ?? document.querySelector('h1')?.innerText?.trim() ?? null,
      location:
        jobPosting.jobLocation?.address?.addressLocality ??
        jobPosting.jobLocation?.address?.addressRegion ??
        null,
      ...parseSalary(jobPosting.baseSalary),
      job_url: window.location.href,
    }
  }

  // No JSON-LD on this page (e.g. an expired/removed listing, or
  // VietnamWorks drops it from some page type) - <h1> is the only other
  // reasonably stable thing to reach for.
  return {
    company: null,
    position: document.querySelector('h1')?.innerText?.trim() ?? null,
    location: null,
    salary_min: null,
    salary_max: null,
    job_url: window.location.href,
  }
}

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message.type === 'SCRAPE_JOB') {
    sendResponse({ ok: true, job: scrapeJob() })
  }
  return false
})

// --- Auto-save on "Lưu công việc này" (Save) / "Nộp đơn" (Apply) ------
//
// Two independent triggers, tracked against the same job so they don't
// create duplicate LwkApply entries for one posting:
//   - Save button click -> confirmed  => create as status "saved"
//   - Apply button click -> confirmed => if this job was already saved,
//     PATCH that row to "applied" + today's date instead of creating a
//     second one; otherwise create directly as "applied" (the existing
//     behavior for a bare apply with no prior save).
//
// IMPORTANT CALIBRATION NOTE: both button selectors below are real
// (read from a live posting on 2026-09-06 - Apply is a visible-text
// button with class "apply-btn", Save is an icon-only button identified
// by aria-label="Lưu công việc này"), but what happens *after* a
// successful click is not verified - that needs a real, logged-in
// VietnamWorks account submitting/saving for real, which wasn't
// available to test against. So rather than guess at their internal
// API, both SAVE_SIGNALS/APPLY_SIGNALS below watch the *page* for a
// plausible completion signal: the clicked button's aria-label or
// disabled state changing, or new text matching a "success" pattern
// appearing nearby. Confirmed already: clicking Save while logged out
// of VietnamWorks (not LwkApply - their own session) opens a login
// modal rather than saving - neither pattern matches that modal's text,
// so it correctly won't false-positive, but the real post-login success
// state is still a guess. Try both buttons on a real posting and tell
// me what actually happens (does the icon/aria-label change? does a
// toast appear? what does devtools' Network tab show?) so detection can
// be tightened.
const APPLY_BUTTON_SELECTOR = '.apply-btn'
const APPLY_INTENT_PATTERN = /nộp đơn|ứng tuyển/i
const SAVE_ARIA_PATTERN = /lưu công việc/i
const CONFIRMATION_WINDOW_MS = 20_000
const CAPTURED_JOBS_KEY = 'lwkapply_captured_jobs'
const MAX_TRACKED_JOBS = 500

const APPLY_SIGNALS = {
  successTextPattern:
    /(ứng tuyển|nộp (đơn|hồ sơ)).{0,20}thành công|đã ứng tuyển|đã nộp đơn/i,
  ariaChangePattern: /đã ứng tuyển|đã nộp đơn/i,
}

const SAVE_SIGNALS = {
  successTextPattern: /đã lưu (công việc|tin)|lưu (tin|việc làm) thành công/i,
  ariaChangePattern: /bỏ lưu|đã lưu|hủy lưu/i,
}

function isApplyButton(target) {
  if (!(target instanceof Element)) return false
  const button = target.closest(APPLY_BUTTON_SELECTOR) ?? target.closest('button,a')
  if (!button) return false
  if (button.matches(APPLY_BUTTON_SELECTOR)) return true
  const text = button.innerText ?? ''
  return text.trim().length < 30 && APPLY_INTENT_PATTERN.test(text)
}

function isSaveButton(target) {
  if (!(target instanceof Element)) return false
  const button = target.closest('button,a')
  const aria = button?.getAttribute('aria-label') ?? ''
  return SAVE_ARIA_PATTERN.test(aria)
}

// Resolves true if a success signal shows up within the window, false
// on timeout. Watches the clicked button's own aria-label/disabled
// state (via an attribute observer, since a toggle button like Save is
// far more likely to flip an attribute than replace its text) and any
// newly-added page text, rather than re-scanning the whole page on
// every mutation.
function watchForActionConfirmation(clickedButton, { successTextPattern, ariaChangePattern }) {
  return new Promise((resolve) => {
    let settled = false
    const initialAria = clickedButton?.getAttribute('aria-label') ?? null

    const finish = (success) => {
      if (settled) return
      settled = true
      observer.disconnect()
      clearTimeout(timer)
      resolve(success)
    }

    const buttonNowConfirms = () => {
      if (!clickedButton) return false
      if (clickedButton.disabled) return true
      const aria = clickedButton.getAttribute('aria-label')
      if (aria && aria !== initialAria && ariaChangePattern.test(aria)) return true
      return successTextPattern.test(clickedButton.innerText ?? '')
    }

    const observer = new MutationObserver((mutations) => {
      if (buttonNowConfirms()) {
        finish(true)
        return
      }
      for (const mutation of mutations) {
        for (const node of mutation.addedNodes) {
          const text = node.nodeType === Node.TEXT_NODE ? node.textContent : node.innerText
          if (text && successTextPattern.test(text)) {
            finish(true)
            return
          }
        }
      }
    })

    observer.observe(document.body, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ['aria-label', 'disabled'],
    })
    const timer = setTimeout(() => finish(false), CONFIRMATION_WINDOW_MS)
  })
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
    // Object key order is insertion order for string keys, so the
    // oldest-tracked jobs are simply the first N keys.
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

function todayLocalIsoDate() {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

function scrapedPayload(jobUrl) {
  const job = scrapeJob()
  if (!job.company || !job.position) return null // guaranteed 422 otherwise
  return {
    company: job.company,
    position: job.position,
    location: job.location,
    salary_min: job.salary_min,
    salary_max: job.salary_max,
    job_url: jobUrl,
    notes: null,
    source: 'vietnamworks',
  }
}

async function handleSaveConfirmed(jobUrl) {
  if (await getCapturedJob(jobUrl)) return // already tracked either way

  const payload = scrapedPayload(jobUrl)
  if (!payload) return

  const result = await chrome.runtime.sendMessage({ type: 'CREATE_APPLICATION', payload })
  if (!result.ok) {
    showToast(`Couldn't save to LwkApply: ${result.error}`)
    return
  }

  await setCapturedJob(jobUrl, { applicationId: result.application.id, status: 'saved' })
  showToast('Saved to LwkApply', {
    undoLabel: 'Undo',
    onUndo: async () => {
      await chrome.runtime.sendMessage({
        type: 'DELETE_APPLICATION',
        applicationId: result.application.id,
      })
      await deleteCapturedJob(jobUrl)
    },
  })
}

async function handleApplyConfirmed(jobUrl) {
  const existing = await getCapturedJob(jobUrl)
  if (existing?.status === 'applied') return // already recorded, don't double-fire

  if (existing?.status === 'saved') {
    const { applicationId } = existing
    const result = await chrome.runtime.sendMessage({
      type: 'UPDATE_APPLICATION',
      applicationId,
      updates: { status: 'applied', applied_date: todayLocalIsoDate() },
    })
    if (!result.ok) {
      showToast(`Couldn't update LwkApply: ${result.error}`)
      return
    }
    await setCapturedJob(jobUrl, { applicationId, status: 'applied' })
    showToast('Marked as Applied on LwkApply', {
      undoLabel: 'Undo',
      onUndo: async () => {
        await chrome.runtime.sendMessage({
          type: 'UPDATE_APPLICATION',
          applicationId,
          updates: { status: 'saved', applied_date: null },
        })
        await setCapturedJob(jobUrl, { applicationId, status: 'saved' })
      },
    })
    return
  }

  // No prior save on this job - create it directly as applied.
  const payload = scrapedPayload(jobUrl)
  if (!payload) return
  payload.status = 'applied'
  payload.applied_date = todayLocalIsoDate()

  const result = await chrome.runtime.sendMessage({ type: 'CREATE_APPLICATION', payload })
  if (!result.ok) {
    showToast(`Couldn't auto-save to LwkApply: ${result.error}`)
    return
  }

  await setCapturedJob(jobUrl, { applicationId: result.application.id, status: 'applied' })
  showToast('Saved to LwkApply as Applied', {
    undoLabel: 'Undo',
    onUndo: async () => {
      await chrome.runtime.sendMessage({
        type: 'DELETE_APPLICATION',
        applicationId: result.application.id,
      })
      await deleteCapturedJob(jobUrl)
    },
  })
}

document.addEventListener(
  'click',
  async (event) => {
    const isApply = isApplyButton(event.target)
    const isSave = !isApply && isSaveButton(event.target)
    if (!isApply && !isSave) return

    const authState = await chrome.runtime.sendMessage({ type: 'GET_AUTH_STATE' })
    if (!authState?.loggedIn) return

    const jobUrl = window.location.href
    const clickedButton = event.target.closest('button,a')
    const signals = isApply ? APPLY_SIGNALS : SAVE_SIGNALS
    const confirmed = await watchForActionConfirmation(clickedButton, signals)
    if (!confirmed) return

    if (isApply) {
      await handleApplyConfirmed(jobUrl)
    } else {
      await handleSaveConfirmed(jobUrl)
    }
  },
  true, // capture phase, so this still observes the click even if the
  // page's own handler later calls stopPropagation()
)

function showToast(message, { undoLabel, onUndo } = {}) {
  const host = document.createElement('div')
  document.body.appendChild(host)
  const shadow = host.attachShadow({ mode: 'open' })

  shadow.innerHTML = `
    <style>
      :host { all: initial; }
      .toast {
        position: fixed;
        bottom: 20px;
        right: 20px;
        z-index: 2147483647;
        display: flex;
        align-items: center;
        gap: 12px;
        padding: 10px 14px;
        border-radius: 8px;
        background: #1f2328;
        color: #fff;
        font: 13px/1.4 -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
        box-shadow: 0 4px 12px rgba(0, 0, 0, 0.25);
      }
      button {
        background: none;
        border: none;
        color: #8ab4f8;
        font: inherit;
        font-weight: 600;
        cursor: pointer;
        padding: 0;
      }
    </style>
    <div class="toast">
      <span></span>
      ${undoLabel ? '<button type="button"></button>' : ''}
    </div>
  `
  shadow.querySelector('span').textContent = message
  const button = shadow.querySelector('button')
  if (button && undoLabel) {
    button.textContent = undoLabel
    button.addEventListener('click', async () => {
      await onUndo?.()
      host.remove()
    })
  }

  setTimeout(() => host.remove(), undoLabel ? 8000 : 5000)
}
