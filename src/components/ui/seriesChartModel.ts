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
  /** Three y figures, served scale: low, mid, high. */
  yTicks: { y: number; value: number }[]
  /** The x axis's words: how long before the last point each tick stands. */
  xTicks: { x: number; label: string }[]
  /** Every point's pixel, for the hover layer: nearest-x lookup. */
  dots: { x: number; y: number; atMs: number; value: number }[]
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
  const yTicks = [lo, (lo + hi) / 2, hi].map((v) => ({ y: y(v), value: v }))
  const xTicks = [
    { x: plot.x, label: agoLabel(t1 - t0) },
    { x: plot.x + plot.w / 2, label: agoLabel((t1 - t0) / 2) },
    { x: plot.x + plot.w, label: t('shell.now') },
  ]
  return { width: size.width, height: size.height, plot, line, area, yTicks, xTicks, dots }
}

/** The dot nearest an x in plot pixels — the hover layer's one question. */
export function nearestDot(model: SeriesChartModel, px: number): SeriesChartModel['dots'][number] {
  let best = model.dots[0]
  for (const d of model.dots) if (Math.abs(d.x - px) < Math.abs(best.x - px)) best = d
  return best
}
