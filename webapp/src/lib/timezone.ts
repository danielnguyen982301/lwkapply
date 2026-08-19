/**
 * Best-effort browser-reported IANA timezone name, sent to the backend on
 * register/login/refresh so `User.timezone` stays current unless the user
 * has manually overridden it (see ProfileSettingsCard.vue's timezone
 * picker, and `timezone_is_manual` on `User`/`UserRead`). Backend
 * validation (app/utils/timezone.py) is the actual source of truth for
 * "is this a real IANA name"; this just best-effort reports whatever the
 * browser gives back, and returns undefined rather than throwing if
 * `Intl` is unavailable/misbehaves for any reason — an unreported
 * timezone should never block login/register.
 */
export function getBrowserTimezone(): string | undefined {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone
  } catch {
    return undefined
  }
}

export interface TimezoneOption {
  label: string
  value: string
}

// Computed once and cached (~400 IANA zones — cheap to build, no reason to
// rebuild per component instance) for ProfileSettingsCard.vue's timezone
// Select, backed by a filter so the raw list length is fine.
let cachedTimezoneOptions: TimezoneOption[] | null = null

// Not in this project's `lib` target (locked to ES2020 to match Vite's
// build target - see tsconfig.app.json) even though every browser this
// app supports implements it - a local type, not a cast to `any`, so the
// call below still gets checked against the right signature.
type IntlWithSupportedValuesOf = typeof Intl & {
  supportedValuesOf?: (key: 'timeZone') => string[]
}

// Also missing from the ES2020 `lib` target - `timeZoneName: 'shortOffset'`
// (e.g. "GMT+7") is a later addition to Intl.DateTimeFormatOptions than
// this project's lib covers. Same reasoning/pattern as
// IntlWithSupportedValuesOf above.
type ShortOffsetFormatOptions = Intl.DateTimeFormatOptions & { timeZoneName?: 'shortOffset' }

/** "UTC+7"/"UTC-5"/"UTC+5:30" for the given IANA zone, or `null` if the
 * zone name is bad or the runtime can't format it (older Safari doesn't
 * support `timeZoneName: 'shortOffset'`, though it does support the zone
 * names themselves). Reflects the offset *right now*, not a fixed
 * standard-time value - the only sane choice for zones that observe DST,
 * and matches how e.g. Google Calendar's own timezone picker labels them. */
function formatUtcOffset(zone: string): string | null {
  try {
    const parts = new Intl.DateTimeFormat('en-US', {
      timeZone: zone,
      timeZoneName: 'shortOffset',
    } as ShortOffsetFormatOptions).formatToParts(new Date())
    const offset = parts.find((part) => part.type === 'timeZoneName')?.value
    // "GMT" (not "GMT+0") for zero-offset zones - normalize to "UTC" either way.
    return offset ? offset.replace('GMT', 'UTC').replace(/^UTC$/, 'UTC+0') : null
  } catch {
    return null
  }
}

export function timezoneOptions(): TimezoneOption[] {
  if (cachedTimezoneOptions) return cachedTimezoneOptions

  const supportedValuesOf = (Intl as IntlWithSupportedValuesOf).supportedValuesOf
  // Unavailable in some environments (older Safari) - fall back to
  // whatever the browser itself detected, so the picker always has at
  // least the user's own zone to offer.
  const fallback = getBrowserTimezone()
  const zones = supportedValuesOf?.('timeZone') ?? (fallback ? [fallback] : [])

  cachedTimezoneOptions = zones.map((zone) => {
    const offset = formatUtcOffset(zone)
    const name = zone.replace(/_/g, ' ')
    return { label: offset ? `${name} (${offset})` : name, value: zone }
  })
  return cachedTimezoneOptions
}
