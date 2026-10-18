// ONE AUTHORITY for every number this game prints.
//
// No screen formats a number inline. A ledger whose columns disagree about whether a thousand has
// a separator, or whether a loss is "-420" or "−420 d.", is a ledger nobody can scan — and this
// game is nothing but columns of numbers. So the rules live here, once:
//
//   · Thousands separator is a comma, always (8,180 — never 8180, never 8 180).
//   · A negative money figure uses U+2212 MINUS SIGN, not the hyphen-minus: in JetBrains Mono the
//     hyphen sits at text height and reads as a dash between two figures. The minus sits on the
//     maths axis, aligned with the digits, which is what a column of deltas needs.
//   · Ducats are suffixed with the COIN mark, spelled ONCE below — the owner, 2026-09-18: "the
//     currency is ... i don't like it. d. lets change it, to a coin". Every screen and every
//     ledger line that names money composes onto `COIN`; no file writes the mark itself.
//   · Every other unit is SPELLED: "tons", "miles", "knots", "days". The owner asked twice —
//     2026-08-22 "stores? t? kn? what are these" and 2026-09-13 "9t free? 9t free out of what?"
//     — and the second time is the rule: a unit a player has to decode is not a unit.
//
// Pure: no React, no DOM, no clock, no locale lookup (the separator is fixed, not Intl-derived —
// a player's locale must not silently change what a shared leaderboard figure looks like).

/** U+2212. Exported because a screen writing a literal '-' in front of a number is the bug. */
export const MINUS = '\u2212'

/** Thin-space-free grouped integer: 8180 → "8,180". Rounds; NaN/±Infinity → "—". */
export function formatInt(n: number): string {
  if (!Number.isFinite(n)) return '—'
  const rounded = Math.round(n)
  const sign = rounded < 0 ? MINUS : ''
  return sign + group(Math.abs(rounded).toString())
}

/** Fixed-decimal grouped number: (1234.56, 1) → "1,234.6". */
export function formatFixed(n: number, dp: number): string {
  if (!Number.isFinite(n)) return '—'
  const sign = n < 0 ? MINUS : ''
  const abs = Math.abs(n).toFixed(dp)
  const [whole, frac] = abs.split('.')
  return sign + group(whole) + (frac ? '.' + frac : '')
}

function group(digits: string): string {
  return digits.replace(/\B(?=(\d{3})+(?!\d))/g, ',')
}

/** THE COIN — the one place the currency mark is spelled (a coin, never a letter). */
export const COIN = '🪙'
/** A figure and its coin never part: the space between them is a no-break space, so a button or a
 *  ledger line wraps before the number, never between the number and its mark. */
const NBSP = '\u00a0'

/** Money as the game writes it: 8180 → "8,180 🪙" */
export function formatDucats(n: number): string {
  return `${formatInt(n)}${NBSP}${COIN}`
}

/** A ledger movement, always signed: 600 → "+600 🪙", -420 → "−420 🪙", 0 → "0 🪙" */
export function formatDucatsDelta(n: number): string {
  if (!Number.isFinite(n)) return '—'
  const rounded = Math.round(n)
  if (rounded === 0) return `0${NBSP}${COIN}`
  return `${rounded > 0 ? '+' : MINUS}${group(Math.abs(rounded).toString())}${NBSP}${COIN}`
}

/** A unit price: "7 🪙 each" — the figure a trader actually compares. PER UNIT, not per ton: a
 *  trade quantity is a COUNT of units (`qty`), and a unit of a good takes `bulk` tons of space —
 *  126 of 523 goods have bulk 1.0, so "per ton" was wrong for the other 397. */
export function formatUnitPrice(n: number): string {
  return `${formatInt(n)}${NBSP}${COIN} each`
}

/** A PRICE AT ANY SCALE (the COMMAND DESK, 2026-10-18): the game's prices run from about 1 to about
 *  100,000 a unit (distance pricing is coming), and a figure must keep its meaning at both ends —
 *  "1 🪙" for 1.42 hides a 40 % move, "12,345.67 🪙" is noise. So the decimals follow the size:
 *  below 10 two places (1.42), below 100 one (42.6), from 100 none (1,240 · 98,400). */
export function priceDigits(n: number): number {
  const a = Math.abs(n)
  return a < 10 ? 2 : a < 100 ? 1 : 0
}

/** The bare figure of `formatPrice`, for an axis label or a column: 1.42 · 42.6 · 1,240. */
export function formatPriceFigure(n: number): string {
  if (!Number.isFinite(n)) return '—'
  return formatFixed(n, priceDigits(n))
}

