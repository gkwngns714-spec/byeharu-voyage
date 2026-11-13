// READING A STRING. `t('auth.title')` — the key is `<section>.<entry>`, typed from the registry in
// ./dict, so a typo fails `tsc`. `{name}` placeholders take `vars`; a plural entry picks `one` when
// `vars.count` (or, without one, `vars.n`) is 1, else `other` — `count` lets the printed figure
// be formatted ("−1", "1,000") while the pick still reads the number.
//
// Pure code (lib/format, domain/*) calls `t` and reads the locale at call time. A component calls
// `useT()` (./react) instead, so a switch re-renders it and a `useMemo` keyed on `t` recomputes.

import { DICT } from './dict'
import type { Msg } from './define'
import { getLocale, type Locale } from './locale'

type Sections = typeof DICT

export type TKey = {
  [S in keyof Sections]: `${S & string}.${keyof Sections[S]['en'] & string}`
}[keyof Sections]

export type TVars = Readonly<Record<string, string | number>>

export type T = (key: TKey, vars?: TVars) => string

function fill(text: string, vars: TVars | undefined): string {
  if (!vars) return text
  return text.replace(/\{(\w+)\}/g, (all, name: string) => (name in vars ? String(vars[name]) : all))
}

// A KOREAN WORD KEEPS ITS BRACKET (2026-11-13, owner row 318; the History page at 320 px: "Casa de Aveiro 설립(리스본)."
// stood as "설립" / "(리스본)."). Korean lines turn between words, not inside one (`word-break: keep-all`, src/index.css), but
// that rule only joins letter to letter: a browser may still turn a line before "(" where it follows a Hangul letter with no
// space, as Korean writes it ("설립(리스본)", "{port}(으)로"). A WORD JOINER (U+2060: no width, no glyph) between the letter
// and the bracket forbids that one turn. Here, once, for every Korean sentence the dictionary makes, after its values are
// filled in: no screen and no dictionary entry carries the character itself. English is never touched.
const BEFORE_BRACKET = /([\uAC00-\uD7A3A-Za-z0-9])(?=\()/g
const WORD_JOINER = '\u2060'
function whole(locale: Locale, text: string): string {
  return locale === 'ko' ? text.replace(BEFORE_BRACKET, `$1${WORD_JOINER}`) : text
}

function pick(msg: Msg, vars: TVars | undefined): string {
  if (typeof msg === 'string') return msg
  return String(vars?.count ?? vars?.n) === '1' ? msg.one : msg.other
}

function entry(locale: Locale, section: string, name: string): Msg | undefined {
  const dict = (DICT as unknown as Record<string, Record<Locale, Record<string, Msg>>>)[section]
  return dict?.[locale]?.[name] ?? dict?.en?.[name]
}

export function translate(locale: Locale, key: TKey, vars?: TVars): string {
  const dot = key.indexOf('.')
  const msg = entry(locale, key.slice(0, dot), key.slice(dot + 1))
  return msg === undefined ? key : whole(locale, fill(pick(msg, vars), vars))
}

/** A key only known at run time (a served code). Null when the section has no such entry, so the
 *  caller prints its own truthful fallback (the server's English sentence, the served name). */
export function translateMaybe(locale: Locale, section: keyof Sections, name: string, vars?: TVars): string | null {
  const dict = (DICT as unknown as Record<string, Record<Locale, Record<string, Msg>>>)[section]
  const msg = dict?.[locale]?.[name]
  return msg === undefined ? null : whole(locale, fill(pick(msg, vars), vars))
}

const BY_LOCALE: Record<Locale, T> = {
  en: (key, vars) => translate('en', key, vars),
  ko: (key, vars) => translate('ko', key, vars),
}

/** The `t` for one locale. Stable per locale, so it is a sound `useMemo` dependency. */
export function tFor(locale: Locale): T {
  return BY_LOCALE[locale]
}

/** The `t` for the locale in force right now — for pure code that is not a component. */
export const t: T = (key, vars) => translate(getLocale(), key, vars)

/** A WORD TABLE whose words follow the locale: same shape as a plain `Record<K, string>`, but each
 *  value is read through `t` when it is accessed, so the many readers of one shared table (a
 *  status word, a face's label) need no change of their own. */
export function wordTable<K extends string>(keys: Readonly<Record<K, TKey>>): Readonly<Record<K, string>> {
  const table = {} as Record<K, string>
  for (const k of Object.keys(keys) as K[]) Object.defineProperty(table, k, { get: () => t(keys[k]), enumerable: true })
  return table
}
