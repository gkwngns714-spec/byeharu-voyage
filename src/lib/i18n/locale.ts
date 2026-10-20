// THE ONE LOCALE. Which language the game speaks to THIS viewer: 'en' or 'ko'.
//
// Default: the browser's own language (`ko…` → Korean, anything else → English), so a Korean
// player reads Korean before touching a switch and every Playwright spec (default `en-US`) keeps
// reading English. A choice made on the switch is remembered per viewer in localStorage under ONE
// key; every read and write is in try/catch, because a private window or blocked site data throws
// and the game must still open — in the browser's language.
//
// A tiny external store (subscribe/get), so React reads it through useSyncExternalStore and the
// shell re-renders in place on a switch — no reload, no remount.

export type Locale = 'en' | 'ko'

export const LOCALES: readonly Locale[] = ['en', 'ko']

const STORAGE_KEY = 'bv.locale'

function isLocale(v: unknown): v is Locale {
  return v === 'en' || v === 'ko'
}

function remembered(): Locale | null {
  try {
    const v = globalThis.localStorage?.getItem(STORAGE_KEY)
    return isLocale(v) ? v : null
  } catch {
    return null
  }
}

function fromBrowser(): Locale {
  try {
    const lang = globalThis.navigator?.language ?? ''
    return /^ko\b/i.test(lang) ? 'ko' : 'en'
  } catch {
    return 'en'
  }
}

let current: Locale = remembered() ?? fromBrowser()
const listeners = new Set<() => void>()

export function getLocale(): Locale {
  return current
}

export function setLocale(next: Locale): void {
  try {
    globalThis.localStorage?.setItem(STORAGE_KEY, next)
  } catch {
    // Not remembered; still switched for this visit.
  }
  if (next === current) return
  current = next
  if (typeof document !== 'undefined') document.documentElement.lang = next
  for (const fn of listeners) fn()
}

export function subscribeLocale(fn: () => void): () => void {
  listeners.add(fn)
  return () => listeners.delete(fn)
}

/** The BCP 47 tag the Intl formatters take. */
export function localeTag(locale: Locale = current): string {
  return locale === 'ko' ? 'ko-KR' : 'en'
}

if (typeof document !== 'undefined') document.documentElement.lang = current
