import { test, expect } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { pressCity } from './deskMap.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// BUY AND SELL — ONE MIRRORED GAME SCREEN (owner row 229, 2026-10-26: *"I want to click on cities, see the selling
// prices when i click on the city, not give a bunch of list since it will be too easy. for buying and selling i want
// both to be... similar mechanism. similar screen, buttons to press etc. make it like a true game."*). A new company
// docked at Lisbon, in the in-tab (PGlite) world, at the owner's desktop (1440×900) and the phone (390×844):
//   Buy → the map with every city → press Lisbon on it → its goods as CARDS, each priced with a line → press a good:
//   THE panel (the chart, the units, the money, ONE button "Buy") → Buy 1 → Sell → press Lisbon → the card shows
//   "Aboard 1" with its line → Sell 1 → no cargo. And a city she is not at offers "Sail & sell", the same button.
// No cross-city list stands on either face. Nothing here asserts a price; "a figure, not a dash" is the claim.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

test.use({ locale: 'en-US' })

const SIZES = [
  { width: 1440, height: 900 },
  { width: 390, height: 844 },
] as const

for (const size of SIZES) {
  test.describe(`Buy and Sell at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size })

    test('press a city, its cards, a good: Buy 1, then Sell it on the same screen', async ({ page, request, baseURL }) => {
      test.setTimeout(480_000)
      test.skip(
        !(await reachable(request, baseURL ?? '')),
        `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
      )
      await page.goto('command')
      await ready(page)
      const faces = page.getByRole('tablist', { name: 'Desk faces' })
      await faces.getByRole('tab', { name: 'Buy', exact: true }).click()
      const face = page.getByTestId('desk-buy')
      await expect(face).toBeVisible()

      // THE SHIP under the orders (row 233): cargo, crew, stores — from the readings FLEETS already draws
      const ship = face.getByTestId('buy-ship')
      await expect(ship).toBeVisible()
      await expect(ship.getByTestId('cargo-bar')).toBeVisible()
      await expect(ship.getByTestId('buy-ship-crew')).toContainText(/\d+\/\d+/)
      await expect(ship.getByTestId('buy-ship-stores')).toContainText(/\d/)

      // THE MAP ON TOP, every city on it; no cross-city list on the face
      const map = face.getByTestId('trade-map')
      await expect(map.getByTestId('small-chart')).toBeVisible()
      expect(await map.locator('[data-port-code]').count(), 'the map draws the cities').toBeGreaterThan(20)
      await expect(page.getByTestId('trade-sell-list')).toHaveCount(0)
      await expect(page.getByTestId('trade-card')).toHaveCount(0)

      // Lisbon pressed on the map: its goods as cards, each priced, with its line
      await pressCity(page, map, 'LIS')
      const goods = face.getByTestId('city-goods')
      await expect(goods).toHaveAttribute('data-city', 'LIS')
      await expect(goods).toHaveAttribute('data-docked', 'true')
      const cards = goods.getByTestId('city-good')
      await expect(cards.first()).toBeVisible({ timeout: 120_000 })
      expect(await cards.count()).toBeGreaterThan(2)
      await expect(cards.first().getByTestId('city-good-price')).toHaveText(/\d/)
      await expect(cards.first().getByTestId('city-good-spark')).toBeVisible()
      await expect(cards.first().getByTestId('city-good-aboard')).toHaveText(/Aboard \d/)
      // the chip strip names cities, never prices
      await expect(goods.getByTestId('city-chip').first()).toBeVisible()
      expect(await goods.getByTestId('city-chips').innerText()).not.toMatch(/\d/)

      // a good pressed: THE panel — the chart, the units with Max, the money, ONE button "Buy"
      const card = cards.first()
      const code = await card.getAttribute('data-good')
      await card.click()
      await expect(card).toHaveAttribute('aria-pressed', 'true')
      const panel = page.getByTestId('good-detail')
      await expect(panel).toBeVisible()
      await expect(panel).toHaveAttribute('data-good', code!)
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
      await expect(goods.locator(`[data-testid="city-good"][data-good="${code}"]`).getByTestId('city-good-aboard')).toHaveText('Aboard 1', { timeout: 60_000 })

      // SELL: the same screen; press Lisbon; the card shows Aboard 1 with its line, at Lisbon's price
      await faces.getByRole('tab', { name: 'Sell', exact: true }).click()
      const sellFace = page.getByTestId('desk-sell')
      await expect(sellFace).toBeVisible()
      const sellMap = sellFace.getByTestId('trade-map')
      await pressCity(page, sellMap, 'LIS')
      const cargo = sellFace.getByTestId('city-goods')
      await expect(cargo).toHaveAttribute('data-city', 'LIS')
      const mine = cargo.locator(`[data-testid="city-good"][data-good="${code}"]`)
      await expect(mine).toBeVisible({ timeout: 60_000 })
      await expect(mine.getByTestId('city-good-aboard')).toHaveText('Aboard 1')
      await expect(mine.getByTestId('city-good-price')).toHaveText(/\d/, { timeout: 60_000 })
      await expect(mine.getByTestId('city-good-spark')).toBeVisible()
      await expect(page.getByTestId('trade-sell-list')).toHaveCount(0)

      // a city she is not at: the same button says "Sail & sell"
      await pressCity(page, sellMap, 'AMS')
      await expect(cargo).toHaveAttribute('data-city', 'AMS')
      await expect(cargo).toHaveAttribute('data-docked', 'false')
      const far = cargo.locator(`[data-testid="city-good"][data-good="${code}"]`)
      await expect(far.getByTestId('city-good-price')).toHaveText(/\d|No buyer/, { timeout: 60_000 })
      if (/\d/.test(await far.getByTestId('city-good-price').innerText())) {
        await far.click()
        await expect(page.getByTestId('good-detail')).toHaveAttribute('data-city', 'AMS')
        await expect(page.getByTestId('trade-act')).toHaveAttribute('data-act', 'sail-sell')
        await expect(page.getByTestId('trade-act')).toHaveText(/Sail & sell|Too far|Cargo full|Shut/, { timeout: 60_000 })
        await expect(page.getByTestId('plan-estimate')).toBeVisible()
        await expect(page.getByTestId('plan-days')).toBeVisible()
        // closed by its own ✕: on a phone the sheet covers the card (row 231: every near city now bids, so this runs there too)
        await page.getByTestId('good-detail').getByTestId('tray-close').click()
        await expect(page.getByTestId('good-detail')).toHaveCount(0)
      }

      // back at Lisbon: Sell 1 here
      await pressCity(page, sellMap, 'LIS')
      await expect(cargo).toHaveAttribute('data-city', 'LIS')
      await mine.click()
      const sellPanel = page.getByTestId('good-detail')
      await expect(sellPanel).toHaveAttribute('data-side', 'sell')
      await expect(sellPanel.getByTestId('span-picker')).toBeVisible()
      await expect(act).toHaveText('Sell')
      await expect(sellPanel.getByTestId('stepper-figure')).toHaveValue('1')
      await expect(act).toBeEnabled({ timeout: 60_000 })
      await act.click()
      await expect(page.getByTestId('trade-toast')).toContainText(/^Sold 1 /, { timeout: 60_000 })
      await expect(cargo.getByTestId('city-goods-none')).toBeVisible({ timeout: 60_000 })

      // no sideways scroll
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
    })
  })
}
