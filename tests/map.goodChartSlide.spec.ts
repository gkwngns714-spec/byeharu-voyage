import { test, expect, type Page } from '@playwright/test'
import { PHONE, reachable, ready } from './appReady.fixture'
import { openCityPanel } from './openCity.fixture'

// A GOOD'S CHART SLIDES OUT BESIDE THE CITY PANEL (owner row 220, 2026-10-26): *"when pressed map, city,
// then market, buy, when i press trade good, i want to see the chart too on left side of the info page,
// another slide."* Map → Lisbon → Market → press a good's buy cell → a second panel (`price-tray`,
// `side-next`) stands to the LEFT of the city panel with the good's chart and its axis; another good
// swaps it; the same good again, or ×, slides it away. On a phone it covers the sheet (never squeezes
// it), with no sideways scroll.
//
// Run: npm run build && npx vite preview --port <n>, PLAYWRIGHT_BASE_URL=http://localhost:<n>/byeharu-voyage/

const WIDE = { width: 1280, height: 800 }

async function openMarket(page: Page) {
  await page.goto('map')
  await ready(page)
  await page.waitForSelector('[data-testid="map-ports"] > g', { timeout: 300_000 })
  await openCityPanel(page, 'LIS', 'Lisbon')
  await page.getByRole('tab', { name: 'Market' }).click()
  await expect(page.getByTestId('quay-ledger')).toBeVisible({ timeout: 60_000 })
}

/** Press the live buy cell of the nth good; returns that row's name. */
async function pressBuy(page: Page, nth: number): Promise<string> {
  const cell = page.locator('[data-testid="trade-row"] button:enabled').filter({ hasText: /^buy/i }).nth(nth)
  const name = await cell.evaluate((b) => ((b.closest('[data-testid="trade-row"]') as HTMLElement).innerText || '').split('\n')[0].trim())
  await cell.click()
  return name
}

const noSideways = (page: Page) => page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)

test.describe('map city › a good opens its chart', () => {
  test.beforeEach(async ({ request, baseURL }) => {
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  })

  test('wide: the chart stands left of the info panel, swaps, and slides away on × and on a second press', async ({ page }) => {
    test.setTimeout(600_000)
    await page.setViewportSize(WIDE)
    await openMarket(page)
    const info = page.locator('[data-tray-mode="side"]').first()
    const slide = page.getByTestId('price-tray')

    await pressBuy(page, 0)
    await expect(slide).toBeVisible()
    await expect(slide).toHaveAttribute('data-tray-mode', 'side-next')
    await expect(slide.getByTestId('price-chart')).toBeVisible({ timeout: 60_000 })
    await expect(slide.getByTestId('price-chart-x').first()).toBeVisible()
    await expect(slide.getByTestId('price-chart-y').first()).toBeVisible()
    await page.waitForTimeout(500)
    const a = (await slide.boundingBox())!
    const b = (await info.boundingBox())!
    expect(a.x + a.width, 'the chart is not left of the info panel').toBeLessThanOrEqual(b.x + 1)
    expect(await noSideways(page)).toBe(true)

    // another good swaps the chart
    const second = await pressBuy(page, 1)
    await expect(slide).toHaveAttribute('aria-label', second)
    await expect(slide.getByTestId('price-chart')).toBeVisible({ timeout: 60_000 })
    await expect(page.getByTestId('price-tray')).toHaveCount(1)

    // the same good again slides it away; the info panel stays
    await pressBuy(page, 1)
    await expect(slide).toHaveCount(0)
    await expect(info).toBeVisible()

    // × closes it too
    await pressBuy(page, 0)
    await expect(slide).toBeVisible()
    await slide.getByTestId('tray-close').click()
    await expect(slide).toHaveCount(0)
    await expect(info).toBeVisible()
  })

  test('phone: the chart covers the sheet, not squeezes it, and × gives the sheet back', async ({ page }) => {
    test.setTimeout(600_000)
    await page.setViewportSize(PHONE)
    await openMarket(page)
    const info = page.locator('[data-tray-mode="side"]').first()
    const before = (await info.boundingBox())!
    await pressBuy(page, 0)
    const slide = page.getByTestId('price-tray')
    await expect(slide.getByTestId('price-chart')).toBeVisible({ timeout: 60_000 })
    await expect(slide.getByTestId('price-chart-x').first()).toBeVisible()
    await page.waitForTimeout(500)
    expect((await info.boundingBox())!.width, 'the info panel was squeezed').toBe(before.width)
    expect(await noSideways(page)).toBe(true)
    await slide.getByTestId('tray-close').click()
    await expect(slide).toHaveCount(0)
    await expect(info).toBeVisible()
  })
})
