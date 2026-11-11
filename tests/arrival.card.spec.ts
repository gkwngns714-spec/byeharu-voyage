import { test, expect } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { buyHere, findCarry, sailAndSell } from './deskMap.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE ARRIVAL CARD (owner row 307, S3; src/app/ArrivalCard.tsx). A new company buys at Lisbon and presses
// Sail & sell, then SITS ON ANOTHER TAB (Fleets). When the fleet comes in and sells, one card appears over that tab:
// the port, what was sold with the server's profit, and what the server's reads say moved (a new port, a level). Its
// profit is the Report's own figure; it is an overlay (the page does not move, nothing scrolls sideways); Next lands
// on Trade and clears it. Phone and desktop, DPR 2.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

test.use({ locale: 'en-US', deviceScaleFactor: 2 })

const SIZES = [
  { width: 390, height: 844 },
  { width: 1280, height: 800 },
] as const

for (const size of SIZES) {
  test.describe(`the arrival card at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size })

    test('a sale landing on another tab shows one card with the Report profit; Next opens Trade', async ({ page, request, baseURL }) => {
      test.setTimeout(480_000)
      test.skip(
        !(await reachable(request, baseURL ?? '')),
        `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
      )
      await page.goto('command')
      await ready(page)
      const { code, city } = await findCarry(page)
      await buyHere(page, code)
      await sailAndSell(page, code, city)

      // sit on another tab while she sails
      await page.goto('fleets')
      await ready(page)
      await expect(page.getByTestId('arrival-card')).toHaveCount(0)
      const main = page.locator('main')
      const before = await main.boundingBox()

      const card = page.getByTestId('arrival-card')
      await expect(card).toBeVisible({ timeout: 300_000 })
      await expect(page.getByTestId('arrival-card')).toHaveCount(1)
      await expect(page.getByTestId('arrival-sale').first()).toContainText(/^Sold \d/)
      const net = Number(await card.getAttribute('data-net'))
      expect(Number.isFinite(net)).toBe(true)

      // an overlay: the page did not move, nothing scrolls sideways, the card sits inside the glass
      expect(await main.boundingBox()).toEqual(before)
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
      const box = (await card.boundingBox())!
      expect(box.x).toBeGreaterThanOrEqual(0)
      expect(box.x + box.width).toBeLessThanOrEqual(size.width)
      const figures = (await page.getByTestId('arrival-sale').allInnerTexts()).join(' ')
      console.log(`arrival card: ${JSON.stringify((await card.innerText()).replace(/\s+/g, ' '))}`)

      // Next: Trade, and the card is gone
      await page.getByTestId('arrival-next').click()
      await expect(page).toHaveURL(/\/command/)
      await expect(page.getByTestId('desk-trade')).toBeVisible()
      await expect(card).toHaveCount(0)

      // the same figure the Report shows (the one sale this company has made)
      await page.getByRole('tablist', { name: 'Desk faces' }).getByRole('tab', { name: 'Report', exact: true }).click()
      await expect(page.getByTestId('report-total')).toBeVisible()
      const sign = (n: number) => (n < 0 ? `−${Math.abs(n)}` : n > 0 ? `+${n}` : '0')
      const digits = (s: string) => s.replace(/[^\d−+-]/g, '').replace('-', '−')
      expect(digits(await page.getByTestId('report-total').innerText()), `card ${figures} vs the Report`).toBe(sign(net).replace(/,/g, ''))
    })
  })
}
