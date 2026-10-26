import { test, expect } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE MAP ON TOP, AND AN ORDER PRESSED SHOWS ITS ROUTE AND ESTIMATE (owner row 217, 2026-10-26: *"on command,
// trade, map should be at top. when i press my order, i should be able to see the route, time, money, profit all on
// estimate below the map + map"*). A new company at Lisbon, in the in-tab (PGlite) world, at the owner's desktop
// (1440×900) and the phone (390×844):
//   Trade → the map is the first thing on the page → Here: buy a good → Cargo → that good → a sell row → Go →
//   press the queued SELL → its course is drawn on the map and the estimate stands under it (Route, Time, Profit
//   with figures) → press it again → the estimate is gone.
// Nothing here asserts a price; presence, order on the page and "a figure, not a dash" are the claim.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const SIZES = [
  { width: 1440, height: 900 },
  { width: 390, height: 844 },
] as const

for (const size of SIZES) {
  test.describe(`order estimate at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size })

    test('the map is on top; a pressed order shows its route and estimate', async ({ page, request, baseURL }) => {
      test.setTimeout(480_000)
      test.skip(
        !(await reachable(request, baseURL ?? '')),
        `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
      )
      await page.goto('command')
      await ready(page)
      await page.getByRole('tab', { name: 'Trade', exact: true }).click()
      const face = page.getByTestId('desk-plans')
      await expect(face).toBeVisible()

      // THE MAP ON TOP: above Start and above the centre pane's content
      const map = face.getByTestId('trade-map')
      await expect(map.getByTestId('small-chart')).toBeVisible()
      const y = (id: string) => face.getByTestId(id).first().evaluate((e) => e.getBoundingClientRect().top)
      expect(await y('trade-map'), 'the map is not above the market').toBeLessThan(await y('here-market').catch(() => Infinity))
      if (size.width < 1024) expect(await y('trade-map'), 'the map is not the first thing on a phone').toBeLessThan(await y('trade-start-here'))

      // buy a good here, then plan its sale from Cargo and Go
      await face.getByTestId('trade-start-here').click()
      const buyable = face.locator('button[data-testid="here-buy"]:enabled')
      await expect(buyable.first()).toBeVisible({ timeout: 120_000 })
      const code = await buyable.first().locator('xpath=ancestor::*[@data-testid="here-row"]').getAttribute('data-good')
      await buyable.first().click()
      const tray = page.getByTestId('trade-tray')
      await expect(tray.getByTestId('trade-tray-send')).toBeEnabled({ timeout: 60_000 })
      await tray.getByTestId('trade-tray-send').click()
      await expect(tray).toHaveCount(0, { timeout: 60_000 })
      await face.getByTestId('trade-start-hold').click()
      await face.locator(`[data-testid="trade-good"][data-good="${code}"]`).click()
      const rows = face.getByTestId('trade-sell-row')
      await expect(rows.first()).toBeVisible({ timeout: 120_000 })
      await rows.first().click()
      // the plan is drawn on THE map on top (the card has no chart of its own now)
      await expect(map.getByTestId('map-plan-course').first()).toBeAttached({ timeout: 60_000 })
      await expect(face.getByTestId('trade-card').getByTestId('small-chart')).toHaveCount(0)
      const go = face.getByTestId('plan-queue')
      await expect(go).toHaveText('Go', { timeout: 60_000 })
      await go.click()
      await expect(face.getByTestId('trade-card')).toHaveCount(0, { timeout: 60_000 })

      // press the queued SELL: its route on the map, its estimate under it
      const sell = page.getByTestId('queue-pick').last()
      await expect(sell).toBeVisible({ timeout: 30_000 })
      await sell.click()
      await expect(sell).toHaveAttribute('aria-pressed', 'true')
      const est = map.getByTestId('order-estimate')
      await expect(est).toBeVisible()
      await expect(est).toBeInViewport()
      await expect(map.getByTestId('map-plan-course').first()).toBeAttached({ timeout: 30_000 })
      await expect(est.getByTestId('est-route-stops')).toContainText('→')
      await expect(est.getByTestId('est-time')).toContainText(/\d/, { timeout: 60_000 })
      await expect(est.getByTestId('est-profit')).toContainText(/\d/, { timeout: 60_000 })
      for (const id of ['est-supplies', 'est-wages', 'est-tax', 'est-fee', 'est-cost']) await expect(est.getByTestId(id)).toBeVisible()
      // the estimate stands UNDER the map
      const chartBox = await map.getByTestId('small-chart').boundingBox()
      const estBox = await est.boundingBox()
      expect(estBox!.y).toBeGreaterThanOrEqual(chartBox!.y + chartBox!.height - 1)
      // nothing cut off: the estimate fits the page's width
      expect(estBox!.x + estBox!.width).toBeLessThanOrEqual(size.width + 0.5)
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)

      // pressed again: cleared
      await sell.click()
      await expect(est).toHaveCount(0)
      // and Close clears it too
      await sell.click()
      await expect(est).toBeVisible()
      await est.getByTestId('order-estimate-close').click()
      await expect(map.getByTestId('order-estimate')).toHaveCount(0)
    })
  })
}
