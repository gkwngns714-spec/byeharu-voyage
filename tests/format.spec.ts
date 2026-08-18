// PURE UNIT SPEC — src/lib/format. No browser: this file never asks for the `page` fixture, so
// Playwright runs it as a plain Node process and no browser binary is needed.
//
// What it pins: the house rules for printing a number, because every screen depends on them and a
// silent change to one of them changes every column in the game at once.

import { test, expect } from '@playwright/test'
import {
  MINUS,
  REAL_MS_PER_VOYAGE_DAY,
  TIME_COMPRESSION,
  formatClock,
  formatDucats,
  formatDucatsDelta,
  formatFixed,
  formatGameDate,
  formatInt,
  formatKnots,
  formatNm,
  formatOfTotal,
  formatPct,
  formatPctDelta,
  formatPctPoints,
  formatRealDuration,
  formatRealShort,
  formatRelative,
  formatTuns,
  formatTwoClocks,
  formatUnitPrice,
  formatVoyageDays,
  gameDate,
  realMsToVoyageDays,
  seasonOfMonth,
  voyageDaysToRealMs,
} from '../src/lib/format'

test('ducats group on thousands and carry the period abbreviation', () => {
  expect(formatDucats(8180)).toBe('8,180 d.')
  expect(formatDucats(0)).toBe('0 d.')
  expect(formatDucats(1234567)).toBe('1,234,567 d.')
  expect(formatInt(999)).toBe('999')
  expect(formatInt(1000)).toBe('1,000')
})

test('a money delta is always signed, and a loss uses U+2212 not a hyphen', () => {
  expect(formatDucatsDelta(600)).toBe('+600 d.')
  expect(formatDucatsDelta(-420)).toBe(`${MINUS}420 d.`)
  expect(formatDucatsDelta(0)).toBe('0 d.')
  // The distinction is the whole point: a hyphen-minus would sit at text height in a mono column.
  expect(MINUS).not.toBe('-')
  expect(formatDucatsDelta(-1104)).toBe('−' + '1,104 d.')
})

test('non-finite input degrades to an em dash rather than NaN', () => {
  expect(formatInt(Number.NaN)).toBe('—')
  expect(formatFixed(Number.POSITIVE_INFINITY, 2)).toBe('—')
  expect(formatPct(Number.NaN)).toBe('—')
  expect(formatVoyageDays(Number.NaN)).toBe('—')
})

test('units print as the design document writes them', () => {
  expect(formatTuns(60)).toBe('60 t')
  expect(formatTuns(4.1, 1)).toBe('4.1 t')
  expect(formatNm(188.4)).toBe('188 nm')
  expect(formatNm(11736)).toBe('11,736 nm')
  expect(formatKnots(3.5695)).toBe('3.6 kn')
  expect(formatUnitPrice(7)).toBe('7 d./t')
  expect(formatOfTotal(98, 120)).toBe('98 / 120')
})

test('percentages: fractions and already-in-points both have a formatter, and they differ', () => {
  expect(formatPct(0.62)).toBe('62%')
  expect(formatPct(0.9673, 1)).toBe('96.7%')
  expect(formatPctPoints(113.4)).toBe('113%')
  expect(formatPctDelta(0.38)).toBe('+38%')
  expect(formatPctDelta(-0.136)).toBe(`${MINUS}14%`)
  // Rounding is Math.round, which is half-UP on the number line — so -13.5 becomes -13, not -14.
  // Pinned because a ledger that rounds two ways is a ledger that does not add up.
  expect(formatPctDelta(-0.135)).toBe(`${MINUS}13%`)
})

test('the compression constant is 480 and one voyage-day is three real minutes (D.1)', () => {
  expect(TIME_COMPRESSION).toBe(480)
  expect(REAL_MS_PER_VOYAGE_DAY).toBe(180_000)
  expect(voyageDaysToRealMs(1)).toBe(3 * 60 * 1000)
  expect(realMsToVoyageDays(180_000)).toBe(1)
})

test('B.3 worked distances reproduce their published real times', () => {
  // Lisboa -> Cadiz, 188 nm at 5 kn = 1.567 voyage-days = 4.7 min.
  const days = 188 / 5 / 24
  expect(formatRealDuration(voyageDaysToRealMs(days))).toBe('4.7 min')
  // Cadiz -> Havana, 3,944 nm at 5 kn = 32.9 days = 1 h 39 min.
  expect(formatRealDuration(voyageDaysToRealMs(3944 / 5 / 24))).toBe('1 h 39 min')
  // Lisboa -> Malaca, 11,736 nm at 5 kn = 97.8 days = 4 h 53 min.
  expect(formatRealDuration(voyageDaysToRealMs(11736 / 5 / 24))).toBe('4 h 53 min')
})

test('durations have a long form and a table-cell form', () => {
  expect(formatRealDuration(282_000)).toBe('4.7 min')
  expect(formatRealDuration(30_000)).toBe('30 s')
  expect(formatRealDuration(2 * 60 * 60 * 1000)).toBe('2 h')
  expect(formatRealShort(660_000)).toBe('11m')
  expect(formatRealShort(3_720_000)).toBe('1h02m')
  expect(formatRealShort(12_000)).toBe('12s')
})

test('the two clocks are printed together, because one of them is a lie on its own (D.3)', () => {
  expect(formatTwoClocks(1.567)).toBe('1.6 voyage-days · 4.7 min real')
  expect(formatVoyageDays(9.44)).toBe('9.4 d')
})

test('relative time reads forwards and backwards from a supplied instant', () => {
  const now = Date.UTC(2026, 5, 1, 12, 0, 0)
  expect(formatRelative(now + 282_000, now)).toBe('in 4.7 min')
  expect(formatRelative(now - 2 * 24 * 60 * 60 * 1000, now)).toBe('2 days ago')
  expect(formatRelative(now + 3 * 60 * 60 * 1000, now)).toBe('in 3 h')
  expect(formatRelative(now + 1_000, now)).toBe('just now')
})

test('the wall clock stamps a ledger row as HH:MM', () => {
  const at = new Date(2026, 5, 1, 14, 22, 0).getTime()
  expect(formatClock(at)).toBe('14:22')
})

test('the calendar clock runs one game month per real day (D.1) and seasons follow B.4', () => {
  const epoch = Date.UTC(2026, 5, 1, 0, 0, 0)
  const sixMonthsLater = epoch + 6 * 24 * 60 * 60 * 1000
  const d = gameDate(sixMonthsLater, epoch, 1554)
  expect(d.year).toBe(1554)
  expect(d.monthIndex).toBe(6)
  expect(formatGameDate(d)).toBe('July 1554 · Summer')
  // A game year is twelve real days.
  expect(gameDate(epoch + 12 * 24 * 60 * 60 * 1000, epoch, 1554).year).toBe(1555)
  expect(seasonOfMonth(2)).toBe('Spring')
  expect(seasonOfMonth(8)).toBe('Autumn')
  expect(seasonOfMonth(11)).toBe('Winter')
})
