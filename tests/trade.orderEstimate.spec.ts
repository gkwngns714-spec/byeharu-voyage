import { test, expect } from '@playwright/test'
import { openFold, ready, reachable } from './appReady.fixture'
import { buyHere, findCarry, openTradeMap, sailAndSell } from './deskMap.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE SMALL MAP AT THE BOTTOM, AND AN ORDER PRESSED SHOWS ITS ROUTE AND ESTIMATE (owner row 217, 2026-10-26: *"on
// command, trade, map should be at top. when i press my order, i should be able to see the route, time, money, profit
// all on estimate below the map + map"*; the map is SMALL, at the BOTTOM, FOLDABLE since owner 2026-10-30, and the
// face is ONE screen). A new company at Lisbon, in the in-tab (PGlite) world, at the owner's desktop (1440×900) and
// the phone (390×844):
//   Trade → the small map stands at the BOTTOM, under the goods board, in a fold → buy a good here → a city she is
//   not at (the chip strip) → Sail & sell (owner row 229) → press the queued SELL → its course is drawn on the map
//   and the estimate stands under it (Route, Time, Profit with figures) → press it again → the estimate is gone →
//   press it again → the same estimate stands.
// Nothing here asserts a price; presence, order on the page and "a figure, not a dash" are the claim.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const SIZES = [
  { width: 1440, height: 900 },
  { width: 390, height: 844 },
] as const

for (const size of SIZES) {
  test.describe(`order estimate at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size })

    test('the small map is at the bottom in a fold; a pressed order shows its route and estimate', async ({ page, request, baseURL }) => {
      test.setTimeout(480_000)
      test.skip(
        !(await reachable(request, baseURL ?? '')),
        `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
      )
      await page.goto('command')
      await ready(page)
      const face = page.getByTestId('desk-trade')
      await expect(face).toBeVisible()

      // THE SMALL MAP AT THE BOTTOM: below the goods board, in a fold that is open by default
      const fold = face.getByTestId('trade-map-fold')
      await expect(fold).toBeVisible()
      // on a phone the map starts folded (the one-page law); the press opens it, as a player does
      await openTradeMap(face)
      await expect(fold).toHaveAttribute('data-open', 'true')
      await expect(face.getByTestId('trade-board').first()).toBeVisible()
      await expect(face.getByTestId('trade-map').getByTestId('small-chart')).toBeVisible()
      const y = (id: string) => face.getByTestId(id).first().evaluate((e) => e.getBoundingClientRect().top)
      expect(await y('trade-board'), 'the map is not below the board').toBeLessThan(await y('trade-map'))

      // buy a good here, then sail to sell it at a city that deals in it (found by pressing cities, owner row 229)
      const { code, city } = await findCarry(page)
      await buyHere(page, code)
      await sailAndSell(page, code, city)
      const map = face.getByTestId('trade-map')

      // press the queued SELL: its route on the map, its estimate under it (the Orders fold is
      // closed at rest on a phone; a player opens it to see the queue)
      await openFold(page, 'command-queue')
      const sell = page.getByTestId('queue-pick').last()
      await expect(sell).toBeVisible({ timeout: 30_000 })
      await sell.click()
      await expect(sell).toHaveAttribute('aria-pressed', 'true')
      const est = map.getByTestId('order-estimate')
      await expect(est).toBeVisible()
      await est.evaluate((e) => e.scrollIntoView({ block: 'nearest' }))
      await expect(est).toBeInViewport()
      await expect(map.getByTestId('map-plan-course').first()).toBeAttached({ timeout: 30_000 })
      await expect(est.getByTestId('est-route-stops')).toContainText('→')
      await expect(est.getByTestId('est-time')).toContainText(/\d/, { timeout: 60_000 })
      // the profit is served only for the board's dearest cities (good_board_quoted, 0171); the city she pressed may not
      // be one of them (owner row 229: no ranking is shown), so its row stands, with a figure or a dash
      await expect(est.getByTestId('est-profit')).toBeVisible()
      for (const id of ['est-supplies', 'est-wages', 'est-tax', 'est-fee', 'est-cost']) await expect(est.getByTestId(id)).toBeVisible()
      // the estimate stands UNDER the map's chart
      const chartBox = await map.getByTestId('small-chart').boundingBox()
      const estBox = await est.boundingBox()
      expect(estBox!.y).toBeGreaterThanOrEqual(chartBox!.y + chartBox!.height - 1)
      // nothing cut off: the estimate fits the page's width
      expect(estBox!.x + estBox!.width).toBeLessThanOrEqual(size.width + 0.5)
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)

      // pressed again: cleared
      await sell.click()
      await expect(est).toHaveCount(0)
      // pressed again: the same estimate stands
      await sell.click()
      await expect(map.getByTestId('order-estimate')).toBeVisible()
      await expect(map.getByTestId('est-route-stops')).toContainText('→')
      // and Close clears it too
      await map.getByTestId('order-estimate-close').click()
      await expect(map.getByTestId('order-estimate')).toHaveCount(0)
    })
  })
}
