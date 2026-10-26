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
import { clampPan, panBackMs, panByDrag, panByKey, panView } from '../src/components/ui/chartPan'
import { PRICE_CHART_H, PRICE_CHART_W, priceChartModel } from '../src/components/ui/priceChartModel'
import { MINUS } from '../src/lib/format'
import type { PricePoint } from '../src/lib/rpc'

/** `n` served points, one per step, the newest `slotSeconds` before `nowMs`. Both sides carry the same
 *  figure here, so every expectation below reads one price: the two-sided cases are their own tests. */
function series(values: number[], slotSeconds: number, nowMs: number): PricePoint[] {
  const n = values.length
  return values.map((v, i) => ({
    at: new Date(nowMs - (n - i) * slotSeconds * 1000).toISOString(),
    ask: v,
    bid: v,
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
    { at: new Date(NOW - 6 * 3_600_000).toISOString(), ask: 100, bid: 100 },
    { at: new Date(NOW - 600_000).toISOString(), ask: 120, bid: 120 },
  ]
  const m = priceChartModel(pts, 600, NOW)!
  expect(m.spanHours).toBeCloseTo(6, 6)
  expect(m.xTicks[0].label).toBe(`${MINUS}6h`)
  expect(m.points[0].x).toBeCloseTo(m.plot.x, 6)
})

test('the marks sit on the lowest, highest and latest served points, and ties go to the latest', () => {
  const m = priceChartModel(series([100, 90, 130, 90, 130, 110], 600, NOW), 600, NOW)!
  expect(m.low.index).toBe(3)
  expect(m.low.value).toBe(90)
  expect(m.high.index).toBe(4)
  expect(m.high.value).toBe(130)
  expect(m.now.index).toBe(5)
  expect(m.now.value).toBe(110)
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
  expect(priceChartModel([{ at: 'not a time', ask: 100, bid: 100 }, { at: new Date(NOW).toISOString(), ask: 110, bid: 110 }], 600, NOW)).toBeNull()
  // A flat record is drawn through the middle with ONE label — "it did not move" is an answer.
  const flat = priceChartModel(series([100, 100, 100], 600, NOW), 600, NOW)!
  expect(flat.yTicks.map((t) => t.label)).toEqual(['100'])
  expect(flat.points.every((p) => Math.abs(p.y - (flat.plot.y + flat.plot.h / 2)) < 1e-6)).toBe(true)
})

// ── 2026-10-18: THE ESTIMATE (docs/COMMAND_DESK.md §5.4) ─────────────────────────────────────────
// The served outlook is drawn to the right of now: the axis runs on to its last instant (`+Nh`), the
// dashed path and the band are its own points, the best time and the arrival are marks — and the
// y scale takes the band in, with decimals that follow the span (prices run ~1 to ~100,000 a unit).

function outlook(values: number[], width: number, nowMs: number, slotSeconds: number) {
  return values.map((v, k) => ({
    at: new Date(nowMs + k * slotSeconds * 1000).toISOString(),
    value: v,
    lo: v - width * k,
    hi: v + width * k,
  }))
}

test('the estimate runs on from now: +Nh at the edge, the band in the scale, the best time and the arrival marked', () => {
  const pts = outlook([110, 112, 114, 115, 115], 2, NOW, 900)
  const m = priceChartModel(series([100, 120, 90, 130, 110], 600, NOW), 600, NOW, {
    points: pts,
    bestAt: pts[3].at,
    arriveMs: NOW + 1800_000,
  })!
  expect(m.outlook).not.toBeNull()
  expect(m.xTicks.map((t) => t.label)).toEqual([`${MINUS}0.8h`, 'now', '+1h'])
  // a record too short for its own label beside now is labelled at now alone
  const short = priceChartModel(series([100, 101], 900, NOW), 900, NOW, { points: outlook(Array(25).fill(100), 1, NOW, 900) })!
  expect(short.xTicks.map((t) => t.label)).toEqual(['now', '+6h'])
  // now stands between the record and the estimate, and the estimate ends at the right edge
  expect(m.outlook!.nowX).toBeGreaterThan(m.plot.x)
  expect(m.outlook!.nowX).toBeLessThan(m.plot.x + m.plot.w)
  expect(m.outlook!.line.split(' L')).toHaveLength(5)
  expect(m.outlook!.band.endsWith('Z')).toBe(true)
  // the scale takes the band in: the top label is the band's top (115 + 2×4 = 123 < 130, so the record's 130)
  expect(m.yTicks.map((t) => t.label)).toEqual(['90', '110', '130'])
  expect(m.outlook!.best!.value).toBe(115)
  expect(m.outlook!.arriveX).not.toBeNull()
  expect(m.outlook!.arriveX!).toBeGreaterThan(m.outlook!.nowX)
})

test('an estimate with no record still draws, from now; and small or large prices keep their meaning', () => {
  const small = priceChartModel([], 900, NOW, { points: outlook([1.2, 1.25, 1.3], 0.05, NOW, 900) })!
  expect(small).not.toBeNull()
  expect(small.points).toHaveLength(0)
  expect(small.xTicks[0].label).toBe('now')
  expect(small.yTicks.map((t) => t.label)).toEqual(['1.20', '1.30', '1.40'])
  const large = priceChartModel([], 900, NOW, { points: outlook([98_000, 99_000, 100_000], 0, NOW, 900) })!
  expect(large.yTicks.map((t) => t.label)).toEqual(['98,000', '99,000', '100,000'])
})

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE WINDOW AND THE DRAG — owner request 178, 2026-10-20: *"make the chart dragable to see the past
// prices by swiping left?"*
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The model takes a WINDOW (a from and a to) and draws that stretch: the axis spans it, x is no longer
// clamped so a point outside it keeps its true place for the painter to clip, and the y band and the
// marks are read from what is INSIDE it. `chartPan` turns a drag into that window and is pure, so the
// gesture is proved here too — a pointer never enters this file.

const H = 3_600_000

test('a window draws that stretch and no other: the axis spans it, x is not clamped, the band is what is inside', () => {
  // 8 h of record: a tall plateau for the first 6 h, then the last 2 h between 100 and 111.
  const mids = Array.from({ length: 48 }, (_, i) => (i < 36 ? 1000 : 100 + (i - 36)))
  const view = { fromMs: NOW - 2 * H, toMs: NOW }
  const m = priceChartModel(series(mids, 600, NOW), 600, NOW, null, undefined, null, view)!
  expect(m).not.toBeNull()
  // the y band is the window's own: the plateau outside it is not in the scale
  expect(m.yTicks[0].label).toBe('100')
  expect(m.yTicks[2].label).toBe('111')
  // the axis says where the window's edges are, in hours from now
  expect(m.xTicks.map((t) => t.label)).toEqual([`${MINUS}2h`, `${MINUS}1h`, 'now'])
  // a point 8 h back keeps its true place, off the plot's left edge, for the painter to clip
  expect(m.points[0].x).toBeLessThan(m.plot.x)
  expect(m.points[47].x).toBeCloseTo(m.plot.x + m.plot.w - m.plot.w / 12, 3)
  // the marks are the window's own: the record's 1000 is not this chart's high
  expect(m.low.value).toBe(100)
  expect(m.high.value).toBe(111)
})

test('a window with the estimate in it labels `now` where it falls, not at the right edge', () => {
  const view = { fromMs: NOW - 4 * H, toMs: NOW + 2 * H }
  const m = priceChartModel(
    series([100, 101, 102, 103], 900, NOW),
    900,
    NOW,
    { points: outlook([103, 106, 109], 2, NOW, 900) },
    undefined,
    null,
    view,
  )!
  expect(m.xTicks.map((t) => t.label)).toEqual([`${MINUS}4h`, 'now', '+2h'])
  // now stands two hours in from the right edge of a six-hour window: a third of the plot back
  expect(m.outlook!.nowX).toBeCloseTo(m.plot.x + m.plot.w * (4 / 6), 3)
})

test('a drag moves the window with the finger and cannot leave the record', () => {
  const limits = { oldestMs: NOW - 8 * H, newestMs: NOW, spanMs: 2 * H }
  expect(panBackMs(limits)).toBe(6 * H)
  // dragging RIGHT by half the plot brings in an hour of earlier prices (half of a two-hour window)
  expect(panByDrag(0, 170, 340, limits)).toBe(1 * H)
  expect(panView(1 * H, limits)).toEqual({ fromMs: NOW - 3 * H, toMs: NOW - 1 * H })
  // dragging LEFT from the right edge does nothing: there is nothing after now to look at
  expect(panByDrag(0, -170, 340, limits)).toBe(0)
  // and a long drag stops at the oldest point rather than running off it
  expect(panByDrag(0, 3400, 340, limits)).toBe(6 * H)
  expect(panView(99 * H, limits)).toEqual({ fromMs: NOW - 8 * H, toMs: NOW - 6 * H })
  // a plot of no width cannot be dragged, and nonsense is nought
  expect(panByDrag(2 * H, 100, 0, limits)).toBe(2 * H)
  expect(clampPan(Number.NaN, limits)).toBe(0)
})

test('a window as wide as the record has nothing behind it, so there is nothing to drag', () => {
  const limits = { oldestMs: NOW - 8 * H, newestMs: NOW, spanMs: 8 * H }
  expect(panBackMs(limits)).toBe(0)
  expect(panByDrag(0, 1000, 340, limits)).toBe(0)
  expect(panByKey(0, true, limits)).toBe(0)
  expect(panView(5 * H, limits)).toEqual({ fromMs: NOW - 8 * H, toMs: NOW })
})

test('the keyboard walks a quarter of a window, and the left arrow goes into the past', () => {
  const limits = { oldestMs: NOW - 8 * H, newestMs: NOW, spanMs: 2 * H }
  expect(panByKey(0, true, limits)).toBe(0.5 * H)
  expect(panByKey(0.5 * H, true, limits)).toBe(1 * H)
  expect(panByKey(1 * H, false, limits)).toBe(0.5 * H)
  expect(panByKey(0, false, limits)).toBe(0)
})

// ── 0226: BOTH SIDES (owner row 189), and a record that reaches back days and years (owner row 205) ──
// A served point carries the city's ask (null where it does not sell the good) and its bid. The chart
// draws both; the PRIMARY line — the ask where there is one, else the bid — carries the ground and the
// marks. The folded tiers' low…high is a band under each line and inside the y scale.

test('a city that only buys the good is read on its bid: no ask line, the marks on the bid, the scale its own', () => {
  const n = 6
  const pts: PricePoint[] = [100, 90, 130, 90, 130, 110].map((bid, i) => ({
    at: new Date(NOW - (n - i) * 900_000).toISOString(),
    ask: null,
    bid,
  }))
  const m = priceChartModel(pts, 900, NOW)!
  expect(m.primary).toBe('bid')
  expect(m.sides.ask).toBe('')
  expect(m.sides.bid).not.toBe('')
  expect(m.line).toBe(m.sides.bid)
  expect(m.low.value).toBe(90)
  expect(m.high.value).toBe(130)
  expect(m.now.value).toBe(110)
  expect(m.yTicks.map((t) => t.label)).toEqual(['90', '110', '130'])
  expect(m.bands).toEqual({ ask: '', bid: '' })
})

test('a city that sells the good is read on its ask, and the bid is drawn under it in the same scale', () => {
  const n = 4
  const pts: PricePoint[] = [100, 110, 120, 130].map((ask, i) => ({
    at: new Date(NOW - (n - i) * 900_000).toISOString(),
    ask,
    bid: ask * 0.8,
  }))
  const m = priceChartModel(pts, 900, NOW)!
  expect(m.primary).toBe('ask')
  expect(m.line).toBe(m.sides.ask)
  expect(m.sides.bid).not.toBe('')
  expect(m.sides.bid).not.toBe(m.sides.ask)
  expect(m.low.value).toBe(100)
  expect(m.high.value).toBe(130)
  // the scale takes the bid in: its lowest point (80) is the floor
  expect(m.yTicks.map((t) => t.label)).toEqual(['80', '105', '130'])
})

test('a folded tier draws each side\'s low…high as a band, inside the scale; a long record is labelled in days and years', () => {
  const days = 30
  const pts: PricePoint[] = Array.from({ length: days }, (_, i) => ({
    at: new Date(NOW - (days - i) * 86_400_000).toISOString(),
    ask: 100,
    ask_lo: 95,
    ask_hi: 108,
    bid: 80,
    bid_lo: 76,
    bid_hi: 84,
  }))
  const m = priceChartModel(pts, 86_400, NOW)!
  expect(m.bands.ask.endsWith('Z')).toBe(true)
  expect(m.bands.bid.endsWith('Z')).toBe(true)
  expect(m.yTicks.map((t) => t.label)).toEqual(['76', '92', '108'])
  expect(m.spanHours).toBeCloseTo(30 * 24, 6)
  expect(m.xTicks.map((t) => t.label)).toEqual([`${MINUS}30d`, `${MINUS}15d`, 'now'])
  const years = 3 * 365
  const long = Array.from({ length: years }, (_, i) => ({ at: new Date(NOW - (years - i) * 86_400_000).toISOString(), ask: 1, bid: 1 }))
  expect(priceChartModel(long, 86_400, NOW)!.xTicks[0].label).toBe(`${MINUS}3y`)
})
