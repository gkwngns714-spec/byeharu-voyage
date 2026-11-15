import { translateMaybe, type Locale } from '../../lib/i18n'
import { formatFixed, formatInt } from '../../lib/format'

/** A REFUSAL IN THE VIEWER'S LANGUAGE. English is the server's own sentence, always, so this answers null and the
 *  caller prints that sentence. Korean is the code's entry in codesDict, with the served figures after it; a code with
 *  no entry answers null too, and the caller falls back to the server's English sentence rather than to nothing.
 *
 *  It lived inside Note.tsx until 2026-11-12. A refusal is also printed as a caption under a greyed button (the captain's
 *  skill rows, 0355), which is not a Note; the rule is one, so it stands here and both read it. */
export function refusalWords(
  locale: Locale,
  code: string,
  figures: { have: number; need: number; unit: string } | null | undefined,
  served?: string | null,
): string | null {
  const words = codeWords(locale, code, figures)
  if (words === null) return null
  const name = servedName(served, figures)
  return name === null ? words : `${name}: ${words}`
}

/** THE FLEET THE SERVER NAMED. An armada refuses under the name of the fleet that failed (0433:
 *  `Frota 1-1: Wait 10 / 30 min`, `Almiranta: Crew 6 / 8`). The payload carries no name field, so it is read here, once,
 *  off the English sentence: the text before its last `: `, kept only when the rest is the have / need line itself —
 *  an older sentence with a colon in its prose (`X fought 3 minutes ago: one battle in 30`) is not a name. */
export function servedName(served: string | null | undefined, figures: { have: number; need: number } | null | undefined): string | null {
  if (!served || !figures || typeof figures.have !== 'number' || typeof figures.need !== 'number') return null
  const cut = served.lastIndexOf(': ')
  if (cut <= 0) return null
  const name = served.slice(0, cut).trim()
  return name !== '' && /\d[\d.,]* \/ \d/.test(served.slice(cut + 2)) ? name : null
}

function codeWords(locale: Locale, code: string, figures: { have: number; need: number; unit: string } | null | undefined): string | null {
  if (locale === 'en') return null
  const sentence = translateMaybe(locale, 'codes', code)
  if (sentence === null) return null
  // figures of another shape (a closed sea's, 0396) are not a have / need pair: the sentence stands alone
  if (!figures || typeof figures.have !== 'number' || typeof figures.need !== 'number') return sentence
  const unit = translateMaybe(locale, 'codes', `unit_${figures.unit}`) ?? figures.unit
  const fig = translateMaybe(locale, 'codes', 'figures', { have: figure(figures.have), need: figure(figures.need), unit })
  return `${sentence} (${fig})`
}

const figure = (n: number) => (Number.isInteger(n) ? formatInt(n) : formatFixed(n, 1))
