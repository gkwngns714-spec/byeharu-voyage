// ═══════════════════════════════════════════════════════════════════════════════════════════════
// NO CHART'S RIGHT EDGE GOES DOWN — which points of a SUM are whole (owner, 2026-11-06, and again 2026-11-07: *"i said i don't like the
// right edge of the chart goes down. every chart"*). docs/dev-log/2026-11-07-chart-right-edge-every-chart.md has the audit and the images.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// PURE SPEC: no `page`, so Playwright runs it as a plain Node process. The figures below are READ OFF PROD on 2026-11-07 (07:22 UTC, 1.5 minutes
// after the 07:21 count), because the defect was a plunge of 93 % that only real numbers show:
//   · world.stats_overview's series ends in a LIVE point at now() whose flows are the minutes since the last count: 1,821,942 sold, against
//     25,022,617 and 26,122,487 in the two quarter hours before it;
//   · the hour the live point stands in is still being counted (2 of its 4 slots: 51,145,104 against 101,091,608 the hour before), and so is the day
//     (30 of 96 slots: 719,427,742 against 2,371,026,924).
// The one rule is `wholePeriods` (src/components/ui/seriesChartModel.ts); the Stats faces reach it through `wholeRows` and the Report's and Me's bars
// through `reportBars`. tests/rpc.stats.spec.ts holds the same rule against the real server read.

import { test, expect } from '@playwright/test'
import { wholePeriods } from '../src/components/ui/seriesChartModel'
import { wholeRows } from '../src/features/stats/statsFaces'
import { formatRealDay, realDayMs } from '../src/lib/format'
import { reportBars } from '../src/live/reportBars'

const H = 3_600_000
const DAY = 86_400_000
const at = (iso: string) => Date.parse(iso)
/** What the 07:21 count says: the last count the figures reach. */
const COUNTED = '2026-11-07T07:21:00.122Z'
const sold = (rows: readonly { sold: number }[]) => rows.map((r) => r.sold)

// ── the 15-minute rows ──────────────────────────────────────────────────────────────────────────

test('a count\'s own rows are whole; the live point after the last count is no period', () => {
  const rows = [
    { atMs: at('2026-11-07T06:51:00.119Z'), sold: 27_173_751 },
    { atMs: at('2026-11-07T07:06:00.115Z'), sold: 25_022_617 },
    { atMs: at(COUNTED), sold: 26_122_487 },
    { atMs: at('2026-11-07T07:22:23.496Z'), sold: 1_821_942 }, // the live point: the minutes since the count
  ]
  // the row AT the reach is the last count itself: kept; the live point stands after it: gone, and nothing is drawn in its place
  expect(sold(wholePeriods(rows, 'quarter', at(COUNTED)))).toEqual([27_173_751, 25_022_617, 26_122_487])
  // a minute before its count a row is not yet there to be whole
  expect(sold(wholePeriods(rows, 'quarter', at(COUNTED) - 1))).toEqual([27_173_751, 25_022_617])
})

// ── hour and day: the bucket still being counted ───────────────────────────────────────────────

test('an hour stands at its last slot and is whole once the figures reach its end; the one being counted is left out, and so is the live point', () => {
  const rows = [
    { atMs: at('2026-11-07T05:51:00.150Z'), sold: 93_732_446 }, // n = 4: the 05:00 hour
    { atMs: at('2026-11-07T06:51:00.110Z'), sold: 101_091_608 }, // n = 4: the 06:00 hour
    { atMs: at(COUNTED), sold: 51_145_104 }, // n = 2: the 07:00 hour, two slots in
    { atMs: at('2026-11-07T07:22:23.496Z'), sold: 1_821_942 }, // the live point
  ]
  expect(sold(wholePeriods(rows, 'hour', at(COUNTED)))).toEqual([93_732_446, 101_091_608])
  // the 07:00 hour ends at 08:00:00.000 exactly: one millisecond before, it is open; on the edge, whole
  const full = { atMs: at('2026-11-07T07:51:00.100Z'), sold: 100_000_000 }
  expect(wholePeriods([rows[1], full], 'hour', at('2026-11-07T07:59:59.999Z')).map((r) => r.sold)).toEqual([101_091_608])
  expect(wholePeriods([rows[1], full], 'hour', at('2026-11-07T08:00:00.000Z')).map((r) => r.sold)).toEqual([101_091_608, 100_000_000])
})

