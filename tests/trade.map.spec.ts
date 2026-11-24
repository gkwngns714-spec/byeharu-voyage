import { test, expect } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { closeTop, openFleetSheet } from './desk.fixture'
import { buyHere, findCarry } from './deskMap.fixture'

// THE TRIP IN HAND IS DRAWN ON HER MAP (owner row 183, 2026-10-25: *"It should show map (without npcs or name of the cities that
// aren't associated with the route/plan"*). Until H3 (2026-11-24) the Trade desk's Map page drew the trip being composed in its trade
// panel. The desk is gone; the trip last opened in the trade sheet (plans/planDraft.ts, the one draft) is drawn on the Map page of
// HER SHEET over HQ (src/app/HqSheet.tsx `FleetSheet`), until an order is pressed there. This spec is the desk's, walked on HQ:
//   · a cargo row pressed in her sheet opens that trip in the trade sheet; back in her sheet, her Map draws its legs and its stops,
//     and no other city;
//   · the map's frame is one size for two trips;
//   · the trip sent queues one SAIL line a leg.

const SIZES = [
  { width: 1440, height: 900 },
  { width: 390, height: 844 },
] as const

for (const size of SIZES) {
  test.describe(`the trip's route map at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size, locale: 'en-US' })

    test("her sheet's map draws the trip in hand, its stops and legs; the SAIL lines queue", async ({ page, request, baseURL }) => {
      test.setTimeout(600_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`)
      await page.goto('city')
      await ready(page)

      // a good she can carry, bought where she lies
      const { code, home } = await findCarry(page)
      await buyHere(page, code)

      const sheet = await openFleetSheet(page)
      const place = () => sheet.locator(`[data-testid="cargo-good"][data-good="${code}"]`).locator(`[data-testid="cargo-place"]:not([data-port="${home}"])`)
      const panel = page.getByTestId('good-detail')
      const act = page.getByTestId('trade-act')
      const mapPage = page.getByTestId('hq-sheet-fleet-map-page')

      /** Open the trip to the i-th place her cargo sells, and step back to her sheet: the trip stays in hand. */
      const tripTo = async (i: number) => {
        await expect(place().nth(i)).toBeVisible({ timeout: 120_000 })
        const to = (await place().nth(i).getAttribute('data-port'))!
        await place().nth(i).click()
        await expect(panel).toHaveAttribute('data-city', to, { timeout: 60_000 })
        await expect(act).toHaveText(/Sail & sell|Too far|Cargo full|Shut|No money/, { timeout: 60_000 })
        return to
      }
      const backToSheet = async () => {
        await closeTop(page)
        await expect(panel).toHaveCount(0)
        await expect(sheet).toBeVisible()
      }
      const openMap = async () => {
        await page.getByTestId('hq-sheet-fleet-map').click()
        await expect(mapPage).toBeVisible()
        return mapPage.getByTestId('trade-map')
      }
      const closeMap = async () => {
        await mapPage.locator('[data-detail-back]').first().click()
        await expect(mapPage).toHaveCount(0)
      }

      // THE FIRST TRIP: its legs and its stops, and no other city
      const to0 = await tripTo(0)
      await backToSheet()
      const map = await openMap()
      const chart = map.getByTestId('small-chart')
      const legs = map.getByTestId('plan-leg')
      await expect(legs.first(), 'the trip in hand is not drawn on her map').toBeVisible({ timeout: 60_000 })
      const stops = [...new Set((await legs.evaluateAll((es) => es.map((e) => e.getAttribute('data-to') ?? ''))).filter(Boolean))]
      expect(stops.length, 'the trip has no stops').toBeGreaterThan(0)
      expect(stops, 'the pressed city is not a stop of the trip').toContain(to0)
      await expect(map).toHaveAttribute('data-cities', stops.join(' '))
      const drawn = [...new Set(await chart.locator('[data-port-code]').evaluateAll((es) => es.map((e) => e.getAttribute('data-port-code') ?? '')))]
      expect(drawn.sort(), 'the map draws other cities than the trip’s stops').toEqual([...stops].sort())
      await expect(chart.getByTestId('small-chart-controls')).toHaveCount(0)
      const box0 = await chart.boundingBox()
      await page.screenshot({ path: `test-results/desk-into-hq/trip-map-${size.width}.png` })
      await closeMap()

      // A SECOND TRIP: the same frame
      if ((await place().count()) > 1) {
        await tripTo(1)
        await backToSheet()
        const box1 = await (await openMap()).getByTestId('small-chart').boundingBox()
        expect({ w: Math.round(box1!.width), h: Math.round(box1!.height) }, 'the map frame resized between two trips').toEqual({
          w: Math.round(box0!.width),
          h: Math.round(box0!.height),
        })
        await closeMap()
      }

      // A TRIP SHE CAN SAIL: its legs counted on her map, then sent; one SAIL line a leg
      let ready0: number | null = null
      for (let i = 0; i < Math.min(6, await place().count()); i++) {
        await tripTo(i)
        const go = (await act.innerText()).trim() === 'Sail & sell' && (await act.isEnabled())
        await backToSheet()
        if (go) {
          ready0 = i
          break
        }
      }
      expect(ready0, 'no place her cargo sells made a trip ready to sail').not.toBeNull()
      await tripTo(ready0!)
      await backToSheet()
      const sailLines = await (await openMap()).getByTestId('plan-leg').count()
      expect(sailLines, 'the trip has no leg line').toBeGreaterThan(0)
      await closeMap()
      await tripTo(ready0!)
      await expect(act).toHaveText(/^Sail & sell$/)
      await act.click()
      await expect(page.getByTestId('trade-toast')).toContainText('Sailing to', { timeout: 60_000 })
      // the trip sent, the trade sheet steps back to her sheet, where her orders are
      await expect(sheet).toBeVisible({ timeout: 60_000 })
      await expect
        .poll(
          async () => (await sheet.getByTestId('queue-row').allInnerTexts()).filter((t) => /^\s*Sail\b/i.test(t)).length + (await sheet.getByTestId('queue-passage').count()),
          { timeout: 90_000, message: `${sailLines} legs, so ${sailLines} SAIL lines (queued SAILs + the passage under way)` },
        )
        .toBe(sailLines)
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
    })
  })
}
