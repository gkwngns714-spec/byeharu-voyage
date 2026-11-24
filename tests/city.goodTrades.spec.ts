// WHO BOUGHT WHAT (0227, owner row 211, 2026-10-26): *"i want to see who bought what when pressed a city -
// clicking trade goods."* Press a city's good → its panel lists that city's recent trades of it: who,
// Bought or Sold, units, price each, when. Here, in the in-tab (PGlite) canary world: buy a good, press the
// same good again, and the list carries the buy as yours — on a phone and on a wide glass, with no sideways scroll.
//
// SINCE S1 (2026-11-24, docs/design/simplify-2026-11-24.md; src/app/HqSheet.tsx) a price pressed on HQ's Market opens THE
// trade sheet over the page it was pressed on — the URL does not move — so the list is read where the trade is, in the sheet's panel
// (TradePanel.tsx draws CityGoodTrades). The sheet stays open after a trade where she lies. H3 (2026-11-24): the Office is gone;
// the Market plate is the one trade list.
//
// The build under test must be served: `npm run build && npx vite preview --port <n>`, then
// PLAYWRIGHT_BASE_URL=http://localhost:<n>/byeharu-voyage/ (localhost, not 127.0.0.1).

import { test, expect, type Page } from '@playwright/test'
import { PHONE, ready, reachable } from './appReady.fixture'
import { openMarket, tradeOnDesk } from './desk.fixture'
import { pressFirstPricedCard } from './deskMap.fixture'

test.use({ viewport: PHONE })

/** Press the Buy of the Market's first card with a live one; it opens THE trade sheet over HQ on that good, the URL unmoved (S1).
 *  Returns the good's code. */
async function pressBuy(page: Page): Promise<string> {
  const url = page.url()
  const code = await pressFirstPricedCard(page)
  const sheet = page.getByTestId('good-detail')
  await expect(sheet, 'the trade sheet did not open on the good pressed').toBeVisible({ timeout: 60_000 })
  expect(page.url(), 'the Buy left the page it was pressed on').toBe(url)
  await expect(sheet).toHaveAttribute('data-side', 'buy')
  await expect(sheet).toHaveAttribute('data-good', code)
  return code
}

const noSideways = (page: Page) =>
  page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)

test('City › a good pressed lists who bought it: my buy shows as mine, Bought, newest first', async ({ page, request, baseURL }, testInfo) => {
  test.setTimeout(420_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.goto('city')
  await ready(page)
  await openMarket(page)
  expect(await page.locator('[data-testid="city-market-buy"] [data-testid="trade-good"]').count(), 'no goods cards — is a fleet docked?').toBeGreaterThan(1)

  // BUY ONE LOT, in the sheet the Market's Buy opens
  const code = await pressBuy(page)
  expect(code, 'the open sheet has no good').not.toBe('')
  await tradeOnDesk(page)

  // THE SAME GOOD'S SHEET, STILL OPEN: its list carries the buy, as mine
  await expect(page.getByTestId('good-detail')).toHaveAttribute('data-good', code)
  const list = page.getByTestId('city-good-trades')
  await expect(list).toBeVisible({ timeout: 30_000 })
  const first = list.locator('[data-testid="city-good-trade"]').first()
  await expect(first).toBeVisible({ timeout: 30_000 })
  await expect(first).toContainText(/you/i)
  await expect(first).toContainText(/Bought \d+/)
  await expect(first).toContainText(/each/)
  await expect(first).toContainText(/just now|min ago/)
  await expect(first.locator('[data-side="bought"]')).toHaveCount(1)
  // the company's name is whole: its hover title is the same text
  const title = await first.locator('[title]').first().getAttribute('title')
  expect(title, 'the company name has no full-text title').toBeTruthy()
  await expect(first).toContainText(title ?? '')
  expect(await noSideways(page), 'the page scrolls sideways at 390').toBe(true)
  await list.scrollIntoViewIfNeeded()
  await page.screenshot({ path: testInfo.outputPath('trades-phone.png') })

  // WIDE GLASS: HQ re-lays out; the same press opens the same list in the sheet, with no sideways scroll
  await page.setViewportSize({ width: 1280, height: 900 })
  await expect(async () => {
    if ((await list.count()) === 0)
      await page.locator(`[data-testid="city-market-buy"] [data-testid="trade-good"][data-good="${code}"]`).getByTestId('trade-buy').click({ timeout: 2_000 })
    await expect(first).toBeVisible({ timeout: 2_000 })
  }).toPass({ timeout: 60_000 })
  await expect(first).toContainText(/you/i)
  expect(await noSideways(page), 'the page scrolls sideways at 1280').toBe(true)
  await page.screenshot({ path: testInfo.outputPath('trades-wide.png') })
})
