// PURE UNIT SPEC — src/components/ui/priceChartModel.ts. No browser: this file never asks for
// the `page` fixture, so Playwright runs it as a plain Node process.
//
// WHAT IT PINS (docs/QUAY_LEDGER.md Appendix A B, owner row 76 slice 3): the chart's axes say what
// was SERVED and nothing else. The y scale is the record's own min, midpoint and max; the x axis is
// hours before now DERIVED from the points and `slot_seconds`, ending at `now`; the three marks sit
// on the lowest, highest and latest served points. The tripwire the appendix names — a `12 h` or a
// `48` literal in the axis wording — is asserted against here: change the cadence or the count and
// the label must move with them.

import { test, expect } from '@playwright/test'
import { PRICE_CHART_H, PRICE_CHART_W, priceChartModel } from '../src/components/ui/priceChartModel'
import { MINUS } from '../src/lib/format'
import type { PricePoint } from '../src/lib/rpc'

/** `n` served points, one per slot, the newest `slotSeconds` before `nowMs`. */
function series(mids: number[], slotSeconds: number, nowMs: number): PricePoint[] {
  const n = mids.length
  return mids.map((mid, i) => ({
    slot: 1000 + i,
    at: new Date(nowMs - (n - i) * slotSeconds * 1000).toISOString(),
    mid,
  }))
}

const NOW = Date.parse('2026-09-13T12:00:00Z')

test('the plane is 340×170 and the y scale is the served min, the round midpoint and the served max', () => {
  const m = priceChartModel(series([100, 120, 90, 130, 110], 600, NOW), 600, NOW)!
  expect(m).not.toBeNull()
  expect(m.width).toBe(PRICE_CHART_W)
  expect(m.height).toBe(PRICE_CHART_H)
  expect([m.width, m.height]).toEqual([340, 170])
  expect(m.yTicks.map((t) => t.label)).toEqual(['90', '110', '130'])
  // Bottom to top: the min sits lowest on the plane (largest y), the max highest.
  expect(m.yTicks[0].y).toBeGreaterThan(m.yTicks[1].y)
  expect(m.yTicks[1].y).toBeGreaterThan(m.yTicks[2].y)
  // The extremes sit on the plot's edges — the band is the data's own, never scaled to zero.
  expect(m.yTicks[0].y).toBeCloseTo(m.plot.y + m.plot.h, 6)
  expect(m.yTicks[2].y).toBeCloseTo(m.plot.y, 6)
})

test('the x axis is hours before now, derived from the served cadence and count — no literal window', () => {
  // 48 slots of 600 s is 8 h: the label must say so because the DATA says so.
  const eight = priceChartModel(series(Array.from({ length: 48 }, (_, i) => 100 + (i % 7)), 600, NOW), 600, NOW)!
  expect(eight.spanHours).toBeCloseTo(8, 6)
  expect(eight.xTicks.map((t) => t.label)).toEqual([`${MINUS}8h`, `${MINUS}4h`, 'now'])
  // Halve the cadence and the same 48 points are 4 h; double the count and they are 16 h.
  const four = priceChartModel(series(Array.from({ length: 48 }, () => 100), 300, NOW), 300, NOW)!
  expect(four.xTicks[0].label).toBe(`${MINUS}4h`)
  const sixteen = priceChartModel(series(Array.from({ length: 96 }, () => 100), 600, NOW), 600, NOW)!
  expect(sixteen.xTicks[0].label).toBe(`${MINUS}16h`)
  // The right edge is `now`, and the last point stands on it.
  expect(eight.xTicks[2].x).toBeCloseTo(eight.plot.x + eight.plot.w, 6)
  expect(eight.now.x).toBeCloseTo(eight.plot.x + eight.plot.w - eight.plot.w / 48, 3)
  // A fractional span prints one decimal: 9 slots of 600 s is 1.5 h.
  const odd = priceChartModel(series(Array.from({ length: 9 }, () => 100), 600, NOW), 600, NOW)!
  expect(odd.xTicks[0].label).toBe(`${MINUS}1.5h`)
})

test('a record older than its cadence × count reads at its true age, so a gap is a gap', () => {
  // Two points, one 6 h ago and one 10 min ago: the span is 6 h, not 20 min.
  const pts: PricePoint[] = [
    { slot: 1, at: new Date(NOW - 6 * 3_600_000).toISOString(), mid: 100 },
    { slot: 37, at: new Date(NOW - 600_000).toISOString(), mid: 120 },
  ]
  const m = priceChartModel(pts, 600, NOW)!
  expect(m.spanHours).toBeCloseTo(6, 6)
  expect(m.xTicks[0].label).toBe(`${MINUS}6h`)
  expect(m.points[0].x).toBeCloseTo(m.plot.x, 6)
})

test('the marks sit on the lowest, highest and latest served points, and ties go to the latest', () => {
  const m = priceChartModel(series([100, 90, 130, 90, 130, 110], 600, NOW), 600, NOW)!
  expect(m.low.index).toBe(3)
  expect(m.low.mid).toBe(90)
  expect(m.high.index).toBe(4)
  expect(m.high.mid).toBe(130)
  expect(m.now.index).toBe(5)
  expect(m.now.mid).toBe(110)
  expect(m.points).toHaveLength(6)
  // The line visits every point in order; the area closes down to the floor.
  expect(m.line.split(' L')).toHaveLength(6)
  expect(m.area.startsWith(m.line)).toBe(true)
  expect(m.area.endsWith('Z')).toBe(true)
})

test('nothing is drawn below two points, without a cadence, or with a point that has no time', () => {
  expect(priceChartModel(series([100], 600, NOW), 600, NOW)).toBeNull()
  expect(priceChartModel([], 600, NOW)).toBeNull()
  expect(priceChartModel(series([100, 110], 600, NOW), 0, NOW)).toBeNull()
  expect(priceChartModel([{ slot: 1, at: 'not a time', mid: 100 }, { slot: 2, at: new Date(NOW).toISOString(), mid: 110 }], 600, NOW)).toBeNull()
  // A flat record is drawn through the middle with ONE label — "it did not move" is an answer.
  const flat = priceChartModel(series([100, 100, 100], 600, NOW), 600, NOW)!
  expect(flat.yTicks.map((t) => t.label)).toEqual(['100'])
  expect(flat.points.every((p) => Math.abs(p.y - (flat.plot.y + flat.plot.h / 2)) < 1e-6)).toBe(true)
})
