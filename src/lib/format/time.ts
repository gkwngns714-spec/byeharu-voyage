// ONE AUTHORITY for the two clocks (DESIGN.md §D.1) and everything printed from them.
//
// THE TWO CLOCKS, and why the UI must state both:
//
//   VOYAGE CLOCK   compressed TIME_COMPRESSION = 960×.  1 voyage-day = 90 REAL SECONDS (0100).
//                  (0045 raised it ×20 for faster testing; it was 480 = 3 real minutes.)
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
import { localeTag, t, type TKey } from '../i18n'

/** DESIGN.md §D.1 / §L.1 — a server constant (world_config.time_compression, 0045), mirrored
 *  here for DISPLAY ONLY. tests/rpc.surface.spec.ts asserts the served knob EQUALS this mirror,
 *  so the two cannot drift apart quietly. */
export const TIME_COMPRESSION = 960

/** 24 h of voyage time in real milliseconds: 86_400_000 / 960 = 90_000 = 90 real seconds (0100). */
export const REAL_MS_PER_VOYAGE_DAY = (24 * 60 * 60 * 1000) / TIME_COMPRESSION

/**
 * A SERVED INSTANT, IN MS — or null. Every timestamp the server sends is an ISO string
 * (`voyage.eta`, `busy_until`, `next_lap_at`, `clock.next_change_at` …), and the client used to
 * spell "Date.parse it, and NaN means nothing" at each reader (domain/fleet twice, the chart
 * twice, the merchant line twice, the merchant words, the fair, the top bar). One spelling: an
 * absent field and a string that is not a time both read as null, never as NaN or 1970.
 */
export function instantMs(iso: string | null | undefined): number | null {
  if (!iso) return null
  const ms = Date.parse(iso)
  return Number.isFinite(ms) ? ms : null
}

/** One real day is one game month. */
export const REAL_MS_PER_GAME_MONTH = 24 * 60 * 60 * 1000

export function voyageDaysToRealMs(days: number): number {
  return days * REAL_MS_PER_VOYAGE_DAY
}

export function realMsToVoyageDays(ms: number): number {
  return ms / REAL_MS_PER_VOYAGE_DAY
}

/** Voyage-days as the fleet list prints them: 1.63 → "1.6 days".
 *
 *  IT SPELLS THE WORD, and that is the whole point. It used to print "1.6 d" while
 *  `formatDucats` printed "8,000 d." — THE SAME LETTER FOR TWO UNITS, separated only by a full
 *  stop, side by side on FLEETS and PORT. The owner asked, 2026-08-22: "common words — stores?
 *  t? kn? what are these". This function spelled "days" that day and the other two units were
 *  kept as "t" and "kn" on the argument that they were unambiguous. They were not: 2026-09-13,
 *  "9t free? 9t free out of what?" — so `formatTons` and `formatKnots` spell theirs too now
 *  (docs/WORDS.md). */
export function formatVoyageDays(days: number, dp = 1): string {
  if (!Number.isFinite(days)) return '—'
  return t('format.days', { n: formatFixed(days, dp) })
}

/** A real-world span, long form — the shape §B.3's worked table uses.
 *  282_000 → "4.7 min" · 5_940_000 → "1 h 39 min" · 17_580_000 → "4 h 53 min" · 900 → "1 s" */
export function formatRealDuration(ms: number): string {
  if (!Number.isFinite(ms)) return '—'
  const s = Math.max(0, ms) / 1000
  if (s < 60) return t('format.seconds', { n: Math.max(1, Math.round(s)) })
  const min = s / 60
  if (min < 90) return t('format.minutes', { n: formatFixed(min, 1) })
  const h = Math.floor(min / 60)
  const rem = Math.round(min - h * 60)
  return rem === 0 ? t('format.hours', { n: h }) : t('format.hoursMinutes', { h, m: rem })
}

/** A real-world span, COMPACT — the form the wireframes use inside a table cell where the column
 *  is four characters wide: "11m", "1h02m", "12s". */
export function formatRealShort(ms: number): string {
  if (!Number.isFinite(ms)) return '—'
  const totalS = Math.max(0, Math.round(ms / 1000))
  if (totalS < 60) return t('format.shortS', { n: totalS })
  const totalMin = Math.round(totalS / 60)
  if (totalMin < 60) return t('format.shortM', { n: totalMin })
  const h = Math.floor(totalMin / 60)
  const m = totalMin - h * 60
  return t('format.shortHM', { h, m: String(m).padStart(2, '0') })
}

/** A LIVE countdown's clock face: "4:12", "0:07", "1:02:07" (0029). Ticks legibly every second,
 *  which is what separates it from `formatRealShort` — that is a duration in a four-character
 *  table cell ("11m") and rounds the seconds away, so a countdown drawn with it would only move
 *  once a minute and read as stuck. Never negative: a passed instant is the caller's cue to
 *  re-ask the server, not to count up. */
