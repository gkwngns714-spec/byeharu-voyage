// ONE AUTHORITY for the two clocks (DESIGN.md §D.1) and everything printed from them.
//
// THE TWO CLOCKS, and why the UI must state both:
//
//   VOYAGE CLOCK   compressed TIME_COMPRESSION = 480×.  1 voyage-day = 3 REAL MINUTES.
//                  Governs sailing, provisions, wages, hazard checkpoints.
//   CALENDAR CLOCK 1 REAL DAY = 1 game month (a game year is 12 real days).
//                  Governs season, wind regime, ice closure, seasonal goods.
//
// §D.3: "we separate them and say so out loud in the UI". A player told a voyage takes "1.6 days"
// has been lied to unless the same line also says 4.7 minutes — those are two different clocks and
// only one of them is the one they will wait through. So every duration this module prints in
// voyage-days has a real-time twin, and formatTwoClocks() is the idiom that prints the pair.
//
// Pure: no Date.now() anywhere. A caller passes the instant in (the shell owns THE ONE CLOCK —
// see src/app/shellState.ts), so a spec can pin time and a countdown never disagrees with itself.

import { formatFixed, formatInt } from './numbers'

/** DESIGN.md §D.1 / §L.1 — a server constant, mirrored here for DISPLAY ONLY. */
export const TIME_COMPRESSION = 480

/** 24 h of voyage time in real milliseconds: 86_400_000 / 480 = 180_000 = 3 real minutes. */
export const REAL_MS_PER_VOYAGE_DAY = (24 * 60 * 60 * 1000) / TIME_COMPRESSION

/** One real day is one game month. */
export const REAL_MS_PER_GAME_MONTH = 24 * 60 * 60 * 1000

export function voyageDaysToRealMs(days: number): number {
  return days * REAL_MS_PER_VOYAGE_DAY
}

export function realMsToVoyageDays(ms: number): number {
  return ms / REAL_MS_PER_VOYAGE_DAY
}

/** Voyage-days as the fleet roster prints them: 1.63 → "1.6 days".
 *
 *  IT SPELLS THE WORD, and that is the whole point. It used to print "1.6 d" while
 *  `formatDucats` printed "8,000 d." — THE SAME LETTER FOR TWO UNITS, separated only by a full
 *  stop, and the two appear side by side on FLEETS and PORT ("15.0 d of stores · 4.9 kn · 56 t
 *  free" under a purse reading "8,000 d."). The owner asked, 2026-08-22: "common words — stores?
 *  t? kn? what are these". A reader who cannot tell money from time is not reading a ledger.
 *
 *  The other two abbreviations survive because they are unambiguous in this game: `t` is a TUN of
 *  hold and `kn` is KNOTS, and neither collides with anything. They are glossed behind the info
 *  dot rather than spelled out in every cell. */
export function formatVoyageDays(days: number, dp = 1): string {
  if (!Number.isFinite(days)) return '—'
  return `${formatFixed(days, dp)} days`
}

/** A real-world span, long form — the shape §B.3's worked table uses.
 *  282_000 → "4.7 min" · 5_940_000 → "1 h 39 min" · 17_580_000 → "4 h 53 min" · 900 → "1 s" */
export function formatRealDuration(ms: number): string {
  if (!Number.isFinite(ms)) return '—'
  const s = Math.max(0, ms) / 1000
  if (s < 60) return `${Math.max(1, Math.round(s))} s`
  const min = s / 60
  if (min < 90) return `${formatFixed(min, 1)} min`
  const h = Math.floor(min / 60)
  const rem = Math.round(min - h * 60)
  return rem === 0 ? `${h} h` : `${h} h ${rem} min`
}

/** A real-world span, COMPACT — the form the wireframes use inside a table cell where the column
 *  is four characters wide: "11m", "1h02m", "12s". */
export function formatRealShort(ms: number): string {
  if (!Number.isFinite(ms)) return '—'
  const totalS = Math.max(0, Math.round(ms / 1000))
  if (totalS < 60) return `${totalS}s`
  const totalMin = Math.round(totalS / 60)
  if (totalMin < 60) return `${totalMin}m`
  const h = Math.floor(totalMin / 60)
  const m = totalMin - h * 60
  return `${h}h${String(m).padStart(2, '0')}m`
}

/** THE IDIOM that keeps the two clocks honest: "1.6 voyage-days · 4.7 min real". */
export function formatTwoClocks(voyageDays: number): string {
  return `${formatFixed(voyageDays, 1)} voyage-days · ${formatRealDuration(voyageDaysToRealMs(voyageDays))} real`
}

/** Relative time against a supplied `now`. Future → "in 4.7 min"; past → "2 days ago". */
export function formatRelative(atMs: number, nowMs: number): string {
  const delta = atMs - nowMs
  const abs = Math.abs(delta)
  if (abs < 45_000) return 'just now'
  const body =
    abs < 60 * 60 * 1000
      ? formatRealDuration(abs)
      : abs < 24 * 60 * 60 * 1000
        ? `${formatInt(abs / (60 * 60 * 1000))} h`
        : `${formatFixed(abs / (24 * 60 * 60 * 1000), abs < 2 * 24 * 60 * 60 * 1000 ? 1 : 0)} days`
  return delta >= 0 ? `in ${body}` : `${body} ago`
}

/** Wall clock, 24 h, as the Ledger stamps a row: "14:22". Local time deliberately — the player
 *  reads their own day, and nothing is decided from this string. */
export function formatClock(atMs: number): string {
  const d = new Date(atMs)
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
}

const MONTHS = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
] as const

export type Season = 'Spring' | 'Summer' | 'Autumn' | 'Winter'

/** §B.4 — seasons are game months, three apiece, Mar–May Spring. */
export function seasonOfMonth(monthIndex0: number): Season {
  const m = ((monthIndex0 % 12) + 12) % 12
  if (m >= 2 && m <= 4) return 'Spring'
  if (m >= 5 && m <= 7) return 'Summer'
  if (m >= 8 && m <= 10) return 'Autumn'
  return 'Winter'
}

export interface GameDate {
  year: number
  /** 0-based, so it indexes MONTHS directly. */
  monthIndex: number
  season: Season
  /** How far through the game month we are, 0–1. One real day spans the whole month. */
  monthFraction: number
}

/** The calendar clock: elapsed real days since `epochMs` are game months since `epochYear`/Jan. */
export function gameDate(nowMs: number, epochMs: number, epochYear: number): GameDate {
  const months = (nowMs - epochMs) / REAL_MS_PER_GAME_MONTH
  const whole = Math.floor(months)
  const year = epochYear + Math.floor(whole / 12)
  const monthIndex = ((whole % 12) + 12) % 12
  return { year, monthIndex, season: seasonOfMonth(monthIndex), monthFraction: months - whole }
}

/** "March 1554 · Spring" */
export function formatGameDate(d: GameDate): string {
  return `${MONTHS[d.monthIndex]} ${d.year} · ${d.season}`
}
