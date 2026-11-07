// THE SERIES CHART'S GEOMETRY — pure, so tests/seriesChart.spec.ts proves the axis in Node and the
// component only draws.
//
// ONE SERIES, ONE AXIS (0214, the Stats tab). The world's money has four holders a thousandfold apart
// (players 0.2 M, cities 988 M on 2026-10-20); one plane with one y axis would flatten three of them
// to the floor, and two y axes are the chart mistake every dataviz guide names first. So a figure that
// moves over time is drawn as SMALL MULTIPLES: one `SeriesChart` per figure, each on its own scale,
// the current value printed beside it. The callers today: the Overview's four holders and its minted
// / removed lines, a city's purse (Cities), the merchants' day (Merchants) — three faces, one shape.
//
// WHAT IT SHARES WITH priceChartModel.ts, AND WHY IT IS NOT THAT FILE. The price chart is the record
// of ONE good at ONE city in drift slots, with the server's estimate, its band, the arrival and the
// best time drawn to the right of now — an instrument for a trade. This is a plain line over served
// instants with nothing to the right of now. Folding the estimate machinery into a generic chart, or
// this axis into the price chart, would make one component with two jobs and a flag; two small pure
// models are the honest shape (docs/NO_SPAGHETTI.md §5: a wrapper that makes two things coexist is
// a third thing).
//
// WHAT IT REFUSES, like the Sparkline: it does not interpolate across a gap (the points are what the
// job wrote; the retention keeps one a day past the fine window, so the x axis is TIME, not index);
// it does not scale to zero unless the data touches it (the shape of the move is the point; the
// figures beside it carry the size). Below two points it draws nothing.

import { t } from '../../lib/i18n'

export interface SeriesPoint {
  /** The served instant, in ms. */
  atMs: number
  value: number
}

export interface SeriesChartModel {
  width: number
  height: number
  plot: { x: number; y: number; w: number; h: number }
  /** The polyline, and the same closed to the floor for the wash under it. */
  line: string
  area: string
  /** Where the wash under the line fades out: it ends at nothing, with no wall at the newest point. */
  areaFade: WashFade | null
  /** Three y figures, served scale: low, mid, high. */
  yTicks: { y: number; value: number }[]
  /** The x axis's words: how long before the last point each tick stands. */
  xTicks: { x: number; label: string }[]
  /** Every point's pixel, for the hover layer: nearest-x lookup. */
  dots: { x: number; y: number; atMs: number; value: number }[]
}

/** The stretch, in plot px, over which a wash fades to nothing at its newest end. */
export interface WashFade {
  from: number
  to: number
}
const WASH_FADE_PX = 28

/** THE ONE SPELLING OF A WASH'S RIGHT EDGE, for every chart (series and price): the wash is opaque until `from` and gone at `to`, the
 *  newest point. A wash shorter than twice the stretch fades over its half. Null: nothing to fade. */
export function washFade(firstX: number, lastX: number): WashFade | null {
  const len = lastX - firstX
  if (!(len > 0)) return null
  return { from: lastX - Math.min(WASH_FADE_PX, len / 2), to: lastX }
}

/** WHAT A POINT OF A SUM STANDS FOR: the stretch of time whose money it adds. `quarter` is one of the Stats count's own rows (the quarter hour it adds,
 *  stood at its END); `hour` and `day` are the buckets those rows fold into for the longer spans (stood at the last slot's own instant, anywhere inside
 *  the bucket); `week` and `month` are the record's periods (world.history), each stood at its first day. */
export type SumPeriod = 'quarter' | 'hour' | 'day' | 'week' | 'month'

const HOUR_MS = 3_600_000
const DAY_MS = 86_400_000

/** Where a period ends, from the instant its point stands at: a count's row at its own instant; an hour or a day floored to its UTC hour or day (the server
 *  buckets by the row's own UTC hour / day, public.stats_bucket); a week 7 days and a month its LONGEST length, 31 days, after the first day it stands at. */
function periodEnd(atMs: number, period: SumPeriod): number {
  switch (period) {
    case 'quarter':
      return atMs
    case 'hour':
      return Math.floor(atMs / HOUR_MS) * HOUR_MS + HOUR_MS
    case 'day':
      return Math.floor(atMs / DAY_MS) * DAY_MS + DAY_MS
    case 'week':
      return atMs + 7 * DAY_MS
    case 'month':
      return atMs + 31 * DAY_MS
  }
}

