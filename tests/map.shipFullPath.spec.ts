import { test, expect } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { buyHere, findCarry, sailAndSell } from './deskMap.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// PRESS MY SHIP, SEE HER WHOLE PATH (owner row 225, 2026-10-26: *"i want to see the full paths when i press my
// ship, not the current going city"*). The canary: queue two trips (Sell › a city › Sail & sell, owner row 229), open the Map, press her
// fleet — the leg she is on AND the queued stop after it are drawn as the planned course, each stop numbered
// (1, 2 …) with its days; pressing her again clears it. In the in-tab (PGlite) world, desktop and phone.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const SIZES = [
  { width: 1440, height: 900 },
  { width: 390, height: 844 },
] as const

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
      // THREE TRIPS (owner row 229, cities pressed): buy a good here, Sail & sell it at a city that deals in it, then
      // Sail & buy at two more. The cities are near (a leg is minutes), so the first trip may be done by the time the
      // Map is open; two more keep a leg under way AND a stop after it.
      const { code, city, home } = await findCarry(page)
      await buyHere(page, code)
      await sailAndSell(page, code, city)
      const faces = page.getByRole('tablist', { name: 'Desk faces' })
      await faces.getByRole('tab', { name: 'Buy', exact: true }).click()
      const buyFace = page.getByTestId('desk-buy')
      const chips = buyFace.getByTestId('city-chip')
      const codes = await chips.evaluateAll((es) => es.map((e) => e.getAttribute('data-port') ?? ''))
      let queuedMore = 0
      for (const other of codes.slice(1)) {
        if (queuedMore >= 2) break
        if (other === city || other === home) continue
        await buyFace.locator(`[data-testid="city-chip"][data-port="${other}"]`).click()
        const card = buyFace.locator('[data-testid="city-good"]:not([disabled])').first()
        await expect(buyFace.getByTestId('city-goods')).toHaveAttribute('data-city', other)
        await expect(buyFace.getByTestId('city-good').first().or(buyFace.getByTestId('city-goods-none'))).toBeVisible({ timeout: 60_000 })
        if (!(await card.isVisible())) continue
        await card.click()
        const act = page.getByTestId('trade-act')
        await expect(act).toHaveAttribute('data-act', 'sail-buy')
        await expect(act).toBeEnabled({ timeout: 30_000 }).catch(() => {})
        if (!(await act.isEnabled())) {
          console.log(`no trip to ${other}: ${await act.innerText()}`)
          await card.click()
          continue
        }
        await act.click()
        await expect(page.getByTestId('good-detail')).toHaveCount(0, { timeout: 60_000 })
        queuedMore++
      }
      expect(queuedMore, 'two more trips could not be queued').toBe(2)
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
