import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { closeTradeMap, openTradeMap, pressFirstPricedCard, pressNearCity } from './deskMap.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A TRIP STANDS ON THE FACE IT WAS PRESSED ON, ITS COURSE ON THE SMALL MAP (owner row 183, 2026-10-20; row 218; row 229,
// 2026-10-26 — a city she is not at, a good pressed: the panel's one button is "Sail & buy" and the trip is drawn):
// On a local build, at the owner's desktop (1440×900) and the phone (390×844):
//   · a good of a city she is not at leaves the desk on Trade (its tab selected) and the trade panel stands in it;
//   · the small map — a summary row on the compact face since 2026-10-31, a press opening its own full-screen
//     page — is the plan's mini route map (row 191): its stops only, numbered, and the trip's course on it;
//   · no merchant is on it (no merchant hull, lane, loop or track);
//   · the days, the supplies, the crew and "Can you go there?" stand in the panel;
//   · a step of the units changes the figures in place: the panel's button and the map do not move.
// Nothing here asserts a price or a requirement's figure; presence, membership and geometry are the claim.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const SIZES = [
  { width: 1440, height: 900 },
  { width: 390, height: 844 },
] as const

test.use({ locale: 'en-US' })

/** An element's top on the glass (the panel is pinned: a bottom sheet, or the right pane). */
const top = (page: Page, id: string) => page.getByTestId(id).first().evaluate((e) => Math.round(e.getBoundingClientRect().top))

for (const size of SIZES) {
  test.describe(`plan this trade at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size })

    test('Sail & buy stands on Trade, its course on the small map with the cities', async ({ page, request, baseURL }) => {
      test.setTimeout(480_000)
      test.skip(
        !(await reachable(request, baseURL ?? '')),
        `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
      )
      await page.goto('command')
      await ready(page)
      const plans = page.getByTestId('desk-trade')
      await expect(plans.getByTestId('trade-good').first()).toBeVisible({ timeout: 120_000 })
      await pressNearCity(plans)
      await pressFirstPricedCard(plans)

      // the desk stays on Trade, and the trade is made there
      await expect(
        page.getByRole('tablist', { name: 'Desk faces' }).getByRole('tab', { name: 'Trade', exact: true }),
      ).toHaveAttribute('aria-selected', 'true')
      const card = page.getByTestId('good-detail')
      await expect(card).toBeVisible({ timeout: 30_000 })
      await expect(page.getByTestId('trade-act')).toHaveAttribute('data-act', 'sail-buy')

      // the chart — THE small map, a summary row on the compact face (owner rows 217, 218; a page since 2026-10-31)
      const voyage = card.getByTestId('plan-voyage')
      await expect(voyage).toBeAttached({ timeout: 60_000 })
      // press the map's summary row and work inside its page, the way a player does
      await openTradeMap(plans)
      const map = plans.getByTestId('trade-map')
      const chart = map.getByTestId('small-chart')
      await expect(chart.getByTestId('map-view')).toBeVisible({ timeout: 60_000 })
      await expect(chart.locator('[data-port-code]').first()).toBeAttached({ timeout: 30_000 })

      // ROW 191 (docs/COMMAND_REDESIGN.md §3): the plan's map is the ROUTE ONLY — every harbour on it is a stop
      // of the plan, numbered; the trip's course runs over them; and the chart is still (no zoom column).
      const legLines = map.getByTestId('plan-leg')
      await expect(legLines.first()).toBeVisible({ timeout: 60_000 })
      const stopCodes = [...new Set((await legLines.evaluateAll((es) => es.map((e) => e.getAttribute('data-to') ?? ''))).filter(Boolean))]
      expect(stopCodes.length, 'the plan has no stop').toBeGreaterThan(0)
      await expect(map).toHaveAttribute('data-cities', stopCodes.join(' '))
      const drawn = [...new Set(await chart.locator('[data-port-code]').evaluateAll((es) => es.map((e) => e.getAttribute('data-port-code') ?? '')))]
      expect(drawn.length, 'the plan map draws no stop').toBeGreaterThan(0)
      for (const code of drawn) expect(stopCodes, `${code} is drawn and is not a stop of the plan`).toContain(code)
      expect(drawn.sort(), 'a stop of the plan is missing from its map').toEqual([...stopCodes].sort())
      await expect(map.getByTestId('map-plan-course').first()).toBeAttached({ timeout: 60_000 })
      await expect(chart.getByTestId('small-chart-controls'), 'the plan map is not still').toHaveCount(0)
      for (const id of ['map-merchant', 'map-merchant-lane', 'map-merchant-loop', 'map-merchant-track']) {
        await expect(chart.getByTestId(id), `a merchant (${id}) is on the trade's chart`).toHaveCount(0)
      }

      // the figures and the restrictions stand in the panel (the supplies are the server's: 0225)
      await expect(card.getByTestId('plan-days')).toBeAttached()
      await expect(card.getByTestId('plan-supplies')).not.toContainText('—', { timeout: 60_000 })
      await expect(voyage.getByTestId('plan-crew-min')).toBeAttached()
      await expect(voyage.getByTestId('plan-restrictions')).toBeAttached()
      await expect(voyage.getByTestId('plan-sea-state')).not.toBeEmpty({ timeout: 30_000 })

      // A STEP OF THE UNITS (the press law): a press changes the figures in place and moves nothing that
      // follows it. Read the face with the map's page CLOSED — an open page covers the screen, so the
      // press would land on the page, not the card; the map's place on the face is its summary row.
      await closeTradeMap(plans)
      const before = [await top(page, 'trade-act'), await top(page, 'trade-map-open')]
      await card.getByRole('button', { name: 'Less', exact: true }).click()
      await page.waitForTimeout(800)
      expect([await top(page, 'trade-act'), await top(page, 'trade-map-open')], 'a press moved the trade').toEqual(before)
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
    })
  })
}