test('a day stands at its last slot and is whole at its own midnight, not a millisecond before', () => {
  const rows = [
    { atMs: at('2026-11-05T23:51:00.070Z'), sold: 2_411_307_084 }, // n = 96
    { atMs: at('2026-11-06T23:51:00.110Z'), sold: 2_371_026_924 }, // n = 96
    { atMs: at(COUNTED), sold: 719_427_742 }, // n = 30: today so far
    { atMs: at('2026-11-07T07:22:23.496Z'), sold: 1_821_942 }, // the live point
  ]
  expect(sold(wholePeriods(rows, 'day', at(COUNTED)))).toEqual([2_411_307_084, 2_371_026_924])
  expect(sold(wholePeriods(rows.slice(0, 2), 'day', at('2026-11-06T23:59:59.999Z')))).toEqual([2_411_307_084])
  expect(sold(wholePeriods(rows.slice(0, 2), 'day', at('2026-11-07T00:00:00.000Z')))).toEqual([2_411_307_084, 2_371_026_924])
})

// ── the record: day, week, month stand at their first day, and the figures are complete to now ─────

test('a record\'s day is whole at its midnight; a week 7 days after its Monday; a month by its longest length (31 days)', () => {
  const d6 = Date.UTC(2026, 10, 6)
  const days = [d6 - DAY, d6, d6 + DAY].map((atMs, i) => ({ atMs, v: [95_202, 100_000, 6_728][i] })) // 11-05, 11-06, 11-07 (today)
  expect(wholePeriods(days, 'day', d6 + DAY + 14 * H).map((p) => p.v)).toEqual([95_202, 100_000])
  expect(wholePeriods(days, 'day', d6 + 2 * DAY).map((p) => p.v)).toEqual([95_202, 100_000, 6_728])

  const mon = Date.UTC(2026, 10, 2)
  const weeks = [{ atMs: mon - 7 * DAY, v: 1 }, { atMs: mon, v: 2 }]
  expect(wholePeriods(weeks, 'week', mon + 7 * DAY - 1).map((p) => p.v)).toEqual([1])
  expect(wholePeriods(weeks, 'week', mon + 7 * DAY).map((p) => p.v)).toEqual([1, 2])

  // no month arithmetic in the client (tests/duplication.spec.ts): November (30 days) is judged by 31, so it is held back until Dec 2
  const months = [{ atMs: Date.UTC(2026, 9, 1), v: 1 }, { atMs: Date.UTC(2026, 10, 1), v: 2 }]
  expect(wholePeriods(months, 'month', Date.UTC(2026, 10, 20)).map((p) => p.v)).toEqual([1])
  expect(wholePeriods(months, 'month', Date.UTC(2026, 11, 2)).map((p) => p.v)).toEqual([1, 2])
  // ...but only while it is the NEWEST: once December has a row, November is over, whatever its length
  const next = [...months, { atMs: Date.UTC(2026, 11, 1), v: 3 }]
  expect(wholePeriods(next, 'month', Date.UTC(2026, 11, 1, 0, 12)).map((p) => p.v)).toEqual([1, 2])
})

// ── what the rule never does ────────────────────────────────────────────────────────────────────

test('only the newest period can be open; the rest is kept as it stands, in any order, and nothing is invented', () => {
  const rows = [3, 1, 4, 2].map((k) => ({ atMs: Date.UTC(2026, 10, k), v: k })) // out of order on purpose
  const out = wholePeriods(rows, 'day', Date.UTC(2026, 10, 4, 12))
  expect(out.map((r) => r.v).sort()).toEqual([1, 2, 3]) // 11-04 is the newest and still running
  for (const r of out) expect(rows).toContain(r) // the very objects it was handed, none made up
  expect(wholePeriods([], 'hour', at(COUNTED))).toEqual([])
  // a reach that is not a time draws nothing, never something short
  expect(wholePeriods(rows, 'day', Number.NaN)).toEqual([])
})

// ── a Stats read: the span names the period, the read's counted_at is the reach ─────────────────

