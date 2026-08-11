/**
 * Best-effort browser-reported IANA timezone name, sent to the backend on
 * register/login/refresh so `User.timezone` stays current without a
 * dedicated settings-screen picker — see TODO.md's reminder-system plan.
 * Backend validation (app/utils/timezone.py) is the actual source of
 * truth for "is this a real IANA name"; this just best-effort reports
 * whatever the browser gives back, and returns undefined rather than
 * throwing if `Intl` is unavailable/misbehaves for any reason — an
 * unreported timezone should never block login/register.
 */
export function getBrowserTimezone(): string | undefined {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone
  } catch {
    return undefined
  }
}