export function formatCountdown(ms: number): string {
  if (!Number.isFinite(ms)) return '—'
  const totalS = Math.max(0, Math.floor(ms / 1000))
  const h = Math.floor(totalS / 3600)
  const m = Math.floor((totalS % 3600) / 60)
  const s = totalS % 60
  if (h > 0) return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`
  return `${m}:${String(s).padStart(2, '0')}`
}

/** THE IDIOM that keeps the two clocks honest: "1.6 voyage-days · 4.7 min real". */
export function formatTwoClocks(voyageDays: number): string {
  return t('format.twoClocks', {
    days: formatFixed(voyageDays, 1),
    real: formatRealDuration(voyageDaysToRealMs(voyageDays)),
  })
}

/** Relative time against a supplied `now`. Future → "in 4.7 min"; past → "2 days ago". */
export function formatRelative(atMs: number, nowMs: number): string {
  const delta = atMs - nowMs
  const abs = Math.abs(delta)
  if (abs < 45_000) return t('format.justNow')
  const body =
    abs < 60 * 60 * 1000
      ? formatRealDuration(abs)
      : abs < 24 * 60 * 60 * 1000
        ? t('format.relHours', { n: formatInt(abs / (60 * 60 * 1000)) })
        : t('format.relDays', { n: formatFixed(abs / (24 * 60 * 60 * 1000), abs < 2 * 24 * 60 * 60 * 1000 ? 1 : 0) })
  return t(delta >= 0 ? 'format.inFuture' : 'format.inPast', { body })
}

/** Wall clock, 24 h, as the Ledger stamps a row: "14:22". Local time deliberately — the player
 *  reads their own day, and nothing is decided from this string.
 *
 *  `withSeconds` is the LIVE-clock form (0029, "the actual time"): "14:22:07", ticking each second
 *  so the reader can see it is alive. Extended here rather than written a second time — this is
 *  the one authority for how this game prints a time of day. */
export function formatClock(atMs: number, withSeconds = false): string {
  const d = new Date(atMs)
  const hm = `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
  return withSeconds ? `${hm}:${String(d.getSeconds()).padStart(2, '0')}` : hm
}

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
  /** 0-based: January is 0. */
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
  const month = t(`format.m${d.monthIndex}` as TKey)
  return t('format.gameDate', { month, year: d.year, season: t(`format.${d.season}`) })
}

const MS_PER_DAY = 24 * 60 * 60 * 1000

/** THE GAME CLOCK'S RATE — an EIGHTH of the voyage clock. The owner, 2026-10-15: *"make the clock
 *  twice slower, but keep the ship speed to where it is"* (960× → 480×), then *"make the light zone
 *  time twice slower"* (480× → 240×), and 2026-10-17 *"change the light zone dark zone area movement
 *  by 2 times slower"* (240× → 120×). The Sun stands where this clock puts it, so the clock and the
 *  light slow together: a game day is 12 real minutes. Sailing stays on the server's
 *  TIME_COMPRESSION (960×): a ship covers in one clock-hour what she covers in eight voyage-hours. */
export const GAME_CLOCK_RATE = TIME_COMPRESSION / 8

/** THE GAME CLOCK — the same for every player: real time since the Unix epoch run at
 *  GAME_CLOCK_RATE×. The owner, 2026-10-15: *"show game clock, no date, only time"* and the
 *  sunlight *"should match the speed of the game speed"*. ONE authority: the top bar prints it and
 *  the Sun (src/chart/useSunlight.ts) stands where this hour puts it. Returns ms into the game day. */
export function gameTimeOfDayMs(nowMs: number): number {
  return (((nowMs % MS_PER_DAY) * GAME_CLOCK_RATE) % MS_PER_DAY + MS_PER_DAY) % MS_PER_DAY
}

/** The game clock as the top bar prints it, UTC hours: "14:22". No date — the owner's call. */
export function formatGameClock(nowMs: number): string {
  const t = gameTimeOfDayMs(nowMs)
  const h = Math.floor(t / 3_600_000)
  const m = Math.floor((t % 3_600_000) / 60_000)
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`
}

/** The UTC instant the Sun is drawn for: today's real date (so the season is the real one) at the
 *  GAME CLOCK's hour (so the day and night turn at game speed). */
export function gameSunInstantMs(nowMs: number): number {
  return nowMs - (((nowMs % MS_PER_DAY) + MS_PER_DAY) % MS_PER_DAY) + gameTimeOfDayMs(nowMs)
}

/** A CALENDAR DATE in the viewer's language — the one door to Intl for dates, so no screen spells
 *  a locale of its own. `opts` are Intl.DateTimeFormat's ("Oct 20, 2026" · "2026년 10월 20일"). */
export function formatDate(atMs: number, opts: Intl.DateTimeFormatOptions): string {
  if (!Number.isFinite(atMs)) return '—'
  return new Intl.DateTimeFormat(localeTag(), opts).format(atMs)
}
