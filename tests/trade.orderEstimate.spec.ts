import { test, expect } from '@playwright/test'
import { closeDetail, openDetail, ready, reachable } from './appReady.fixture'
import { buyHere, closeTradeMap, findCarry, openTradeMap, sailAndSell } from './deskMap.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE MAP AND AN ORDER'S ESTIMATE — now a POP-UP PAGE (owner, 2026-10-31: compact screens; a press
// opens a new page). The map is one summary row on the compact Trade face; the queued order is
// selected inside the Orders page; the map page draws its course and estimate. A second press on
// the order clears it, and a third restores it. Both sizes.
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
      await page.goto('command')
      await ready(page)
      const face = page.getByTestId('desk-trade')
      await expect(face).toBeVisible()

      // THE MAP IS ONE SUMMARY ROW, OPENING ITS PAGE
      await expect(face.getByTestId('trade-map-open')).toBeVisible()
      await openTradeMap(face)
      await expect(face.getByTestId('trade-map').getByTestId('small-chart')).toBeVisible()
      await closeTradeMap(face)

      const { code, city } = await findCarry(page)
      await buyHere(page, code)
      await sailAndSell(page, code, city)

      // SELECT THE QUEUED SELL ON ITS PAGE
      await openDetail(page, 'command-queue')
      const sell = page.getByTestId('queue-pick').last()
      await expect(sell).toBeVisible({ timeout: 30_000 })
      await sell.click()
      await expect(sell).toHaveAttribute('aria-pressed', 'true')
      await closeDetail(page)

      /** THE MAP PAGE: the course and the estimate, under the chart, inside its own scroll. */
      const assertEstimate = async () => {
        await openTradeMap(face)
        const map = face.getByTestId('trade-map')
        const est = map.getByTestId('order-estimate')
        await expect(est).toBeVisible()
        await est.evaluate((e) => e.scrollIntoView({ block: 'nearest' }))
        await expect(est).toBeInViewport()
        await expect(map.getByTestId('map-plan-course').first()).toBeAttached({ timeout: 30_000 })
        await expect(est.getByTestId('est-route-stops')).toContainText('→')
        await expect(est.getByTestId('est-time')).toContainText(/\d/, { timeout: 60_000 })
        await expect(est.getByTestId('est-profit')).toBeVisible()
        for (const id of ['est-supplies', 'est-wages', 'est-tax', 'est-fee', 'est-cost']) await expect(est.getByTestId(id)).toBeVisible()
        const chartBox = await map.getByTestId('small-chart').boundingBox()
        const estBox = await est.boundingBox()
        expect(estBox!.y).toBeGreaterThanOrEqual(chartBox!.y + chartBox!.height - 1)
        expect(estBox!.x + estBox!.width).toBeLessThanOrEqual(size.width + 0.5)
        expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
      }
      await assertEstimate()
      await closeTradeMap(face)

      // PRESS THE ORDER AGAIN: cleared
      await openDetail(page, 'command-queue')
      await page.getByTestId('queue-pick').last().click()
      await closeDetail(page)
      await openTradeMap(face)
      await expect(face.getByTestId('trade-map').getByTestId('order-estimate')).toHaveCount(0)
      await closeTradeMap(face)

      // PRESS IT AGAIN: the same estimate stands
      await openDetail(page, 'command-queue')
      await page.getByTestId('queue-pick').last().click()
      await closeDetail(page)
      await assertEstimate()
      await closeTradeMap(face)
    })
  })
}
