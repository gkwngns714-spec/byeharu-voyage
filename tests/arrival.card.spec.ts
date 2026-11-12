import { test, expect } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { buyHere, findCarry, sailAndSell } from './deskMap.fixture'
import { serveRaidWorld } from './raidWorld.fixture'

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

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A RAID ON THE PASSAGE (0353, owner row 315; docs/COMBAT_LOG.md 1.5): the card says one line for the raid, and Log
// unfolds the fight's log INSIDE the card, scrolling within it. A card hides after 20 s; a log needs longer, so the
// card WAITS while a log is open and its clock starts again when the log is folded. The world is the one raid of
// fixed facts (tests/raidWorld.fixture.ts): given Flee through the real door, she sails 30 seconds and is raided.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
test.describe('the arrival card with a raid at 390×844', () => {
  test.use({ viewport: { width: 390, height: 844 } })

  test('one raid line; Log unfolds the log in the card; the card waits while it is open', async ({ page, request, baseURL }) => {
    test.setTimeout(600_000)
    expect(await reachable(request, baseURL ?? ''), `nothing served at ${baseURL}: run a preview (or set PLAYWRIGHT_BASE_URL)`).toBe(true)
    await serveRaidWorld(page)
    await page.goto('fleets')
    await ready(page)
    await page.getByTestId('fleet-row').first().click()
    await page.getByTestId('raid-order-FLEE').click()
    await expect(page.getByTestId('raid-order')).toHaveAttribute('data-order', 'FLEE')
    await page.keyboard.press('Escape')
    const main = page.locator('main')
    const before = await main.boundingBox()

    const card = page.getByTestId('arrival-card')
    await expect(card).toBeVisible({ timeout: 300_000 })
    // she sold nothing: the card is the port, the raid, and what the server's reads say moved
    await expect(page.getByTestId('arrival-sale')).toHaveCount(0)
    await expect(page.getByTestId('arrival-raid')).toHaveCount(1)
    await expect(page.getByTestId('arrival-raid')).toContainText('Raid: Fled · Hull −17%')
    await expect(card.getByTestId('fight-log')).toHaveCount(0)

    // Log: the log unfolds inside the card, a line at a time, to its result
    const press = page.getByTestId('arrival-raid-log')
    await expect(press).toHaveText('Log')
    await expect(press).toHaveAttribute('aria-expanded', 'false')
    const opened = Date.now()
    await press.click()
    await expect(press).toHaveAttribute('aria-expanded', 'true')
    const log = card.getByTestId('fight-log')
    await expect(log).toBeVisible()
    await expect(log.getByTestId('fight-log-result')).toHaveText('Result Fled, round 6', { timeout: 30_000 })
    await expect(log.getByTestId('fight-log-round')).toHaveCount(6)
    await expect(log.getByTestId('fight-log-lost')).toHaveText('Lost Hull −68 (17%) · Crew 0 · Cargo 0')
    // it scrolls inside the card, never the page: the card is an overlay, the page did not move, nothing scrolls sideways
    expect(await log.evaluate((el) => getComputedStyle(el).overflowY)).toBe('auto')
    expect(await log.evaluate((el) => el.scrollWidth <= el.clientWidth + 1)).toBe(true)
    expect(await main.boundingBox()).toEqual(before)
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
    const box = (await card.boundingBox())!
    expect(box.x).toBeGreaterThanOrEqual(0)
    expect(box.x + box.width).toBeLessThanOrEqual(390)
    expect(box.y, 'the card with a log open stands inside the glass').toBeGreaterThanOrEqual(0)
    expect(box.y + box.height).toBeLessThanOrEqual(844)

    // THE CARD WAITS: 24 s after the log was opened (the card's own clock is 20 s) it still stands
    await page.waitForTimeout(Math.max(0, 24_000 - (Date.now() - opened)))
    await expect(card).toBeVisible()
    await expect(log).toBeVisible()
    // folded, the clock starts again and the card goes by itself
    await press.click()
    await expect(card.getByTestId('fight-log')).toHaveCount(0)
    await expect(card).toBeVisible()
    await expect(card).toHaveCount(0, { timeout: 30_000 })
  })
})
