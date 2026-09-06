import * as auth from './auth.js'

// Popup (and, in future, an injected page button) talk to the API only
// through this router - neither the popup nor the content script ever
// touches a token directly, so a compromised job-site page can't read
// them via the content script's execution context.
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

    case 'CREATE_APPLICATION': {
      const response = await auth.apiFetch('/applications', {
        method: 'POST',
        body: JSON.stringify(message.payload),
      })
      const body = await response.json()
      if (!response.ok) {
        return { ok: false, error: firstErrorMessage(body) }
      }
      return { ok: true, application: body }
    }

    default:
      return { ok: false, error: `Unknown message type: ${message.type}` }
  }
}

function firstErrorMessage(body) {
  if (typeof body?.detail === 'string') return body.detail
  if (Array.isArray(body?.detail) && body.detail[0]?.msg) return body.detail[0].msg
  return 'Something went wrong. Please try again.'
}
