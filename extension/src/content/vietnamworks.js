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

// schema.org's BaseSalary.value can be a plain number, a
// QuantitativeValue range (minValue/maxValue), or a string. That string
// case covers two very different things on VietnamWorks: "Thương
// lượng" (negotiable - no digits at all, correctly null) and, verified
// against a real listing ("Senior Web Developer - AI and Digital
// Solutions", 2094252-jv), a pre-formatted range like
// "$ 1,200-1,800 /tháng" that DOES carry real numbers, just not in a
// numeric field. Pulling every digit run out of the string and taking
// the min/max of them handles both a real range and a single figure
// (e.g. "Up to $2,000") the same way, and naturally falls back to
// null/null when there's nothing numeric in it at all.
function parseSalaryFromString(text) {
  const numbers = text.match(/\d[\d,.]*/g)
  if (!numbers) return { salary_min: null, salary_max: null }

  const parsed = numbers
    .map((n) => Number(n.replace(/[,.]/g, '')))
    .filter((n) => Number.isFinite(n) && n > 0)
  if (parsed.length === 0) return { salary_min: null, salary_max: null }

  return { salary_min: Math.min(...parsed), salary_max: Math.max(...parsed) }
}

function parseSalary(baseSalary) {
  const value = baseSalary?.value
  if (value == null) return { salary_min: null, salary_max: null }

  if (typeof value === 'number') {
    return { salary_min: value, salary_max: value }
  }

  if (typeof value === 'string') {
    return parseSalaryFromString(value)
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
    if (typeof value.value === 'string') {
      return parseSalaryFromString(value.value)
    }
  }

  return { salary_min: null, salary_max: null }
}

// Mirrors backend/app/models/application.py::SalaryCurrency. Trusts
// baseSalary.currency when it's one of these; otherwise omits the
// field entirely from the scrape (see scrapedPayload) so the backend's
// own USD default applies, rather than sending a value that would fail
// ApplicationCreate's validation. Not independently verified against a
// non-USD listing - every real posting checked so far reported "USD"
// regardless of whether the displayed figure was USD or VND, so this
// may be boilerplate on VietnamWorks' end rather than reliably accurate
// for VND-denominated postings.
const SALARY_CURRENCIES = new Set([
  'USD', 'EUR', 'GBP', 'CAD', 'AUD', 'NZD', 'CHF', 'SEK', 'NOK', 'DKK',
  'ISK', 'PLN', 'CZK', 'HUF', 'RON', 'UAH', 'RUB', 'TRY', 'ILS', 'AED',
  'SAR', 'EGP', 'NGN', 'KES', 'ZAR', 'INR', 'PKR', 'BDT', 'CNY', 'JPY',
  'KRW', 'TWD', 'HKD', 'SGD', 'MYR', 'THB', 'VND', 'IDR', 'PHP', 'BRL',
  'MXN', 'ARS', 'CLP', 'COP',
])

function parseSalaryCurrency(baseSalary) {
  const currency = baseSalary?.currency
  if (typeof currency !== 'string') return null
  const upper = currency.toUpperCase()
  return SALARY_CURRENCIES.has(upper) ? upper : null
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
      salary_currency: parseSalaryCurrency(jobPosting.baseSalary),
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
    salary_currency: null,
    salary_min: null,
    salary_max: null,
    job_url: window.location.href,
  }
}

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message.type === 'SCRAPE_JOB') {
    sendResponse({ ok: true, job: scrapeJob() })
    return false
  }
  if (message.type === 'AUTO_SAVE_RESULT') {
    handleAutoSaveResult(message)
    return false
  }
  return false
})

function handleAutoSaveResult(message) {
  if (!message.ok) {
    showToast(message.error)
    return
  }
  const undo = message.undo
  showToast(message.message, undo ? { undoLabel: 'Undo', onUndo: () => performUndo(undo) } : undefined)
}

