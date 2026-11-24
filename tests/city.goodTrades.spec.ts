// WHO BOUGHT WHAT (0227, owner row 211, 2026-10-26): *"i want to see who bought what when pressed a city -
// clicking trade goods."* Press a city's good → its panel lists that city's recent trades of it: who,
// Bought or Sold, units, price each, when. Here, in the in-tab (PGlite) canary world: buy a good, press the
// same good again, and the list carries the buy as yours — on a phone and on a wide glass, with no sideways scroll.
//
// SINCE S1 (2026-11-24, docs/design/simplify-2026-11-24.md; src/app/HqSheet.tsx) a price pressed on Office > City > Market opens THE
// trade sheet over the page it was pressed on — the URL does not move — so the list is read where the trade is, in the sheet's panel
// (TradePanel.tsx draws the same CityGoodTrades the quay's tray drew). The sheet stays open after a trade where she lies.
//
// The build under test must be served: `npm run build && npx vite preview --port <n>`, then
// PLAYWRIGHT_BASE_URL=http://localhost:<n>/byeharu-voyage/ (localhost, not 127.0.0.1).

import { test, expect, type Page } from '@playwright/test'
import { PHONE, ready, reachable } from './appReady.fixture'
import { openCityFace, tradeOnDesk } from './desk.fixture'

test.use({ viewport: PHONE })

/** Press the live `buy` cell of the Market face's first live row; it opens THE trade sheet over the Office on that good, the URL
 *  unmoved (S1). Returns the good's code and the row's name. */
async function pressBuy(page: Page): Promise<{ code: string; name: string }> {
  const url = page.url()
  const name = await page.evaluate(() => {
    const cell = [...document.querySelectorAll('[data-testid="trade-row"] button:enabled')].find((b) =>
      /^buy\b/i.test(((b as HTMLElement).innerText || '').trim()),
    ) as HTMLButtonElement | undefined
    const row = cell?.closest('[data-testid="trade-row"]') as HTMLElement | null
    cell?.click()
    return row ? (row.innerText || '').split('\n')[0].trim() : ''
  })
  expect(name, 'no live buy cell to press').not.toBe('')
  const sheet = page.getByTestId('good-detail')
  await expect(sheet, 'the trade sheet did not open on the good pressed').toBeVisible({ timeout: 60_000 })
  expect(page.url(), 'the Buy left the page it was pressed on').toBe(url)
  await expect(sheet).toHaveAttribute('data-side', 'buy')
  return { code: (await sheet.getAttribute('data-good')) ?? '', name }
}

/** The Market face's row of the good named: its Buy opens the good's sheet. */
const rowBuy = (page: Page, name: string) =>
  page.locator('[data-testid="trade-row"]').filter({ hasText: name }).first().getByRole('button', { name: /^buy/i }).first()

const noSideways = (page: Page) =>
  page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)

test('City › a good pressed lists who bought it: my buy shows as mine, Bought, newest first', async ({ page, request, baseURL }, testInfo) => {
  test.setTimeout(420_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.goto('command')
  await ready(page)
  await openCityFace(page)
  expect(await page.locator('[data-testid="trade-row"]').count(), 'no ledger rows — is a fleet docked?').toBeGreaterThan(1)

  // BUY ONE LOT, in the sheet the Market face's price opens
  const good = await pressBuy(page)
  expect(good.code, 'the open sheet has no good').not.toBe('')
  await tradeOnDesk(page)

  // THE SAME GOOD'S SHEET, STILL OPEN: its list carries the buy, as mine
  await expect(page.getByTestId('good-detail')).toHaveAttribute('data-good', good.code)
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

  // WIDE GLASS: the Office re-lays out as the terminal; the same press opens the same list in the sheet, in its right pane, with no
  // sideways scroll
  await page.setViewportSize({ width: 1280, height: 900 })
  await expect(page.getByTestId('desk-pane-ticket'), 'the Office did not re-lay out for the wide glass').toBeVisible({ timeout: 60_000 })
  await expect(async () => {
    if ((await list.count()) === 0) await rowBuy(page, good.name).click({ timeout: 2_000 })
    await expect(first).toBeVisible({ timeout: 2_000 })
  }).toPass({ timeout: 60_000 })
  await expect(first).toContainText(/you/i)
  expect(await noSideways(page), 'the page scrolls sideways at 1280').toBe(true)
  await page.screenshot({ path: testInfo.outputPath('trades-wide.png') })
})
