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
// baseSalary.currency when it's one of these; otherwise this returns
// null, and background.js's payload-builders omit the field entirely
// rather than sending null - ApplicationCreate's salary_currency has no
// None branch, omitting the key is what lets the backend's own USD
// default apply. Not independently verified against a non-USD listing -
// every real posting checked so far reported "USD" regardless of
// whether the displayed figure was USD or VND, so this may be
// boilerplate on VietnamWorks' end rather than reliably accurate for
// VND-denominated postings.
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

// Drops the query string and fragment - verified against a real
// listing that a job's canonical page renders identically without its
// referral tracking params (?source=searchResults&searchType=2&...).
// Now that external_id is the real identity (see extractJobIdFromUrl),
// job_url is purely a "click through to the posting" convenience link,
// so there's no reason to keep noise that varies by how the user got
// there.
function canonicalJobUrl() {
  return window.location.origin + window.location.pathname
}

function scrapeJob() {
  const jobPosting = readJobPostingJsonLd()
  const jobUrl = canonicalJobUrl()

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
      job_url: jobUrl,
      external_id: extractJobIdFromUrl(jobUrl),
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
    job_url: jobUrl,
    external_id: extractJobIdFromUrl(jobUrl),
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

// pathname excludes the query string and fragment by construction, so
// this is naturally immune to a job's URL varying by referral params
// (e.g. ?source=searchResults&...) - only the id right before the
// trailing "-jv" matters. Used above for scrapeJob's external_id -
// background.js's Save/Unsave/Apply detection all read this same id
// straight out of their respective requests' bodies instead, since
// they don't need scrapeJob() to know which job was acted on, only to
// describe it (company/position/salary) once they already do.
function extractJobIdFromUrl(url) {
  const match = new URL(url).pathname.match(/-(\d+)-jv\/?$/)
  return match ? match[1] : null
}

// Three shapes coming from background.js: "delete" undoes a create
// (Save, or a bare Apply with no prior save), "revert-to-saved" undoes
// an Apply that moved an already-saved row to "applied", and "recreate"
// undoes a delete (Unsave) - going through the same upsert endpoint
// Save itself uses (keyed by the same source/external_id in
// undo.payload) rather than a plain create, so double-clicking Undo -
// or a fresh Save racing it - can't produce two rows for the same job.
async function performUndo(undo) {
  switch (undo.kind) {
    case 'delete':
      await chrome.runtime.sendMessage({
        type: 'DELETE_APPLICATION',
        applicationId: undo.applicationId,
      })
      return
    case 'revert-to-saved':
      await chrome.runtime.sendMessage({
        type: 'UPDATE_APPLICATION',
        applicationId: undo.applicationId,
        updates: { status: 'saved', applied_date: null },
      })
      return
    case 'recreate':
      await chrome.runtime.sendMessage({
        type: 'UPSERT_BY_EXTERNAL_ID',
        payload: undo.payload,
      })
      return
  }
}

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