/** A price with its coin: 1.42 → "1.42 🪙", 98400 → "98,400 🪙". */
export function formatPrice(n: number): string {
  return `${formatPriceFigure(n)}${NBSP}${COIN}`
}

/** A signed price: +0.42 🪙, −1,240 🪙 — a net per unit or per ton at any scale (formatPrice's digits). */
export function formatPriceDelta(n: number): string {
  if (!Number.isFinite(n)) return '—'
  const dp = priceDigits(n)
  const r = Math.round(n * 10 ** dp) / 10 ** dp
  if (r === 0) return `0${NBSP}${COIN}`
  return `${r > 0 ? '+' : MINUS}${formatPrice(Math.abs(r))}`
}

/** A signed movement in points already (4.1 → "+4.1%", −2 → "−2.0%", 0 → "0.0%"): the change chip. */
export function formatPctChange(points: number): string {
  if (!Number.isFinite(points)) return '—'
  const r = Math.round(points * 10) / 10
  if (r === 0) return '0.0%'
  return `${r > 0 ? '+' : MINUS}${formatFixed(Math.abs(r), 1)}%`
}

/** A trade quantity: 20 → "20 units", 1 → "1 unit". The count the server trades in; the space it
 *  takes is `formatTons(qty * bulk)`, and the two are never confused (docs/WORDS.md law 2). */
export function formatUnits(n: number): string {
  const rounded = Math.round(n)
  return `${formatInt(rounded)} ${Math.abs(rounded) === 1 ? 'unit' : 'units'}`
}

/** THE WORD FOR THE CARGO UNIT, pluralised — the one place it is spelled. 1 → "ton", else "tons". */
export function tonsWord(n: number): string {
  return Math.abs(n) === 1 ? 'ton' : 'tons'
}

/** Cargo and supplies, in tons. 60 → "60 tons"; 1 → "1 ton"; 4.2 → "4.2 tons" with dp=1. */
export function formatTons(n: number, dp = 0): string {
  const figure = dp > 0 ? formatFixed(n, dp) : formatInt(n)
  return `${figure} ${tonsWord(dp > 0 ? n : Math.round(n))}`
}

/** Distance at sea: 188.4 → "188 miles". (Nautical miles — the word a player reads is "miles".) */
export function formatMiles(n: number, dp = 0): string {
  return `${dp > 0 ? formatFixed(n, dp) : formatInt(n)} miles`
}

/** How a water point reads on a screen: "33.0°N 15.0°W". The one wording, so the panel, the
 *  fleet chip and the report agree. (Moved here from `domain/passage` 2026-10-14 so
 *  `domain/fleet`'s where-she-is line can print a point without the two sections importing each
 *  other — it is a way of printing two numbers, which is this file's whole job.) */
export function pointLabel(at: { readonly lat: number; readonly lon: number }): string {
  const ns = at.lat >= 0 ? 'N' : 'S'
  const ew = at.lon >= 0 ? 'E' : 'W'
  return `${Math.abs(at.lat).toFixed(1)}°${ns} ${Math.abs(at.lon).toFixed(1)}°${ew}`
}

/** Speed: 3.5695 → "3.6 knots". */
export function formatKnots(n: number): string {
  return `${formatFixed(n, 1)} knots`
}

/** A FRACTION (0.62) as a percentage: "62%". Use for shares, fills, hull condition. */
export function formatPct(fraction: number, dp = 0): string {
  if (!Number.isFinite(fraction)) return '—'
  return `${dp > 0 ? formatFixed(fraction * 100, dp) : formatInt(fraction * 100)}%`
}

/** A percentage ALREADY in points (113.4) as "113%". This is what %NBR carries — see
 *  the MARKET tab's %NBR column, which is a percent-of-neighbours ratio the server derives. */
export function formatPctPoints(points: number, dp = 0): string {
  if (!Number.isFinite(points)) return '—'
  return `${dp > 0 ? formatFixed(points, dp) : formatInt(points)}%`
}

/** A signed percentage-point movement: 0.38 → "+38%". */
export function formatPctDelta(fraction: number): string {
  if (!Number.isFinite(fraction)) return '—'
  const pts = Math.round(fraction * 100)
  if (pts === 0) return '0%'
  return `${pts > 0 ? '+' : MINUS}${Math.abs(pts)}%`
}

/** "98 / 120" — a used/total pair, for cargo and crew. A share never prints without its whole. */
export function formatOfTotal(used: number, total: number): string {
  return `${formatInt(used)} / ${formatInt(total)}`
}
