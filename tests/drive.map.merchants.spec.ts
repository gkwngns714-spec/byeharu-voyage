import { test, expect } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { chartOpen } from './seaFrame.fixture'
import { serveNpcOn } from './npcOn.fixture'
import { watchMeter, type MeterWindow } from './mapMeter.fixture'

// Its own file because a spec that imports tests/npcOn.fixture.ts joins the merchants-on POOL (select-specs.mjs): the plain drive.map.spec.ts must stay in the
// plain pool, where its row-72 send arrives on the plain world's clock.

const WIDE = { width: 1280, height: 800 }

test.use({ deviceScaleFactor: 2 })

// A LIT WORLD KEEPS ITS ROSTER (production's case: the merchants sail there). The store keeps the ships it has read across tabs and
// places them in the very call that asks for them (worldStore `wantTraffic`), so on a return to the map no read is pending and the
// meter must not commit a single frame (a flash at the top of the sea on every return). Merchants-on world, Map → HQ → Map. A dark
// roster is not kept, so on a dark world this law would see "Ships 75 %" and go red: it holds the lit case only.
test('Map @1280, merchants on: a return to the map commits no frame of meter, the kept roster paints at once (row 255, D6)', async ({ page, request, baseURL }) => {
  test.setTimeout(900_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await serveNpcOn(page)
  await page.setViewportSize(WIDE)
  await page.addInitScript(watchMeter)
  await page.goto('map')
  await ready(page)
  await chartOpen(page)
  // the cold load counted its steps, the roster among them, and went
  await expect(page.getByTestId('map-load')).toHaveCount(0, { timeout: 120_000 })
  const cold = await page.evaluate(() => (window as unknown as MeterWindow).__meter ?? [])
  console.log(`AUDIT map meter @1280, merchants on, cold: ${JSON.stringify(cold.map((e) => (e.gone ? 'gone' : `${e.step} ${e.pct}`)))}`)
  expect(cold.filter((e) => !e.gone).length, 'the cold load showed no loading percentage').toBeGreaterThan(0)
  await page.evaluate(() => {
    ;(window as unknown as MeterWindow).__meter = []
  })
  await page.getByTestId('nav-cell-/city').first().click()
  await expect(page.getByTestId('city-rail')).toBeVisible({ timeout: 120_000 })
  await page.getByTestId('nav-cell-/map').first().click()
  await chartOpen(page)
  await page.waitForTimeout(1500)
  const warm = await page.evaluate(() => (window as unknown as MeterWindow).__meter ?? [])
  console.log(`AUDIT map meter @1280, merchants on, back from the HQ: ${JSON.stringify(warm)}`)
  expect(warm, 'the meter flashed on a return with the roster kept').toEqual([])
})
