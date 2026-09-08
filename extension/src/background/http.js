// A non-2xx response isn't guaranteed to be JSON - an unhandled
// exception on the backend returns Starlette's default plain-text
// "Internal Server Error" body, and a proxy/gateway in front of it could
// just as easily return an HTML error page. response.json() throws on
// either, which without this surfaces as a raw "Unexpected token 'I',
// "Internal S"... is not valid JSON" instead of a message worth showing
// a user.
export async function parseJsonSafe(response) {
  const text = await response.text()
  if (!text) return null
  try {
    return JSON.parse(text)
  } catch {
    return null
  }
}

export function firstErrorMessage(body, fallback = 'Something went wrong. Please try again.') {
  if (typeof body?.detail === 'string') return body.detail
  if (Array.isArray(body?.detail) && body.detail[0]?.msg) return body.detail[0].msg
  return fallback
}
