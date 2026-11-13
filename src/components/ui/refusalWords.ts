import { translateMaybe, type Locale } from '../../lib/i18n'
import { formatFixed, formatInt } from '../../lib/format'

/** A REFUSAL IN THE VIEWER'S LANGUAGE. English is the server's own sentence, always, so this answers null and the
 *  caller prints that sentence. Korean is the code's entry in codesDict, with the served figures after it; a code with
 *  no entry answers null too, and the caller falls back to the server's English sentence rather than to nothing.
 *
 *  It lived inside Note.tsx until 2026-11-12. A refusal is also printed as a caption under a greyed button (the captain's
 *  skill rows, 0355), which is not a Note; the rule is one, so it stands here and both read it. */
export function refusalWords(locale: Locale, code: string, figures: { have: number; need: number; unit: string } | null | undefined): string | null {
  if (locale === 'en') return null
  const sentence = translateMaybe(locale, 'codes', code)
  if (sentence === null) return null
  if (!figures) return sentence
  const unit = translateMaybe(locale, 'codes', `unit_${figures.unit}`) ?? figures.unit
  const fig = translateMaybe(locale, 'codes', 'figures', { have: figure(figures.have), need: figure(figures.need), unit })
  return `${sentence} (${fig})`
}

const figure = (n: number) => (Number.isInteger(n) ? formatInt(n) : formatFixed(n, 1))
