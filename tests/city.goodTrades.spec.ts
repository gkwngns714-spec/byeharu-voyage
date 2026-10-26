// WHO BOUGHT WHAT (0227, owner row 211, 2026-10-26): *"i want to see who bought what when pressed a city -
// clicking trade goods."* Press a city's good → the tray lists that city's recent trades of it: who,
// Bought or Sold, units, price each, when. Here, in the in-tab (PGlite) canary world: buy a good on the
// quay, press the same good again, and the list carries the buy as yours — on a phone and on a wide
// glass, with no sideways scroll.
//
// The build under test must be served: `npm run build && npx vite preview --port <n>`, then
// PLAYWRIGHT_BASE_URL=http://localhost:<n>/byeharu-voyage/ (localhost, not 127.0.0.1).

import { test, expect, type Page } from '@playwright/test'
import { PHONE, ready, reachable } from './appReady.fixture'
import { openCityFace } from './desk.fixture'

test.use({ viewport: PHONE })

/** Press the live `buy` cell of the row named `name` (or the first live one); returns the row's name. */
async function pressBuy(page: Page, name?: string): Promise<string> {
  const got = await page.evaluate((want) => {
    const cells = [...document.querySelectorAll('[data-testid="trade-row"] button:enabled')].filter((b) =>
      /^buy\b/i.test(((b as HTMLElement).innerText || '').trim()),
    ) as HTMLButtonElement[]
    const nameOf = (b: HTMLElement) => {
      const row = b.closest('[data-testid="trade-row"]') as HTMLElement | null
      return row ? (row.innerText || '').split('\n')[0].trim() : ''
    }
    const cell = want ? cells.find((b) => nameOf(b) === want) : cells[0]
    if (!cell) return ''
    const n = nameOf(cell)
    cell.click()
    return n
  }, name ?? null)
  expect(got, 'no live buy cell to press').not.toBe('')
  await expect(page.locator('[data-testid="trade-tray"]')).toBeVisible()
  return got
}

const noSideways = (page: Page) =>
  page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)

test('City › a good pressed lists who bought it: my buy shows as mine, Bought, newest first', async ({ page, request, baseURL }, testInfo) => {
  test.setTimeout(420_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.goto('command')
  await ready(page)
  await openCityFace(page)
  expect(await page.locator('[data-testid="trade-row"]').count(), 'no ledger rows — is a fleet docked?').toBeGreaterThan(1)

  // BUY ONE LOT
  const good = await pressBuy(page)
  const tray = page.locator('[data-testid="trade-tray"]')
  await expect(tray.locator('[data-testid="trade-tray-send"]')).toBeEnabled({ timeout: 30_000 })
  await tray.locator('[data-testid="trade-tray-send"]').click()
  await expect(tray).toHaveCount(0, { timeout: 30_000 })

  // PRESS THE SAME GOOD: the list carries the buy, as mine
  await pressBuy(page, good)
  const list = tray.locator('[data-testid="city-good-trades"]')
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

  // WIDE GLASS: the desk re-lays out (the tray closes with the swap); the same press opens the same
  // list beside the ledger, with no sideways scroll
  await page.setViewportSize({ width: 1280, height: 900 })
  if ((await tray.count()) === 0) await pressBuy(page, good)
  await expect(first).toBeVisible({ timeout: 30_000 })
  await expect(first).toContainText(/you/i)
  expect(await noSideways(page), 'the page scrolls sideways at 1280').toBe(true)
  await page.screenshot({ path: testInfo.outputPath('trades-wide.png') })
})