test('wholeRows: a Stats read\'s rows, by its span, up to its last count', () => {
  const row = (iso: string, n: number) => ({ at: iso, sold: n })
  const quarters = [row('2026-11-07T06:51:00.119Z', 27_173_751), row('2026-11-07T07:06:00.115Z', 25_022_617), row(COUNTED, 26_122_487), row('2026-11-07T07:22:23.496Z', 1_821_942)]
  const hours = [row('2026-11-07T05:51:00.150Z', 93_732_446), row('2026-11-07T06:51:00.110Z', 101_091_608), row(COUNTED, 51_145_104), row('2026-11-07T07:22:23.496Z', 1_821_942)]
  const days = [row('2026-11-05T23:51:00.070Z', 2_411_307_084), row('2026-11-06T23:51:00.110Z', 2_371_026_924), row(COUNTED, 719_427_742), row('2026-11-07T07:22:23.496Z', 1_821_942)]
  const stamp = (span: string | null) => ({ span, counted_at: COUNTED })

  // 1d (and a read of no span) is the count's own rows: only the live point goes
  expect(sold(wholeRows(stamp('1d'), quarters))).toEqual([27_173_751, 25_022_617, 26_122_487])
  expect(sold(wholeRows(stamp(null), quarters))).toEqual([27_173_751, 25_022_617, 26_122_487])
  // 1w and 1m are hourly buckets, 1y and all daily ones (public.stats_span_unit, 0246): the bucket being counted goes with the live point
  for (const span of ['1w', '1m']) expect(sold(wholeRows(stamp(span), hours))).toEqual([93_732_446, 101_091_608])
  for (const span of ['1y', 'all']) expect(sold(wholeRows(stamp(span), days))).toEqual([2_411_307_084, 2_371_026_924])

  // the rows handed back are the served rows themselves
  expect(wholeRows(stamp('1d'), quarters)[0]).toBe(quarters[0])
  // before the first count there is nothing whole; a span nobody serves draws nothing rather than something short; an instant that does not parse is left out
  expect(wholeRows({ span: '1d', counted_at: null }, quarters)).toEqual([])
  expect(wholeRows(stamp('2h'), quarters)).toEqual([])
  expect(sold(wholeRows(stamp('1d'), [row('not a time', 1), quarters[0]]))).toEqual([27_173_751])
})

test('wholeRows: the reach is the last count, not the clock: a count that has not run leaves its hour open', () => {
  // the 07:21 count was the last; it is now 09:30 and nothing has counted since: the 07:00 hour holds two slots and stays out
  const hours = [{ at: '2026-11-07T06:51:00.110Z', sold: 101_091_608 }, { at: COUNTED, sold: 51_145_104 }]
  expect(sold(wholeRows({ span: '1w', counted_at: COUNTED }, hours))).toEqual([101_091_608])
})

// ── the report's days: today is a figure beside the bars, not a bar that stands short ───────────

test('reportBars: the days that are over; today stands out until its own midnight', () => {
  const today = Math.floor(Date.UTC(2026, 10, 7, 12) / DAY) // 2026-11-07 as the server numbers a real UTC day
  const days = [-6, -5, -4, -3, -2, -1, 0].map((k, i) => ({ day: today + k, net: [120, -40, 0, 75, 310, -90, 25][i] }))
  const noon = realDayMs(today) + 12 * H
  expect(reportBars(days, noon).map((b) => b.id)).toEqual([-6, -5, -4, -3, -2, -1].map((k) => String(today + k)))
  expect(reportBars(days, noon).map((b) => b.value)).toEqual([120, -40, 0, 75, 310, -90])
  expect(reportBars(days, realDayMs(today + 1) - 1)).toHaveLength(6)
  expect(reportBars(days, realDayMs(today + 1))).toHaveLength(7)
  // the Report's Today span is one day and it is today: no bar, rather than one bar of nothing else
  expect(reportBars([{ day: today, net: 25 }], noon)).toEqual([])
})

test('a real UTC day number is one instant, and it prints as the server named it', () => {
  const day = Math.floor(Date.UTC(2026, 10, 5) / DAY)
  expect(realDayMs(day)).toBe(Date.UTC(2026, 10, 5))
  expect(formatRealDay(day)).toBe('11-05')
})
