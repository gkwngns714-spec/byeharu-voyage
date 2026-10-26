import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// PRESS MY SHIP, SEE HER WHOLE PATH (owner row 225, 2026-10-26: *"i want to see the full paths when i press my
// ship, not the current going city"*). The canary: queue two trips on the Trade page, open the Map, press her
// fleet — the leg she is on AND the queued stop after it are drawn as the planned course, each stop numbered
// (1, 2 …) with its days; pressing her again clears it. In the in-tab (PGlite) world, desktop and phone.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const SIZES = [
  { width: 1440, height: 900 },
  { width: 390, height: 844 },
] as const

/** Sell → the good → Plan → the Nth sell row → Go. */
async function queueTrip(page: Page, code: string, nth: number) {
  const faces = page.getByRole('tablist', { name: 'Desk faces' })
  await faces.getByRole('tab', { name: 'Sell', exact: true }).click()
  const face = page.getByTestId('desk-sell')
  const good = face.locator(`[data-testid="city-good"][data-good="${code}"]`)
  await expect(good).toBeVisible({ timeout: 60_000 })
  if ((await good.getAttribute('aria-pressed')) !== 'true') await good.click()
  await face.getByTestId('good-plan').click()
  const rows = face.getByTestId('trade-sell-row')
  await expect(rows.first()).toBeVisible({ timeout: 120_000 })
  await rows.nth(Math.min(nth, (await rows.count()) - 1)).click()
  const go = face.getByTestId('plan-queue')
  await expect(go).toHaveText('Go', { timeout: 60_000 })
  await go.click()
  await expect(face.getByTestId('trade-card')).toHaveCount(0, { timeout: 60_000 })
}

for (const size of SIZES) {
  test.describe(`a pressed ship shows her whole path at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size })

    test('two queued trips: both legs and the stop numbers are drawn; pressed again, gone', async ({ page, request, baseURL }) => {
      test.setTimeout(600_000)
      test.skip(
        !(await reachable(request, baseURL ?? '')),
        `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
      )
      await page.goto('command')
      await ready(page)
      const faces = page.getByRole('tablist', { name: 'Desk faces' })
      await faces.getByRole('tab', { name: 'Buy', exact: true }).click()
      const buyFace = page.getByTestId('desk-buy')
      const first = buyFace.getByTestId('city-good').first()
      await expect(first).toBeVisible({ timeout: 120_000 })
      const code = await first.getAttribute('data-good')
      await first.click()
      await buyFace.getByTestId('good-buy').click()
      const tray = page.getByTestId('trade-tray')
      await expect(tray.getByTestId('trade-tray-send')).toBeEnabled({ timeout: 60_000 })
      await tray.getByTestId('trade-tray-send').click()
      await expect(tray).toHaveCount(0, { timeout: 60_000 })

      // TWO TRIPS: the first sell city, then a second one after it
      await queueTrip(page, code!, 0)
      await queueTrip(page, code!, 1)
      expect(await page.getByTestId('queue-row').count()).toBeGreaterThanOrEqual(3)

      // the Map: press her in the fleets list
      await page.goto('map')
      await ready(page)
      await page.waitForSelector('[data-testid="map-ports"] > g', { timeout: 300_000 })
      await page.getByTestId('map-fleets-corner').locator('button[aria-expanded]').click()
      await page.getByTestId('map-fleet-row').first().click()

      const path = page.getByTestId('map-ship-path')
      await expect(path).toBeAttached({ timeout: 60_000 })
      // the leg she is on + the queued stops after it, in order
      await expect(page.getByTestId('map-path-stop').first()).toHaveAttribute('data-stop', '1')
      await expect.poll(() => page.getByTestId('map-path-stop').count(), { timeout: 30_000 }).toBeGreaterThanOrEqual(2)
      await expect(page.locator('[data-testid="map-path-stop"][data-stop="2"]').first()).toBeAttached()
      // the planned course (the dashed path) is drawn past the current leg
      await expect(page.getByTestId('map-plan-course').first()).toBeAttached()
      await expect(page.getByTestId('map-path-days').first()).toContainText(/\d/)

      // her tray closed (the press ends): cleared
      await page.getByTestId('map-detail-tray').getByRole('button', { name: /close/i }).first().click()
      await expect(page.getByTestId('map-path-stop')).toHaveCount(0, { timeout: 30_000 })
    })
  })
}
