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

// --- Auto-save on a real "Nộp đơn" (Apply) submission -----------------
//
// IMPORTANT CALIBRATION NOTE: I built this against the page's *visible*
// apply button and DOM structure (see scrapeJob() above), but never
// completed a real apply flow to verify what actually happens after
// submission - that needs a real VietnamWorks account, which I don't
// have and can't fabricate one for. So rather than guess their internal
// apply API endpoint (a URL I'd be making up, and a silent no-op if
// wrong), this watches the *page* for a plausible completion signal:
// the clicked button's own text/disabled state changing, or new text
// matching a "success" pattern appearing anywhere on the page shortly
// after the click. If a real apply produces neither - e.g. VietnamWorks
// redirects to a different page instead of updating this one in place -
// this silently won't fire. Please try it on a real posting and tell me
// what actually happens (does the button relabel? does a toast appear?
// does the URL change? what does devtools' Network tab show for the
// request the click fires?) so the detection can be tightened.
const APPLY_BUTTON_SELECTOR = '.apply-btn'
const APPLY_INTENT_PATTERN = /nộp đơn|ứng tuyển/i
const APPLY_SUCCESS_PATTERN =
  /(ứng tuyển|nộp (đơn|hồ sơ)).{0,20}thành công|đã ứng tuyển|đã nộp đơn/i
const CONFIRMATION_WINDOW_MS = 20_000
const CAPTURED_URLS_KEY = 'lwkapply_auto_saved_urls'
const MAX_TRACKED_URLS = 500

function isApplyButton(target) {
  if (!(target instanceof Element)) return false
  const button = target.closest(APPLY_BUTTON_SELECTOR) ?? target.closest('button,a')
  if (!button) return false
  if (button.matches(APPLY_BUTTON_SELECTOR)) return true
  const text = button.innerText ?? ''
  return text.trim().length < 30 && APPLY_INTENT_PATTERN.test(text)
}

// Resolves true if a success signal shows up within the window, false
// on timeout. Only inspects nodes actually added by each mutation batch
// (not a full document.body.innerText re-scan every time) to keep this
// cheap during whatever DOM churn the click itself causes.
function watchForApplySuccess(clickedButton) {
  return new Promise((resolve) => {
    let settled = false
    const finish = (success) => {
      if (settled) return
      settled = true
      observer.disconnect()
      clearTimeout(timer)
      resolve(success)
    }

    const observer = new MutationObserver((mutations) => {
      if (clickedButton && (clickedButton.disabled || APPLY_SUCCESS_PATTERN.test(clickedButton.innerText ?? ''))) {
        finish(true)
        return
      }
      for (const mutation of mutations) {
        for (const node of mutation.addedNodes) {
          const text = node.nodeType === Node.TEXT_NODE ? node.textContent : node.innerText
          if (text && APPLY_SUCCESS_PATTERN.test(text)) {
            finish(true)
            return
          }
        }
      }
    })

    observer.observe(document.body, { childList: true, subtree: true })
    const timer = setTimeout(() => finish(false), CONFIRMATION_WINDOW_MS)
  })
}

async function isAlreadyCaptured(jobUrl) {
  const { [CAPTURED_URLS_KEY]: urls } = await chrome.storage.local.get(CAPTURED_URLS_KEY)
  return Array.isArray(urls) && urls.includes(jobUrl)
}

async function markCaptured(jobUrl) {
  const { [CAPTURED_URLS_KEY]: urls } = await chrome.storage.local.get(CAPTURED_URLS_KEY)
  const next = Array.isArray(urls) ? [...urls, jobUrl] : [jobUrl]
  await chrome.storage.local.set({ [CAPTURED_URLS_KEY]: next.slice(-MAX_TRACKED_URLS) })
}

function todayLocalIsoDate() {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

async function captureAndSave(jobUrl) {
  const job = scrapeJob()
  if (!job.company || !job.position) {
    // Not enough scraped to satisfy the backend's required fields -
    // skip rather than sending a request that's guaranteed to 422.
    return
  }

  const payload = {
    company: job.company,
    position: job.position,
    location: job.location,
    salary_min: job.salary_min,
    salary_max: job.salary_max,
    job_url: jobUrl,
    notes: null,
    source: 'vietnamworks',
    status: 'applied',
    applied_date: todayLocalIsoDate(),
  }

  const result = await chrome.runtime.sendMessage({ type: 'CREATE_APPLICATION', payload })
  if (!result.ok) {
    showToast(`Couldn't auto-save to LwkApply: ${result.error}`)
    return
  }

  await markCaptured(jobUrl)
  showToast('Saved to LwkApply', {
    undoLabel: 'Undo',
    onUndo: () =>
      chrome.runtime.sendMessage({
        type: 'DELETE_APPLICATION',
        applicationId: result.application.id,
      }),
  })
}

document.addEventListener(
  'click',
  async (event) => {
    if (!isApplyButton(event.target)) return

    const jobUrl = window.location.href
    const [authState, alreadyCaptured] = await Promise.all([
      chrome.runtime.sendMessage({ type: 'GET_AUTH_STATE' }),
      isAlreadyCaptured(jobUrl),
    ])
    if (!authState?.loggedIn || alreadyCaptured) return

    const clickedButton = event.target.closest(APPLY_BUTTON_SELECTOR) ?? event.target.closest('button,a')
    const success = await watchForApplySuccess(clickedButton)
    if (!success) return

    await captureAndSave(jobUrl)
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
