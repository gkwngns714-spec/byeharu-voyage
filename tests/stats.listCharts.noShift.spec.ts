import { test, expect } from '@playwright/test'
import { PHONE, reachable, ready } from './appReady.fixture'

// A LATE CHART READ MOVES NOTHING (owner's law: pressing a control never re-flows the page; found 2026-11-06 as the intermittent
// red of stats.goodTray.spec.ts, "first row's top moved, Expected 311 Received 463" at 1280 and +304 at 390).
// The cause: Cities and Markets draw their two chart cards from `world.stats_overview` (WorldSeries.tsx), a read of its own that
// answers AFTER the list's (one PGlite queue). Until it answered, each card held the one-line "line soon" note (44 px); when it
// landed the card grew to the chart (20 px reading line + 176 px) and the whole list under it dropped by 152 px (two stacked
// cards: 304 on a phone). Whether a spec saw it depended on whether the two reads landed in the same frame.
// A local world has no network seam to hold a read, so the CPU is slowed 6x (the reads land far apart) and a per-frame sampler,
// started before the tab is pressed, records the list's document-top and what each card holds on EVERY frame until the charts are
// drawn: the list's top must be one number throughout. Names SeriesChart.tsx, WorldSeries.tsx, Cities.tsx and Markets.tsx.

const WIDE = { width: 1280, height: 707 }
const FACES = [
  { tab: 'Cities', list: 'stats-cities', charts: ['stats-chart-city-purses', 'stats-chart-city-trade'] },
  { tab: 'Markets', list: 'stats-goods', charts: ['stats-chart-market-sold', 'stats-chart-market-bought'] },
] as const

for (const vp of [PHONE, WIDE]) {
  for (const face of FACES) {
    test(`${face.tab}: the chart read landing late moves nothing at ${vp.width}px`, async ({ page, request, baseURL }) => {
      test.setTimeout(420_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
      await page.setViewportSize(vp)
      await page.goto('stats')
      await ready(page)
      const cdp = await page.context().newCDPSession(page)
      await cdp.send('Emulation.setCPUThrottlingRate', { rate: 6 })
      await page.evaluate(
        ({ list, charts }) => {
          const log: { top: number; drawn: number }[] = []
          ;(window as unknown as { __frames: typeof log }).__frames = log
          const tick = () => {
            const el = document.querySelector(`[data-testid="${list}"]`)
            if (el) {
              const drawn = charts.filter((id) => document.querySelector(`[data-testid="${id}"] [role="img"]`)).length
              log.push({ top: Math.round(el.getBoundingClientRect().top + window.scrollY), drawn })
            }
            requestAnimationFrame(tick)
          }
          requestAnimationFrame(tick)
        },
        { list: face.list, charts: [...face.charts] },
      )
      await page.getByRole('tab', { name: face.tab, exact: true }).click()
      await expect(page.getByTestId(face.list)).toBeVisible({ timeout: 240_000 })
      // the charts are drawn once the overview read has landed (a world with no record keeps the note, and the wait ends)
      await page.waitForFunction((id) => document.querySelector(`[data-testid="${id}"] [role="img"]`) !== null, face.charts[0], { timeout: 60_000 }).catch(() => {})
      await page.evaluate(() => new Promise<void>((r) => requestAnimationFrame(() => requestAnimationFrame(() => r()))))
      const frames = await page.evaluate(() => (window as unknown as { __frames: { top: number; drawn: number }[] }).__frames)
      const tops = [...new Set(frames.map((f) => f.top))]
      expect(frames.length, 'the sampler saw no frame of the list').toBeGreaterThan(0)
      expect(tops, `the list moved while the charts arrived: ${JSON.stringify(frames.filter((f, i) => i === 0 || f.top !== frames[i - 1].top || f.drawn !== frames[i - 1].drawn))}`).toHaveLength(1)
    })
  }
}
