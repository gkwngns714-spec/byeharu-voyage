import { test, expect } from '@playwright/test'
import { agoLabel, nearestDot, seriesChartModel } from '../src/components/ui/seriesChartModel'

// THE SERIES CHART'S GEOMETRY (0214) — pure, so the axis is proved here without a browser. The x axis is
// TIME (a gap in the record stays a gap), the y band is the data's own, a flat line sits in the middle,
// and below two points there is no chart.

const H = 3_600_000

test('two points make a line across the plot, the newest at the right edge, the band the data\'s own', () => {
  const m = seriesChartModel([
    { atMs: 0, value: 100 },
    { atMs: 2 * H, value: 300 },
  ])!
  expect(m).not.toBeNull()
  expect(m.dots[0].x).toBe(m.plot.x)
  expect(m.dots[1].x).toBe(m.plot.x + m.plot.w)
  // low at the floor, high at the ceiling
  expect(m.dots[0].y).toBeCloseTo(m.plot.y + m.plot.h, 5)
  expect(m.dots[1].y).toBeCloseTo(m.plot.y, 5)
  expect(m.yTicks.map((t) => t.value)).toEqual([100, 200, 300])
  expect(m.xTicks.map((t) => t.label)).toEqual(['2h', '1h', 'now'])
})

test('the x axis is time, not index: an unevenly spaced record keeps its gaps', () => {
  const m = seriesChartModel([
    { atMs: 0, value: 1 },
    { atMs: 1 * H, value: 2 },
    { atMs: 4 * H, value: 3 },
  ])!
  const [a, b, c] = m.dots
  expect((b.x - a.x) / (c.x - a.x)).toBeCloseTo(0.25, 5)
})

test('a flat line sits in the middle, and one point is no chart', () => {
  const flat = seriesChartModel([
    { atMs: 0, value: 50 },
    { atMs: H, value: 50 },
  ])!
  expect(flat.dots[0].y).toBeCloseTo(flat.plot.y + flat.plot.h / 2, 5)
  expect(seriesChartModel([{ atMs: 0, value: 1 }])).toBeNull()
  expect(seriesChartModel([])).toBeNull()
})

// A FLAT SERIES INVENTS NO RANGE (the drive audit, 2026-11-08, D5): a young city's purse of 0 was drawn between the y figures
// "1 🪙" and "−1 🪙" — a band the model padded in so as not to divide by zero, printed as if it were the data's. A flat line
// has ONE y figure, its own value, at the line (the price chart's rule for a flat price); the padding stays geometry.
test('a flat series has one y figure, its own value — never a ±1 band around a purse of 0', () => {
  const zero = seriesChartModel([
    { atMs: 0, value: 0 },
    { atMs: 30_000, value: 0 },
  ])!
  expect(zero.yTicks.map((t) => t.value)).toEqual([0])
  expect(zero.yTicks[0].y).toBeCloseTo(zero.dots[0].y, 5)
  const flat = seriesChartModel([
    { atMs: 0, value: 50 },
    { atMs: H, value: 50 },
  ])!
  expect(flat.yTicks).toEqual([{ y: flat.dots[0].y, value: 50 }])
  // a series that moves keeps its three figures, the data's own
  const moving = seriesChartModel([
    { atMs: 0, value: 10 },
    { atMs: H, value: 30 },
  ])!
  expect(moving.yTicks.map((t) => t.value)).toEqual([10, 20, 30])
})

test('the hover layer finds the nearest point, and the "ago" words round honestly', () => {
  const m = seriesChartModel([
    { atMs: 0, value: 1 },
    { atMs: H, value: 2 },
    { atMs: 2 * H, value: 3 },
  ])!
  expect(nearestDot(m, m.dots[1].x + 1).atMs).toBe(H)
  expect(nearestDot(m, 0).atMs).toBe(0)
  expect(agoLabel(14 * 60_000)).toBe('14m')
  expect(agoLabel(6 * H)).toBe('6h')
  expect(agoLabel(3 * 24 * H)).toBe('3d')
})

// THE AXIS TELLS THE TIME AT ANY SPAN (the drive audit, 2026-11-08, D5): a series counted within one minute labelled all three
// x ticks "now" (`walk/w-stats-cities.png`), since anything under a minute was rounded to "now". ONE rule for every stretch:
// seconds under a minute, minutes under an hour, then hours, days, years — and two neighbouring labels never say the same thing.
test('a stretch under a minute is labelled in seconds, and no two x labels say the same thing', () => {
  expect(agoLabel(30_000)).toBe('30s')
  expect(agoLabel(5_000)).toBe('5s')
  expect(agoLabel(59_600)).toBe('1m')
  // nought seconds before the newest point is the newest point
  expect(agoLabel(400)).toBe('now')
  const young = seriesChartModel([
    { atMs: 0, value: 0 },
    { atMs: 20_000, value: 0 },
    { atMs: 40_000, value: 0 },
  ])!
  expect(young.xTicks.map((t) => t.label)).toEqual(['40s', '20s', 'now'])
  // a span whose half rounds to the same word as an edge loses its middle, never an edge
  const blink = seriesChartModel([
    { atMs: 0, value: 1 },
    { atMs: 1_000, value: 2 },
  ])!
  expect(blink.xTicks.map((t) => t.label)).toEqual(['1s', 'now'])
  expect(blink.xTicks[0].x).toBe(blink.plot.x)
  expect(blink.xTicks[1].x).toBe(blink.plot.x + blink.plot.w)
  // a span that itself rounds to now is "now" alone, at the right edge
  const instant = seriesChartModel([
    { atMs: 0, value: 1 },
    { atMs: 300, value: 2 },
  ])!
  expect(instant.xTicks.map((t) => t.label)).toEqual(['now'])
  expect(instant.xTicks[0].x).toBe(instant.plot.x + instant.plot.w)
})

// THE RIGHT EDGE DOES NOT DROP (owner, 2026-11-06, 2026-11-07). Which points of a SUM may be drawn is tests/wholePeriods.spec.ts; the wall is here.

test('the wash under the line fades out at the newest point: no vertical wall', async () => {
  const { washFade } = await import('../src/components/ui/seriesChartModel')
  const m = seriesChartModel([{ atMs: 0, value: 1 }, { atMs: H, value: 2 }, { atMs: 2 * H, value: 3 }])!
  expect(m.areaFade).toEqual(washFade(m.dots[0].x, m.dots[2].x))
  expect(m.areaFade!.to).toBe(m.dots[2].x)
  expect(m.areaFade!.from).toBeLessThan(m.areaFade!.to)
  // a wash shorter than twice the stretch fades over its half, never past its own start
  expect(washFade(0, 20)).toEqual({ from: 10, to: 20 })
  expect(washFade(5, 5)).toBeNull()
})
