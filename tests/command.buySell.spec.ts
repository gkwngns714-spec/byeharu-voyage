import { test, expect } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// TRADE — ONE DOCKED SCREEN, BOTH SIDES (owner 2026-10-30: *"removing the map, just have combined buy
// and sell tab with trade goods when docked"*). A new company docked at Lisbon, at the desktop (1440×900)
// and the phone (390×844):
//   Trade → the docked city's goods in ONE list, each card carrying BOTH prices (Buy = the city's ask,
//   Sell = its bid) and its day line → press Buy on a good: THE panel (the chart, the units, the money,
//   ONE button "Buy") → Buy 1 → press Sell on that same card: the panel says Sell → Sell 1 → no cargo.
// The SMALL map stands at the bottom of the face, in a fold (owner 2026-10-30); no cross-city list stands
// anywhere — trade happens where she lies, and the map is there to glance at, not to work from. Nothing
// here asserts a price; "a figure, not a dash" is the claim.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

test.use({ locale: 'en-US' })

const SIZES = [
  { width: 1440, height: 900 },
  { width: 390, height: 844 },
] as const

for (const size of SIZES) {
  test.describe(`Trade at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size })

    test('the docked city\'s goods, both prices on one card: Buy 1, then Sell it back', async ({ page, request, baseURL }) => {
      test.setTimeout(480_000)
      test.skip(
        !(await reachable(request, baseURL ?? '')),
        `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
      )
      await page.goto('command')
      await ready(page)
      const faces = page.getByRole('tablist', { name: 'Desk faces' })
      await faces.getByRole('tab', { name: 'Trade', exact: true }).click()
      const face = page.getByTestId('desk-trade')
      await expect(face).toBeVisible()

      // THE SHIP under the orders (row 233): cargo, crew, stores — from the readings FLEETS already draws
      const ship = face.getByTestId('buy-ship')
      await expect(ship).toBeVisible()
      await expect(ship.getByTestId('buy-ship-crew')).toContainText(/\d+\/\d+/)
      await expect(ship.getByTestId('buy-ship-stores')).toContainText(/\d/)

      // THE BOARD: the docked city's goods, one card per good, both prices; no map, no cross-city list
      const board = face.getByTestId('trade-board')
      await expect(board).toBeVisible()
      const cards = board.getByTestId('trade-good')
      await expect(cards.first()).toBeVisible({ timeout: 120_000 })
      expect(await cards.count()).toBeGreaterThan(2)
      await expect(cards.first().getByTestId('trade-good-buy')).toHaveText(/\d/)
      await expect(cards.first().getByTestId('trade-good-sell')).toHaveText(/\d|No buyer/)
      await expect(cards.first().getByTestId('trade-good-spark')).toBeVisible()
      await expect(cards.first().getByTestId('trade-good-aboard')).toHaveText(/Aboard \d/)
      // the small map is there, at the bottom, in a fold (owner 2026-10-30); no cross-city list
      await expect(page.getByTestId('trade-map')).toHaveCount(1)
      await expect(face.getByTestId('trade-map-fold')).toHaveAttribute('data-open', 'true')
      await expect(page.getByTestId('trade-sell-list')).toHaveCount(0)

      // BUY: a good's Buy button opens THE panel — the chart, the units with Max, the money, ONE button "Buy"
      const first = cards.first()
      const code = (await first.getAttribute('data-good'))!
      await first.getByTestId('trade-buy').click()
      const panel = page.getByTestId('good-detail')
      await expect(panel).toBeVisible()
      await expect(panel).toHaveAttribute('data-good', code)
      await expect(panel).toHaveAttribute('data-side', 'buy')
      await expect(panel.getByTestId('good-detail-price')).toContainText(/\d/)
      await expect(panel.getByTestId('span-picker')).toBeVisible()
      await expect(panel.getByTestId('price-chart').or(panel.getByTestId('trend-empty'))).toBeVisible({ timeout: 60_000 })
      const act = page.getByTestId('trade-act')
      await expect(act).toHaveText('Buy')
      await expect(act).toHaveAttribute('data-act', 'buy')
      await expect(panel.getByRole('button', { name: 'Max', exact: true })).toBeVisible({ timeout: 60_000 })
      await panel.getByTestId('stepper-figure').fill('1')
      await panel.getByTestId('stepper-figure').press('Enter')
      await expect(panel.getByTestId('stepper-figure')).toHaveValue('1')
      await expect(panel.getByTestId('good-detail-total')).toContainText(/\d/, { timeout: 60_000 })
      await expect(act).toBeEnabled({ timeout: 60_000 })
      await act.click()
      await expect(page.getByTestId('trade-toast')).toContainText(/^Bought 1 /, { timeout: 60_000 })
      await expect(panel).toHaveCount(0)
      await expect(
        board.locator(`[data-testid="trade-good"][data-good="${code}"]`).getByTestId('trade-good-aboard'),
      ).toHaveText('Aboard 1', { timeout: 60_000 })

      // SELL: the same card's Sell button; the panel says Sell, and selling leaves no cargo of it
      const mine = board.locator(`[data-testid="trade-good"][data-good="${code}"]`)
      await mine.getByTestId('trade-sell').click()
      const sellPanel = page.getByTestId('good-detail')
      await expect(sellPanel).toBeVisible()
      await expect(sellPanel).toHaveAttribute('data-side', 'sell')
      await expect(sellPanel.getByTestId('stepper-figure')).toHaveValue('1')
      await expect(act).toHaveText('Sell')
      await expect(act).toBeEnabled({ timeout: 60_000 })
      await act.click()
      await expect(page.getByTestId('trade-toast')).toContainText(/^Sold 1 /, { timeout: 60_000 })
      await expect(
        board.locator(`[data-testid="trade-good"][data-good="${code}"]`).getByTestId('trade-good-aboard'),
      ).toHaveText('Aboard 0', { timeout: 60_000 })

      // no sideways scroll
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
    })
  })
}
