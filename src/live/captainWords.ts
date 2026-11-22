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

// ── A TRAIT'S LINE, HER LANGUAGES AND A TRAIT THAT DOES NOTHING YET, IN THE VIEWER'S LANGUAGE (2026-11-23 third play-test) ──────────
// The Korean captain sheet was half English: "+4.5% better prices", "Speaks Spanish", and the builder's "Not in use yet." under three
// traits. A trait's line is one of the eleven effect sentences of data/captains.json (`effects[].words`, "+{pct}% speed"), so it is
// read back by that sentence's shape and worded from `books.eff_<effect>`; a line of no known shape prints as served. Her languages
// are the twenty of data/captains.json `languages` (`books.lang_<name>`). English keeps the server's own lines.
const EFFECT_SHAPES: readonly (readonly [RegExp, string])[] = [
  [/^\+([\d.,]+)% speed$/, 'eff_speed'],
  [/^\+([\d.,]+)% cargo space$/, 'eff_hold'],
  [/^\+([\d.,]+)% better prices on (.+)$/, 'eff_category_spread'],
  [/^\+([\d.,]+)% better prices$/, 'eff_spread'],
  [/^[−-]([\d.,]+)% crew lost to pirates$/, 'eff_crew_saved'],
  [/^[−-]([\d.,]+) points of homesickness$/, 'eff_homesick_relief'],
  [/^[−-]([\d.,]+)% storm damage$/, 'eff_storm'],
  [/^\+([\d.,]+)% days of supplies$/, 'eff_supplies'],
  [/^\+([\d.,]+)% accuracy$/, 'eff_accuracy'],
  [/^\+([\d.,]+)% reach$/, 'eff_reach'],
  [/^\+([\d.,]+)% attack$/, 'eff_attack'],
]

/** One served trait line in the viewer's language ("+4.5% better prices" → 거래 가격 4.5% 유리). */
export function traitLine(served: string): string {
  const locale = getLocale()
  if (locale === 'en') return served
  for (const [shape, key] of EFFECT_SHAPES) {
    const m = shape.exec(served.trim())
    if (m) return translateMaybe(locale, 'books', key, { pct: m[1], goods: m[2] ?? '' }) ?? served
  }
  return served
}

/** A trait's lines, joined as the faces print them. */
export function traitLines(lines: readonly string[]): string {
  return lines.map(traitLine).join(' · ')
}

/** The effect a served line names (`speed`, `hold`, `spread`, … the `eff_` keys without it), or null for a line of no known shape. */
export function traitEffect(served: string): string | null {
  for (const [shape, key] of EFFECT_SHAPES) if (shape.test(served.trim())) return key.slice(4)
  return null
}

// ── X7: A TRAIT THAT DOES NOTHING IS NOT SHOWN (roadmap 2026-11-23 §4: "Hidden · Word list"; the visual overhaul's slice 6) ──────────
// The card (world.captain_card, 0156) serves `in_use` and `note` from the DARK arm's rule: only her job, and only for the four effects
// that were live before crew_bite. Since 0179 lit crew_bite, every fleet effect of every trait she uses is read (public.crew_terms;
// 0355 reads "does it work" the same way), so the card's "Not in use yet." is stale and #800's `in_use` filter hid traits that work
// (measured: Elcano's Pilot, −5.4% storm damage, stands on her sheet's Seamanship). What still does nothing is a SHIP effect while
// combat is off, and the card says so in its own words: 0168 serves "Works when combat arrives." only then. So the word list is that
// sentence; a trait whose card says it is idle, and that is not her job at work, is left off every face a player hires or keeps a
// captain on (the Inn's room, You), by this ONE test. The Codex, the catalogue of everything, keeps them all with their idle word.
const IDLE_NOTES: readonly string[] = ['Works when combat arrives.']

export function traitWorks(t: { in_use: boolean; note: string | null }): boolean {
  return t.in_use || t.note === null || !IDLE_NOTES.includes(t.note.trim())
}

/** A trait that does nothing yet says so in a player's two words (the served note, "Not in use yet." / "Works when combat arrives.",
 *  was a builder's sentence); null when it works. */
export function traitIdle(note: string | null | undefined): string | null {
  return note ? (translateMaybe(getLocale(), 'books', 'traitIdle') ?? note) : null
}

/** "Speaks Portuguese, Spanish" from her served languages, in the viewer's language; the served sentence when none are listed. */
export function speaksWords(c: { languages?: string[]; speaks?: string }): string | null {
  const langs = c.languages ?? []
  if (langs.length === 0) return c.speaks ?? null
  const locale = getLocale()
  const names = langs.map((l) => translateMaybe(locale, 'books', `lang_${key(l)}`) ?? l)
  return translateMaybe(locale, 'books', 'speaks', { langs: names.join(', ') }) ?? c.speaks ?? null
}