/** THE ONE RULE OF WHICH POINTS OF A SUM ARE WHOLE (owner, 2026-11-06, and again 2026-11-07: *"i said i don't like the right edge of the chart goes down.
 *  every chart"*). A quarter hour, an hour, a day of money sold / earned / minted is a SUM, and a sum is a figure only once its period is over. Drawn beside
 *  whole ones, a period still running plunges at the right edge: a good's day on 2026-11-06 sold 6,728 against 95,202 the day before, and every Stats series
 *  ends in a LIVE point at now() whose flows are only the minutes since the last count (prod, 2026-11-07 07:22 UTC: 1,821,942 sold against 26,122,487 in the
 *  quarter hour before it, 93 % down). `reachMs` is the instant the figures are complete to.
 *   1. Nothing that stands after the reach is a period: that is the live point.
 *   2. Of what is left only the NEWEST can still be running: it is left out while its period ends after the reach, so an hour or a day still being counted
 *      goes, and a quarter hour (a count's own row) never does. Nothing is drawn in a left-out period's place.
 *  A Stats read's reach is its `counted_at` (the last count; the server says its live point adds "the minutes since" it), not the clock, so a count that has
 *  not run leaves its hour open rather than showing it short. A record (world.history, the report's days) has no live point and is complete to now: its
 *  reach is the server's now. The client does no month arithmetic (the month is the server's, tests/duplication.spec.ts), so a month is judged by its
 *  longest length: it is held back for the minutes between its end and the new month's first row, never shown short.
 *  A LEVEL (a purse, a price, a count of ships) is not a sum: its newest reading is true, and the caller does not pass it here. */
export function wholePeriods<P extends { atMs: number }>(points: readonly P[], period: SumPeriod, reachMs: number): P[] {
  const reached = points.filter((p) => p.atMs <= reachMs)
  let newest = -Infinity
  for (const p of reached) if (p.atMs > newest) newest = p.atMs
  return reached.length > 0 && periodEnd(newest, period) > reachMs ? reached.filter((p) => p.atMs !== newest) : reached
}

export const SERIES_CHART_W = 340
export const SERIES_CHART_H = 120
const PAD = { left: 8, right: 8, top: 8, bottom: 18 }

/** "6h", "2d", "45m", "2.5y" — how far before the newest point an instant lies. THE one spelling of a
 *  stretch of time on a chart's axis: the price chart reads it too (0226, for days and years). */
export function agoLabel(ms: number): string {
  if (ms < 60_000) return t('shell.now')
  const min = Math.round(ms / 60_000)
  if (min < 60) return t('format.shortM', { n: min })
  const h = Math.round(ms / 3_600_000)
  if (h < 48) return t('format.agoHour', { n: h })
  const d = Math.round(ms / 86_400_000)
  if (d < 730) return t('format.agoDay', { n: d })
  const y = Math.round((ms / (365 * 86_400_000)) * 10) / 10
  return t('format.agoYear', { n: Number.isInteger(y) ? String(y) : y.toFixed(1) })
}

export function seriesChartModel(
  points: readonly SeriesPoint[],
  size: { width: number; height: number } = { width: SERIES_CHART_W, height: SERIES_CHART_H },
): SeriesChartModel | null {
  if (points.length < 2) return null
  const sorted = [...points].sort((a, b) => a.atMs - b.atMs)
  const plot = {
    x: PAD.left,
    y: PAD.top,
    w: size.width - PAD.left - PAD.right,
    h: size.height - PAD.top - PAD.bottom,
  }
  const t0 = sorted[0].atMs
  const t1 = sorted[sorted.length - 1].atMs
  const span = Math.max(1, t1 - t0)
  let lo = Math.min(...sorted.map((p) => p.value))
  let hi = Math.max(...sorted.map((p) => p.value))
  if (hi === lo) {
    // a flat line gets a band to sit in the middle of, rather than a division by zero
    const pad = Math.abs(hi) * 0.05 || 1
    lo -= pad
    hi += pad
  }
  const x = (t: number) => plot.x + ((t - t0) / span) * plot.w
  const y = (v: number) => plot.y + plot.h - ((v - lo) / (hi - lo)) * plot.h
  const dots = sorted.map((p) => ({ x: x(p.atMs), y: y(p.value), atMs: p.atMs, value: p.value }))
  const line = dots.map((d, i) => `${i === 0 ? 'M' : 'L'}${d.x.toFixed(1)} ${d.y.toFixed(1)}`).join(' ')
  const floor = plot.y + plot.h
  const area = `${line} L${dots[dots.length - 1].x.toFixed(1)} ${floor} L${dots[0].x.toFixed(1)} ${floor} Z`
  const areaFade = washFade(dots[0].x, dots[dots.length - 1].x)
  const yTicks = [lo, (lo + hi) / 2, hi].map((v) => ({ y: y(v), value: v }))
  const xTicks = [
    { x: plot.x, label: agoLabel(t1 - t0) },
    { x: plot.x + plot.w / 2, label: agoLabel((t1 - t0) / 2) },
    { x: plot.x + plot.w, label: t('shell.now') },
  ]
  return { width: size.width, height: size.height, plot, line, area, areaFade, yTicks, xTicks, dots }
}

/** The dot nearest an x in plot pixels — the hover layer's one question. */
export function nearestDot(model: SeriesChartModel, px: number): SeriesChartModel['dots'][number] {
  let best = model.dots[0]
  for (const d of model.dots) if (Math.abs(d.x - px) < Math.abs(best.x - px)) best = d
  return best
}
