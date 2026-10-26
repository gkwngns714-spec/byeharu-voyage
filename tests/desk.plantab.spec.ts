import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { pressFirstPricedCard, pressNearCity } from './deskMap.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A TRIP STANDS ON THE FACE IT WAS PRESSED ON, ITS COURSE ON THE MAP ON TOP (owner row 183, 2026-10-20; row 218; row 229,
// 2026-10-26 — a city she is not at, a good pressed: the panel's one button is "Sail & buy" and the trip is drawn):
// On a local build, at the owner's desktop (1440×900) and the phone (390×844):
//   · a good of a city she is not at leaves the desk on Buy (its tab selected) and the trade panel stands in it;
//   · the map on top is drawn with every city on it, and the trip's course on it;
//   · no merchant is on it (no merchant hull, lane, loop or track);
//   · the days, the supplies, the crew and "Can you go there?" stand in the panel;
//   · a step of the units changes the figures in place: the panel's button and the chart do not move.
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

    test('Sail & buy stands on Buy, its course on the map with the cities', async ({ page, request, baseURL }) => {
      test.setTimeout(480_000)
      test.skip(
        !(await reachable(request, baseURL ?? '')),
        `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
      )
      await page.goto('command')
      await ready(page)
      const plans = page.getByTestId('desk-buy')
      await expect(plans.getByTestId('city-good').first()).toBeVisible({ timeout: 120_000 })
      await pressNearCity(plans)
      await pressFirstPricedCard(plans)

      // the desk stays on Buy, and the trade is made there
      await expect(
        page.getByRole('tablist', { name: 'Desk faces' }).getByRole('tab', { name: 'Buy', exact: true }),
      ).toHaveAttribute('aria-selected', 'true')
      const card = page.getByTestId('good-detail')
      await expect(card).toBeVisible({ timeout: 30_000 })
      await expect(page.getByTestId('trade-act')).toHaveAttribute('data-act', 'sail-buy')

      // the chart — THE map on top of the face (owner rows 217, 218)
      const voyage = card.getByTestId('plan-voyage')
      await expect(voyage).toBeAttached({ timeout: 60_000 })
      const map = plans.getByTestId('trade-map')
      const chart = map.getByTestId('small-chart')
      await expect(chart.getByTestId('map-view')).toBeVisible({ timeout: 60_000 })
      await expect(chart.locator('[data-port-code]').first()).toBeAttached({ timeout: 30_000 })

      // every city (row 218), and the trip's course over them
      await expect(map).toHaveAttribute('data-cities', '*')
      expect(await chart.locator('[data-port-code]').count(), 'the map draws the cities').toBeGreaterThan(20)
      await expect(map.getByTestId('map-plan-course').first()).toBeAttached({ timeout: 60_000 })
      for (const id of ['map-merchant', 'map-merchant-lane', 'map-merchant-loop', 'map-merchant-track']) {
        await expect(chart.getByTestId(id), `a merchant (${id}) is on the trade's chart`).toHaveCount(0)
      }

      // the figures and the restrictions stand in the panel (the supplies are the server's: 0225)
      await expect(card.getByTestId('plan-days')).toBeAttached()
      await expect(card.getByTestId('plan-supplies')).not.toContainText('—', { timeout: 60_000 })
      await expect(voyage.getByTestId('plan-crew-min')).toBeAttached()
      await expect(voyage.getByTestId('plan-restrictions')).toBeAttached()
      await expect(voyage.getByTestId('plan-sea-state')).not.toBeEmpty({ timeout: 30_000 })

      // a step of the units: the figures change in place, the button and the map stay where they were
      const before = [await top(page, 'trade-act'), await top(page, 'small-chart')]
      await card.getByRole('button', { name: 'Less', exact: true }).click()
      await page.waitForTimeout(800)
      expect([await top(page, 'trade-act'), await top(page, 'small-chart')], 'a press moved the trade').toEqual(before)
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
    })
  })
}
