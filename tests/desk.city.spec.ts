import { test, expect } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// INVEST AND REPORT, DRIVEN — on a local build, at the phone. They were faces of the Office (and of the Trade desk
// before 2026-11-16); since H3 `desk-into-hq` (2026-11-24) each is a sheet over HQ, opened by its own door there
// (`city-office-invest`, `city-office-report`). The Office's City face and its building strip are gone: the buildings
// are HQ's plates, and tests/hq.desk.spec.ts walks every one of them.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

test.use({ viewport: { width: 390, height: 844 } })

test('the Invest face: your holdings, and the Town Hall of the city the fleet is at', async ({ page, request, baseURL }) => {
  test.setTimeout(420_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
  await page.goto('city')
  await ready(page)
  await page.getByTestId('city-office-invest').click()
  await expect(page.getByTestId('hq-sheet-invest')).toBeVisible()
  await expect(page.getByTestId('invest-holdings')).toBeVisible()
  await expect(page.getByTestId('invest-holdings')).toContainText(/shares|Held/, { timeout: 30_000 })
  await expect(page.getByTestId('invest-hall')).toBeVisible({ timeout: 30_000 })
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
})

test('the Report face: spans, the total, eight section rows and the places', async ({ page, request, baseURL }) => {
  test.setTimeout(420_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
  await page.goto('city')
  await ready(page)
  await page.getByTestId('city-office-report').click()
  await expect(page.getByTestId('hq-sheet-report')).toBeVisible()
  await expect(page.getByTestId('desk-report')).toBeVisible()
  await expect(page.getByTestId('report-spans')).toBeVisible({ timeout: 30_000 })
  for (const id of ['trade', 'crew', 'supplies', 'repairs', 'insurance', 'invest', 'ships', 'other'])
    await expect(page.getByTestId(`report-section-${id}`)).toHaveAttribute('data-summary-row', '')
  // a pressed section opens its own page (the pop-up mechanism), and the back press returns
  await page.getByTestId('report-section-trade').click()
  await expect(page.getByTestId('report-section-trade-page')).toBeVisible()
  await page.locator('[data-detail-back]').last().click()
  await expect(page.getByTestId('report-section-trade-page')).toHaveCount(0)
  // a new company has made nothing yet (its starting money is capital, not profit): the report says so
  await expect(page.getByTestId('report-places')).toContainText(/Nothing in or out/, { timeout: 30_000 })
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
})
