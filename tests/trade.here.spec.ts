import { test, expect } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// TRADE › HERE IS THE PORT'S MARKET (owner row 210, 2026-10-26: *"it should show my cargo, sell and buy prices
// at the center. thats it right? why is there days, supplies?"*). A new company docked at Lisbon, at the owner's
// desktop (1440×900) and the phone (390×844):
//   Trade → Here → the centre lists the goods with Cargo · Buy · Sell → Buy 1 through THE trade tray → the row's
//   cargo reads it → Sell it back → the cargo is gone again
// and nothing on Here is the trip's: no days, no supplies, no sell list, no card. Nothing here asserts a price.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const SIZES = [
  { width: 1440, height: 900 },
  { width: 390, height: 844 },
] as const

for (const size of SIZES) {
  test.describe(`Here is the market at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size })

    test('the goods with both prices; Buy 1 here, then Sell it back', async ({ page, request, baseURL }) => {
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
      await face.getByTestId('trade-start-here').click()

      // the market, docked: a head with the three columns, rows with a buy and a sell price each
      const market = face.getByTestId('here-market')
      await expect(market).toHaveAttribute('data-docked', 'true')
      await expect(market.getByTestId('here-head')).toContainText('Cargo')
      await expect(market.getByTestId('here-head')).toContainText('Buy')
      await expect(market.getByTestId('here-head')).toContainText('Sell')
      const rows = market.getByTestId('here-row')
      await expect(rows.first()).toBeVisible({ timeout: 120_000 })
      expect(await rows.count()).toBeGreaterThan(2)
      // nothing of the trip on Here
      for (const id of ['trade-card', 'trade-sell-list', 'plan-supplies', 'here-not-docked']) await expect(face.getByTestId(id)).toHaveCount(0)

      // the first good this port sells: both its prices are figures, Buy is a press, Sell is shut (none aboard)
      const row = rows.filter({ has: page.locator('button[data-testid="here-buy"]:enabled') }).first()
      const code = await row.getAttribute('data-good')
      const buy = row.getByTestId('here-buy')
      const sell = row.getByTestId('here-sell')
      await expect(buy).toHaveText(/\d/)
      await expect(sell).toHaveText(/\d/)
      await expect(sell).toBeDisabled()

      // Buy 1: THE trade tray (the quay's), one unit, its one button
      await buy.click()
      const tray = page.getByTestId('trade-tray')
      await expect(tray).toBeVisible()
      // the ceiling is served first (world.buy_capacity, the Max row); a figure typed before it clamps to nought
      await expect(tray.getByTestId('trade-tray-max')).toBeVisible({ timeout: 60_000 })
      await tray.getByTestId('stepper-figure').fill('1')
      await tray.getByTestId('stepper-figure').press('Enter')
      await expect(tray.getByTestId('stepper-figure')).toHaveValue('1')
      const send = tray.getByTestId('trade-tray-send')
      await expect(send).toBeEnabled({ timeout: 60_000 })
      await send.click()
      await expect(tray).toHaveCount(0, { timeout: 60_000 })

      // the row's cargo reads 1, and its Sell is a press now
      const same = market.locator(`[data-testid="here-row"][data-good="${code}"]`)
      await expect(same.locator('[data-col]').first()).toHaveText('1', { timeout: 60_000 })
      await expect(same.getByTestId('here-sell')).toBeEnabled()

      // Sell it back: the same tray, the sell side, all of it (1)
      await same.getByTestId('here-sell').click()
      await expect(tray).toBeVisible()
      await expect(tray.getByTestId('stepper-figure')).toHaveValue('1')
      await expect(send).toBeEnabled({ timeout: 60_000 })
      await send.click()
      await expect(tray).toHaveCount(0, { timeout: 60_000 })
      await expect(same.locator('[data-col]').first()).toHaveText('—', { timeout: 60_000 })

      // no sideways scroll, and no price cut off in its cell
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
      const clipped = await market.evaluate((m) =>
        [...m.querySelectorAll<HTMLElement>('[data-testid="here-buy"], [data-testid="here-sell"]')].filter((e) => e.scrollWidth > e.clientWidth + 1).length,
      )
      expect(clipped, 'a price is cut off in its cell').toBe(0)
    })
  })
}
