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

// A CAPTAIN'S ROLE, WITH THE RANGE A COMBAT CAPTAIN FIGHTS AT (owner row 66: *"captains will also be designated a role - role
// based on combat, exploration, trading … combat close, long range"*).
//
// The server has served the three roles since 0156 (`focus`: trading / exploration / combat) and the two combat jobs (the Gunner
// adds accuracy and reach, the Boarder adds attack: data/captains.json `traits`), but no face ever said which RANGE a combat
// captain fights at: both read "Combat". The range is a fact of her JOB, so it is told from the served job code, the way the
// job's word is (above). tests/captains.catalogue.spec.ts holds this table to data/captains.json: every combat job has a range
// here, a job with the `reach` effect is long range and one with `attack` alone is close range. A combat job the table does not
// know yet reads plain "Combat".

/** The range a combat job fights at, by the served job code (`public.traits.code`). */
export const RANGE_OF_JOB: Readonly<Record<string, 'long' | 'close'>> = { GUNNER: 'long', BOARDER: 'close' }

/** What a face needs of a captain to tell her role: the served card's own keys (`world.captain_card`). */
export interface RoleOf {
  focus?: string | null
  job?: string | null
}

/** Her role as a key to group and filter by: `trading`, `exploration`, `combat:long`, `combat:close` (or the bare served role). */
export function roleOf(c: RoleOf): string | null {
  if (c.focus == null || c.focus === '') return null
  const range = c.job ? RANGE_OF_JOB[c.job] : undefined
  return range ? `${c.focus}:${range}` : c.focus
}

/** The roster's order of roles: the owner's three, combat split by range. A role outside the list stands after it. */
export const ROLE_ORDER = ['trading', 'exploration', 'combat:long', 'combat:close'] as const

export function roleRank(role: string): number {
  const i = (ROLE_ORDER as readonly string[]).indexOf(role)
  return i < 0 ? ROLE_ORDER.length : i
}

/** A role's word from its key alone (the roster's headings, which stand for roles nobody fills yet). */
export function roleKeyWord(role: string): string {
  const [focus, range] = role.split(':')
  const word = focusWord(focus) ?? focus
  const r = range ? translateMaybe(getLocale(), 'books', `range_${range}`) : null
  return r ? `${word} · ${r}` : word
}

/** Her role in full: "Trading", "Combat · Long range" → 전투 · 원거리. `null` for a card that serves no role. */
export function roleWord(c: RoleOf): string | null {
  const role = roleOf(c)
  return role === null ? null : roleKeyWord(role)
}
