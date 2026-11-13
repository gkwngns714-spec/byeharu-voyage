import { getLocale, translateMaybe } from '../lib/i18n'

// A CAPTAIN'S JOB AND ROLE, IN THE VIEWER'S LANGUAGE (owner, 2026-11-12: English left on the Korean glass).
//
// The server serves a captain's job as an English word (`job_word`: "Navigator", "Gem trader") and her role as another
// (`focus_word`: "Trading"). Both are small closed sets (25 jobs, `data/officers.json`'s specialties; three roles), so they are
// worded here the way a hull's size and role are (features/compendium/ShipsFace.tsx): a `books` entry keyed by the served word
// (`job_gem_trader`, `focus_trading`), and the served word itself where there is no entry. One authority: every face that
// prints a job (the Inn, You, the Codex, a ship's cabins) reads it through here. A trait's SENTENCE and a captain's blurb are
// the server's prose and stay as served (tests/i18n.ko.spec.ts, "chrome, not prose").

const key = (served: string) => served.trim().toLowerCase().replace(/[^a-z]+/g, '_')

/** The job's word: "Gem trader" → 보석 상인. `null` in, `null` out. */
export function jobWord(served: string | null | undefined): string | null {
  if (served == null || served === '') return null
  return translateMaybe(getLocale(), 'books', `job_${key(served)}`) ?? served
}

/** The role's word: "Trading" → 교역. */
export function focusWord(served: string | null | undefined): string | null {
  if (served == null || served === '') return null
  return translateMaybe(getLocale(), 'books', `focus_${key(served)}`) ?? served
}
