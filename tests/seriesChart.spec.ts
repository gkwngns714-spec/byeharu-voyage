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

test('the hover layer finds the nearest point, and the "ago" words round honestly', () => {
  const m = seriesChartModel([
    { atMs: 0, value: 1 },
    { atMs: H, value: 2 },
    { atMs: 2 * H, value: 3 },
  ])!
  expect(nearestDot(m, m.dots[1].x + 1).atMs).toBe(H)
  expect(nearestDot(m, 0).atMs).toBe(0)
  expect(agoLabel(30_000)).toBe('now')
  expect(agoLabel(14 * 60_000)).toBe('14m')
  expect(agoLabel(6 * H)).toBe('6h')
  expect(agoLabel(3 * 24 * H)).toBe('3d')
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
