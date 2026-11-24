import { test, expect } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { openFleetSheet } from './desk.fixture'
import { buyHere, closeTradeMap, findCarry, openTradeMap, sailAndSell } from './deskMap.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE MAP AND AN ORDER'S ESTIMATE — a POP-UP PAGE (owner, 2026-10-31: compact screens; a press
// opens a new page). Since H3 `desk-into-hq` (2026-11-24) the map is one row of her sheet over HQ
// (her HQ row's press); the queued order is selected in that sheet's Orders; the map page draws its
// course and estimate. A second press on the order clears it, and a third restores it. Both sizes.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const SIZES = [
  { width: 1440, height: 900 },
  { width: 390, height: 844 },
] as const

for (const size of SIZES) {
  test.describe(`order page at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size })

    test('the map is a summary page; a pressed order shows its route and estimate', async ({ page, request, baseURL }) => {
      test.setTimeout(480_000)
      test.skip(
        !(await reachable(request, baseURL ?? '')),
        `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
      )
      await page.goto('city')
      await ready(page)

      // THE MAP IS ONE SUMMARY ROW OF HER SHEET, OPENING ITS PAGE
      const sheet = await openFleetSheet(page)
      await expect(sheet.getByTestId('hq-sheet-fleet-map')).toBeVisible()
      await openTradeMap(page)
      await expect(page.getByTestId('trade-map').getByTestId('small-chart')).toBeVisible()
      await closeTradeMap(page)

      const { code, city } = await findCarry(page)
      await buyHere(page, code)
      await sailAndSell(page, code, city)

      // SELECT THE QUEUED SELL IN HER SHEET'S ORDERS (the pick is the sheet's own: it stays open from here)
      await openFleetSheet(page)
      const sell = page.getByTestId('queue-pick').last()
      await expect(sell).toBeVisible({ timeout: 30_000 })
      await sell.click()
      await expect(sell).toHaveAttribute('aria-pressed', 'true')

      /** THE MAP PAGE: the course and the estimate, under the chart, inside its own scroll. */
      const assertEstimate = async () => {
        await openTradeMap(page)
        const map = page.getByTestId('trade-map')
        const est = map.getByTestId('order-estimate')
        await expect(est).toBeVisible()
        await est.evaluate((e) => e.scrollIntoView({ block: 'nearest' }))
        await expect(est).toBeInViewport()
        await expect(map.getByTestId('map-plan-course').first()).toBeAttached({ timeout: 30_000 })
        await expect(est.getByTestId('est-route-stops')).toContainText('→')
        await expect(est.getByTestId('est-time')).toContainText(/\d/, { timeout: 60_000 })
        await expect(est.getByTestId('est-profit')).toBeVisible()
        for (const id of ['est-supplies', 'est-wages', 'est-tax', 'est-fee', 'est-dock', 'est-cost']) await expect(est.getByTestId(id)).toBeVisible()
        const chartBox = await map.getByTestId('small-chart').boundingBox()
        const estBox = await est.boundingBox()
        expect(estBox!.y).toBeGreaterThanOrEqual(chartBox!.y + chartBox!.height - 1)
        expect(estBox!.x + estBox!.width).toBeLessThanOrEqual(size.width + 0.5)
        expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
      }
      await assertEstimate()
      await closeTradeMap(page, { sheet: false })

      // PRESS THE ORDER AGAIN: cleared
      await page.getByTestId('queue-pick').last().click()
      await openTradeMap(page)
      await expect(page.getByTestId('trade-map').getByTestId('order-estimate')).toHaveCount(0)
      await closeTradeMap(page, { sheet: false })

      // PRESS IT AGAIN: the same estimate stands
      await page.getByTestId('queue-pick').last().click()
      await assertEstimate()
      await closeTradeMap(page)
    })
  })
}
