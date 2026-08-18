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
//   · Ducats are suffixed "d." (the period abbreviation the design document uses throughout).
//   · Cargo is "t" (tuns — the period unit, ~954 L; NOT metric tonnes).
//   · Distance is "nm" (nautical miles). Speed is "kn".
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

/** Money as the game writes it: 8180 → "8,180 d." */
export function formatDucats(n: number): string {
  return `${formatInt(n)} d.`
}

/** A ledger movement, always signed: 600 → "+600 d.", -420 → "−420 d.", 0 → "0 d." */
export function formatDucatsDelta(n: number): string {
  if (!Number.isFinite(n)) return '—'
  const rounded = Math.round(n)
  if (rounded === 0) return '0 d.'
  return `${rounded > 0 ? '+' : MINUS}${group(Math.abs(rounded).toString())} d.`
}

/** A unit price: "7 d./t" — the figure a trader actually compares. */
export function formatUnitPrice(n: number): string {
  return `${formatInt(n)} d./t`
}

/** Cargo and stores, in tuns. 60 → "60 t"; 4.2 → "4.2 t" with dp=1. */
export function formatTuns(n: number, dp = 0): string {
  return `${dp > 0 ? formatFixed(n, dp) : formatInt(n)} t`
}

/** Distance: 188.4 → "188 nm". */
export function formatNm(n: number, dp = 0): string {
  return `${dp > 0 ? formatFixed(n, dp) : formatInt(n)} nm`
}

/** Speed: 3.5695 → "3.6 kn". */
export function formatKnots(n: number): string {
  return `${formatFixed(n, 1)} kn`
}

/** A FRACTION (0.62) as a percentage: "62%". Use for shares, fills, hull condition. */
export function formatPct(fraction: number, dp = 0): string {
  if (!Number.isFinite(fraction)) return '—'
  return `${dp > 0 ? formatFixed(fraction * 100, dp) : formatInt(fraction * 100)}%`
}

/** A percentage ALREADY in points (113.4) as "113%". This is what %NBR carries — see
 *  src/features/market/prices.ts, where the whole column is a percent-of-neighbours ratio. */
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

/** "98 / 120" — a used/total pair, for hold and crew. */
export function formatOfTotal(used: number, total: number): string {
  return `${formatInt(used)} / ${formatInt(total)}`
}
