import { test, expect } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { pressCity } from './deskMap.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// BUY AND SELL, WITH THE MAP, THE CITIES, THE PRICES AND THE CHARTS (owner row 218, 2026-10-26: *"in command, there
// is market, and trade. i want to have buy and sell tab instead of those. with charts, map and all … in mini map in
// command, show cities, when pressed upon, show trade goods with prices, and charts."*). A new company docked at
// Lisbon, in the in-tab (PGlite) world, at the owner's desktop (1440×900) and the phone (390×844):
//   Buy → the mini map with every city → press Amsterdam on it: its goods, "Not docked" → press Lisbon: its goods
//   with prices → press a good: its chart → Buy here, 1 unit, through THE trade tray → Sell → the cargo shows it at
//   Lisbon's price → Sell it here → the cargo is empty.
// Nothing here asserts a price; "a figure, not a dash" is the claim.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const SIZES = [
  { width: 1440, height: 900 },
  { width: 390, height: 844 },
] as const

for (const size of SIZES) {
  test.describe(`Buy and Sell at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size })

    test('press a city on the map, its goods and a chart; Buy 1, then Sell it', async ({ page, request, baseURL }) => {
      test.setTimeout(480_000)
      test.skip(
        !(await reachable(request, baseURL ?? '')),
        `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
      )
      await page.goto('command')
      await ready(page)
      const faces = page.getByRole('tablist', { name: 'Desk faces' })
      // the two faces stand where Markets and Trade stood
      await expect(faces.getByRole('tab', { name: 'Markets', exact: true })).toHaveCount(0)
      await faces.getByRole('tab', { name: 'Buy', exact: true }).click()
      const face = page.getByTestId('desk-buy')
      await expect(face).toBeVisible()

      // THE MAP ON TOP, every city on it; the city in hand is where she lies
      const map = face.getByTestId('trade-map')
      await expect(map.getByTestId('small-chart')).toBeVisible()
      await expect(map).toHaveAttribute('data-cities', '*')
      expect(await map.locator('[data-port-code]').count(), 'the map draws the cities').toBeGreaterThan(20)
      const goods = face.getByTestId('city-goods')
      await expect(goods).toHaveAttribute('data-city', 'LIS')
      await expect(goods).toHaveAttribute('data-docked', 'true')
      // nothing of a trip until one is planned (the trade card stands only on Plan trip)
      await expect(face.getByTestId('trade-card')).toHaveCount(0)

      // a city pressed on the map: its goods, not docked there
      await pressCity(page, map, 'AMS')
      await expect(goods).toHaveAttribute('data-city', 'AMS')
      await expect(goods).toHaveAttribute('data-docked', 'false')
      await expect(goods.getByTestId('city-goods-not-docked')).toBeVisible()
      await expect(goods.getByTestId('city-good').first()).toBeVisible({ timeout: 120_000 })

      // Lisbon pressed: its goods with prices
      await pressCity(page, map, 'LIS')
      await expect(goods).toHaveAttribute('data-city', 'LIS')
      await expect(goods).toHaveAttribute('data-docked', 'true')
      const rows = goods.getByTestId('city-good')
      await expect(rows.first()).toBeVisible({ timeout: 120_000 })
      expect(await rows.count()).toBeGreaterThan(2)
      await expect(rows.first().getByTestId('city-good-price')).toHaveText(/\d/)
      const clipped = await goods.evaluate((g) =>
        [...g.querySelectorAll<HTMLElement>('[data-testid="city-good"] [data-col]')].filter((e) => e.scrollWidth > e.clientWidth + 1).length,
      )
      expect(clipped, 'a figure is cut off in its cell').toBe(0)

      // a good pressed: its page — the price, the chart (or "No data yet" on a record too young), who bought what
      const row = rows.first()
      const code = await row.getAttribute('data-good')
      await row.click()
      const detail = face.getByTestId('good-detail')
      await expect(detail).toBeVisible()
      await expect(detail).toHaveAttribute('data-good', code!)
      await expect(detail.getByTestId('good-detail-price')).toContainText(/\d/)
      await expect(detail.getByTestId('trend-row')).toBeVisible()
      await expect(detail.getByTestId('price-chart').or(detail.getByTestId('trend-empty'))).toBeVisible({ timeout: 60_000 })
      await expect(detail.getByTestId('city-good-trades')).toBeVisible({ timeout: 60_000 })

      // Buy 1 here: THE trade tray, one unit, its one button
      await detail.getByTestId('good-buy').click()
      const tray = page.getByTestId('trade-tray')
      await expect(tray).toBeVisible()
      await expect(tray.getByTestId('trade-tray-max')).toBeVisible({ timeout: 60_000 })
      await tray.getByTestId('stepper-figure').fill('1')
      await tray.getByTestId('stepper-figure').press('Enter')
      await expect(tray.getByTestId('stepper-figure')).toHaveValue('1')
      const send = tray.getByTestId('trade-tray-send')
      await expect(send).toBeEnabled({ timeout: 60_000 })
      await send.click()
      await expect(tray).toHaveCount(0, { timeout: 60_000 })
      await expect(goods.locator(`[data-testid="city-good"][data-good="${code}"] [data-col]`).first()).toHaveText('1', { timeout: 60_000 })

      // SELL: her cargo at Lisbon's price; sell it here
      await faces.getByRole('tab', { name: 'Sell', exact: true }).click()
      const sellFace = page.getByTestId('desk-sell')
      await expect(sellFace).toBeVisible()
      const cargo = sellFace.getByTestId('city-goods')
      await expect(cargo).toHaveAttribute('data-city', 'LIS')
      const mine = cargo.locator(`[data-testid="city-good"][data-good="${code}"]`)
      await expect(mine).toBeVisible({ timeout: 60_000 })
      await expect(mine.locator('[data-col]').first()).toHaveText('1')
      await expect(mine.getByTestId('city-good-price')).toHaveText(/\d/, { timeout: 60_000 })
      // the good pressed on Buy is still in hand on Sell (one city, one good, both faces)
      await expect(mine).toHaveAttribute('aria-pressed', 'true')
      const sellDetail = sellFace.getByTestId('good-detail')
      await expect(sellDetail).toHaveAttribute('data-side', 'sell')
      await sellDetail.getByTestId('good-sell').click()
      await expect(tray).toBeVisible()
      await expect(tray.getByTestId('stepper-figure')).toHaveValue('1')
      await expect(send).toBeEnabled({ timeout: 60_000 })
      await send.click()
      await expect(tray).toHaveCount(0, { timeout: 60_000 })
      await expect(cargo.getByTestId('city-goods-none')).toBeVisible({ timeout: 60_000 })

      // no sideways scroll
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
    })
  })
}
