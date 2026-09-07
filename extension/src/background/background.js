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

    case 'CREATE_APPLICATION': {
      const response = await auth.apiFetch('/applications', {
        method: 'POST',
        body: JSON.stringify(message.payload),
      })
      const body = await parseJsonSafe(response)
      if (!response.ok) {
        return { ok: false, error: firstErrorMessage(body) }
      }
      if (!body) {
        return { ok: false, error: 'Unexpected response from server.' }
      }
      return { ok: true, application: body }
    }

    case 'UPDATE_APPLICATION': {
      const response = await auth.apiFetch(`/applications/${message.applicationId}`, {
        method: 'PATCH',
        body: JSON.stringify(message.updates),
      })
      const body = await parseJsonSafe(response)
      if (!response.ok) {
        return { ok: false, error: firstErrorMessage(body) }
      }
      if (!body) {
        return { ok: false, error: 'Unexpected response from server.' }
      }
      return { ok: true, application: body }
    }

    case 'DELETE_APPLICATION': {
      const response = await auth.apiFetch(`/applications/${message.applicationId}`, {
        method: 'DELETE',
      })
      if (!response.ok) {
        const body = await parseJsonSafe(response)
        return { ok: false, error: firstErrorMessage(body) }
      }
      return { ok: true }
    }

    default:
      return { ok: false, error: `Unknown message type: ${message.type}` }
  }
}
