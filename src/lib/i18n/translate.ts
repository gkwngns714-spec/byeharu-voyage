// READING A STRING. `t('auth.title')` — the key is `<section>.<entry>`, typed from the registry in
// ./dict, so a typo fails `tsc`. `{name}` placeholders take `vars`; a plural entry picks `one` when
// `vars.n === 1`, else `other`.
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

function pick(msg: Msg, vars: TVars | undefined): string {
  if (typeof msg === 'string') return msg
  return vars?.n === 1 ? msg.one : msg.other
}

function entry(locale: Locale, section: string, name: string): Msg | undefined {
  const dict = (DICT as unknown as Record<string, Record<Locale, Record<string, Msg>>>)[section]
  return dict?.[locale]?.[name] ?? dict?.en?.[name]
}

export function translate(locale: Locale, key: TKey, vars?: TVars): string {
  const dot = key.indexOf('.')
  const msg = entry(locale, key.slice(0, dot), key.slice(dot + 1))
  return msg === undefined ? key : fill(pick(msg, vars), vars)
}

/** A key only known at run time (a served code). Null when the section has no such entry, so the
 *  caller prints its own truthful fallback (the server's English sentence, the served name). */
export function translateMaybe(locale: Locale, section: keyof Sections, name: string, vars?: TVars): string | null {
  const dict = (DICT as unknown as Record<string, Record<Locale, Record<string, Msg>>>)[section]
  const msg = dict?.[locale]?.[name]
  return msg === undefined ? null : fill(pick(msg, vars), vars)
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
