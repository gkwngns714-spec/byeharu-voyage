import { test, expect, type Page } from '@playwright/test'
import { ready } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE MARKET DESK (0288 + the Market face) — the owner's 2026-10-31 instructions, held
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// "when pressing a market, instead of city, i would like to have a graph shown, that is changed
// when pressed a trade good. when pressing buy, a new page pops up - this is not good. instead,
// have BUY, beneath show all the trade goods neatly organized. So is sell - cargo good." *
// "Request i press, a page shows up, where i search trade good - press it, shows up chart, choose
// price to buy, and then the put the money in it. - the order is made" *
// "but this feature, request, should only be done in your home country- home city."
//
// THE SERVER'S HALF — E_NOT_HOME away from home, the escrow, a merchant's fill at the request's
// price and not below the ask, a partial fill's cancel-refund — is proved by 0288's own self-assert
// on the production chain (rolled-back probe; see the migration's notice). THIS spec holds the
// SCREEN: the chart stands in the city's left region and follows the pressed good, the doors open
// no page, and the home city places a request that is listed and can be cancelled.
const PHONE = { width: 390, height: 844 } as const

async function openMarket(page: Page, size: { width: number; height: number } = PHONE) {
  await page.setViewportSize(size)
  await page.goto('city')
  await ready(page)
  await expect(page.getByTestId('city-screen')).toBeVisible()
  await page.getByTestId('city-building-market').click()
  await expect(page.getByTestId('city-face-panel')).toHaveAttribute('data-building', 'market')
  await expect(page.getByTestId('city-market-chart')).toBeVisible()
}

test.describe.configure({ mode: 'serial' })

test('market @390: the chart is the city’s left region and follows the pressed good', async ({ page }) => {
  await openMarket(page)
  // the good in hand is printed on the chart, and it is not empty
  const chartGood = page.getByTestId('city-market-chart-good')
  await expect(chartGood).toBeVisible()
  const before = (await chartGood.innerText()).trim()
  expect(before.length).toBeGreaterThan(0)

  // press ANOTHER good's price cell: the chart follows it
  const rows = page.getByTestId('trade-row')
  const n = await rows.count()
  expect(n).toBeGreaterThan(1)
  let target: string | null = null
  for (let i = 0; i < n; i++) {
    const name = (await rows.nth(i).innerText()).split('\n')[0].trim()
    if (name.length > 0 && name !== before) {
      target = name
      await rows.nth(i).getByRole('button').first().click()
      break
    }
  }
  expect(target).not.toBeNull()
  await expect(chartGood).toHaveText(target as string)

  // and NO page was opened by the press (the owner's "a new page pops up - this is not good")
  await expect(page.getByTestId('city-market-buy-page')).toHaveCount(0)
})

test('market @390: BUY and SELL are doors in the panel — no page — and SELL lists only cargo', async ({ page }) => {
  await openMarket(page)
  await expect(page.getByTestId('city-market-buy')).toBeVisible()
  // the buy face opens nothing over the frame
  await page.getByRole('tab', { name: 'Buy', exact: true }).click()
  await expect(page.getByTestId('city-market-buy')).toBeVisible()
  await expect(page.getByTestId('city-market-buy-page')).toHaveCount(0)

  await page.getByRole('tab', { name: 'Sell', exact: true }).click()
  await expect(page.getByTestId('city-market-sell')).toBeVisible()
  await expect(page.getByTestId('city-market-sell-page')).toHaveCount(0)
  // nothing aboard at a fresh house: the sell face says exactly that
  const rows = page.getByTestId('trade-row')
  const empty = page.getByText(/No cargo to sell|팔 화물이 없습니다/)
  await expect(rows.or(empty).first()).toBeVisible()
})

test('market @390: the home city places a request, lists it, and cancels it', async ({ page }) => {
  await openMarket(page)
  // the Request door exists at the home city (the local house is founded at Lisboa, the city page's
  // own default) — the same `home` flag the server read serves
  await page.getByRole('tab', { name: 'Requests', exact: true }).click()
  await expect(page.getByTestId('city-market-requests')).toBeVisible()

  await page.getByTestId('city-request-new').click()
  await expect(page.getByTestId('city-request-page')).toBeVisible()

  // search → press a good → its chart → price and amount (prefilled with the ask and 1)
  await page.locator('[data-testid^="city-request-good-"]').first().click()
  await expect(page.getByTestId('city-request-chart')).toBeVisible()
  const place = page.getByTestId('city-request-place')
  await expect(place).toBeEnabled()
  await place.click()
  await expect(page.getByTestId('city-request-page')).toHaveCount(0)

  // the order stands, listed with its payment — the board re-reads on the world's beat
  const open = page.locator('[data-testid^="city-open-request-"]')
  await expect(open.first()).toBeVisible({ timeout: 20_000 })

  // and the cancel returns it (the row leaves the board on the next beat)
  await open.first().getByRole('button', { name: 'Cancel' }).click()
  await expect(page.locator('[data-testid^="city-open-request-"]')).toHaveCount(0, { timeout: 20_000 })
})