// Two shapes coming from background.js: "delete" undoes a create (the
// Save flow), "recreate" undoes a delete (the Unsave flow) by posting
// the same job data again.
async function performUndo(undo) {
  if (undo.kind === 'delete') {
    await chrome.runtime.sendMessage({
      type: 'DELETE_APPLICATION',
      applicationId: undo.applicationId,
    })
    await deleteCapturedJob(undo.jobUrl)
    return
  }

  const result = await chrome.runtime.sendMessage({
    type: 'CREATE_APPLICATION',
    payload: undo.payload,
  })
  if (result.ok) {
    await setCapturedJob(undo.jobUrl, { applicationId: result.application.id, status: 'saved' })
  }
}

// --- Auto-save on "Nộp đơn" (Apply) -------------------------------------
//
// Save ("Lưu công việc này") needs nothing here at all - see
// background.js's webRequest listener, which detects and handles it
// entirely from the confirmed POST .../save-job network call, with no
// dependency on which element was clicked or what it's labeled. That
// replaced an earlier version of this file that also matched Save's
// aria-label as a click trigger - redundant once the network signal
// alone is a complete trigger, and worth removing rather than keeping
// two mechanisms that could disagree.
//
// Apply has no verified network endpoint yet, so it still relies on the
// DOM heuristic below. If this job was already saved (tracked in
// CAPTURED_JOBS_KEY, written by background.js's Save flow), a confirmed
// Apply click PATCHes that same row to "applied" + today's date instead
// of creating a second entry; otherwise it creates directly as
// "applied" (a bare apply with no prior save).
//
// CALIBRATION NOTE: APPLY_SIGNALS watches the clicked button's
// aria-label/disabled state and nearby added text for a plausible
// completion signal, but what a real successful apply actually looks
// like on-page is unverified.
const APPLY_BUTTON_SELECTOR = '.apply-btn'
const APPLY_INTENT_PATTERN = /nộp đơn|ứng tuyển/i
const CONFIRMATION_WINDOW_MS = 20_000
const CAPTURED_JOBS_KEY = 'lwkapply_captured_jobs'
const MAX_TRACKED_JOBS = 500

const APPLY_SIGNALS = {
  successTextPattern:
    /(ứng tuyển|nộp (đơn|hồ sơ)).{0,20}thành công|đã ứng tuyển|đã nộp đơn/i,
  ariaChangePattern: /đã ứng tuyển|đã nộp đơn/i,
}

function isApplyButton(target) {
  if (!(target instanceof Element)) return false
  const button = target.closest(APPLY_BUTTON_SELECTOR) ?? target.closest('button,a')
  if (!button) return false
  if (button.matches(APPLY_BUTTON_SELECTOR)) return true
  const text = button.innerText ?? ''
  return text.trim().length < 30 && APPLY_INTENT_PATTERN.test(text)
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
    // Omitted entirely when unknown rather than sent as null -
    // ApplicationCreate's salary_currency has no None branch, it just
    // defaults to USD when the key is absent.
    ...(job.salary_currency ? { salary_currency: job.salary_currency } : {}),
    job_url: jobUrl,
    notes: null,
    source: 'vietnamworks',
  }
}

async function createAsApplied(jobUrl) {
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
      if (result.status === 404) {
        // Deleted through some other channel (the web app, another
        // device) since we last saw it - the tracked reference is
        // stale, not this apply. Clear it and fall through to create
        // fresh, same as a bare apply with no prior save.
        await deleteCapturedJob(jobUrl)
        await createAsApplied(jobUrl)
        return
      }
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
  await createAsApplied(jobUrl)
}

document.addEventListener(
  'click',
  async (event) => {
    if (!isApplyButton(event.target)) return

    // Cheap, synchronous guard before any async work: an apply-like
    // click on a search-results or list page (each job card is its own
    // mini listing) has no single JobPosting to scrape here - skip
    // rather than risk capturing the wrong job's data.
    if (!readJobPostingJsonLd()) return

    const authState = await chrome.runtime.sendMessage({ type: 'GET_AUTH_STATE' })
    if (!authState?.loggedIn) return

    const jobUrl = window.location.href
    const clickedButton = event.target.closest('button,a')
    const confirmed = await watchForActionConfirmation(clickedButton, APPLY_SIGNALS)
    if (!confirmed) return
    await handleApplyConfirmed(jobUrl)
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
