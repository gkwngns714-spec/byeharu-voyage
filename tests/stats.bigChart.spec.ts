import { test, expect } from '@playwright/test'
import { PHONE, reachable, ready } from './appReady.fixture'

// A STATS CHART OPENS LARGE (owner row 232, 0246; StatsChart.tsx): tapping a Stats chart opens the same Tray the Buy / Sell
// good page opens its price chart in, with the shared span picker (1d · 1w · 1m · 1y · All) over the same SeriesChart,
// drawn large. Pressing a span asks the server for that span — the Overview's root names the span its newest answer
// came back with (`data-span`, the read's own echo, world.stats_overview 0246) — and closing leaves the page as it was.
// It names StatsChart.tsx and Overview.tsx so CI's rule N selects it.

const WIDE = { width: 1280, height: 707 }

for (const vp of [PHONE, WIDE]) {
  test(`a stats chart opens large and the span switches the series at ${vp.width}px`, async ({ page, request, baseURL }) => {
    test.setTimeout(420_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await page.setViewportSize(vp)
    await page.goto('stats')
    await ready(page)
    await expect(page.getByTestId('stats-overview')).toBeVisible({ timeout: 120_000 })
    await expect(page.getByTestId('stats-overview')).toHaveAttribute('data-span', '1d', { timeout: 60_000 })
    // the charts are ON the face (2026-11-02, the unfold slice: they were behind the World money row); each mini is a
    // press target and the large chart is closed until it is pressed
    await expect(page.getByTestId('stats-big-chart')).toHaveCount(0)

    // the page under the tray does not move when it opens
    // the tapped chart's place against the first holder cell, both in the tab's own scroll box: a press may scroll that box, it may not re-flow it
    const gap = () => page.evaluate(() => document.querySelector('[data-testid="stats-chart-tap"]')!.getBoundingClientRect().top - document.querySelector('[data-testid="stats-holder"]')!.getBoundingClientRect().top)
    const before = await gap()
    await page.getByTestId('stats-chart-tap').first().click()
    const big = page.getByTestId('stats-big-chart')
    await expect(big).toBeVisible()
    await expect(big.getByTestId('span-picker')).toBeVisible()
    await expect(big.locator('[role="img"]')).toHaveCount(1)
    expect(await gap()).toBe(before)

    // a span press asks the server for that span
    for (const [word, span] of [['1 week', '1w'], ['All', 'all'], ['1 day', '1d']] as const) {
      await big.getByTestId('span-picker').getByRole('tab', { name: word, exact: true }).click()
      await expect(page.getByTestId('stats-overview')).toHaveAttribute('data-span', span, { timeout: 30_000 })
      await expect(big).toBeVisible()
    }
  })
}
