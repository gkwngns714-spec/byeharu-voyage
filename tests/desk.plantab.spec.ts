import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// PLAN TRIP STANDS ON THE FACE IT WAS PRESSED ON, ITS COURSE ON THE MAP ON TOP (owner row 183, 2026-10-20, and
// row 218, 2026-10-26: *"in mini map in command, show cities"* — so the map now draws every city, not only the
// trade's, and the plan's course is drawn over them):
// On a local build, at the owner's desktop (1440×900) and the phone (390×844):
//   · Plan trip on a good of Buy leaves the desk on Buy (its tab selected) and the trade card stands inside it;
//   · the map on top is drawn with the cities on it, and the plan's course on it once a sell city is chosen;
//   · no merchant is on it (no merchant hull, lane, loop or track);
//   · the supplies line, the crew and "Can you go there?" stand on the card;
//   · a second sell row pressed changes the figures in place: the card and the chart do not move.
// Nothing here asserts a price or a requirement's figure; presence, membership and geometry are the claim.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const SIZES = [
  { width: 1440, height: 900 },
  { width: 390, height: 844 },
] as const

/** An element's offset within the Buy face: the sheet scrolls to reach a row, and a scroll is not a move. */
const top = (page: Page, id: string) =>
  page.getByTestId(id).first().evaluate((e) => {
    // wide: the centre pane scrolls by itself, so the offset is within its content (a scroll is not a move)
    const box = (e.closest('[data-testid="desk-pane-chart"]') ?? e.closest('[data-testid="desk-buy"]')) as HTMLElement
    return Math.round(e.getBoundingClientRect().top - box.getBoundingClientRect().top + box.scrollTop)
  })

for (const size of SIZES) {
  test.describe(`plan this trade at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size })

    test('Plan trip stands on Buy, its course on the map with the cities', async ({ page, request, baseURL }) => {
      test.setTimeout(480_000)
      test.skip(
        !(await reachable(request, baseURL ?? '')),
        `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
      )
      await page.goto('command')
      await ready(page)
      const plans = page.getByTestId('desk-buy')
      await expect(plans.getByTestId('city-good').first()).toBeVisible({ timeout: 120_000 })
      await plans.getByTestId('city-good').first().click()
      await plans.getByTestId('good-plan').click()

      // the desk stays on Buy, and the trade is made there
      await expect(
        page.getByRole('tablist', { name: 'Desk faces' }).getByRole('tab', { name: 'Buy', exact: true }),
      ).toHaveAttribute('aria-selected', 'true')
      const card = plans.getByTestId('trade-card')
      await expect(card).toBeVisible({ timeout: 30_000 })
      await expect(page.getByRole('dialog'), 'the trade stands over the screen').toHaveCount(0)
      const rows = page.getByTestId('trade-sell-row')
      await expect(rows.first()).toBeVisible({ timeout: 60_000 })
      await rows.first().click()

      // the chart, once the board has chosen the cities — THE map on top of the face (owner rows 217, 218)
      const voyage = card.getByTestId('plan-voyage')
      await expect(voyage).toBeVisible()
      const map = plans.getByTestId('trade-map')
      const chart = map.getByTestId('small-chart')
      await expect(chart.getByTestId('map-view')).toBeVisible({ timeout: 60_000 })
      await expect(card.getByTestId('plan-queue')).toHaveText('Go', { timeout: 60_000 })
      await expect(chart.locator('[data-port-code]').first()).toBeAttached({ timeout: 30_000 })

      // every city (row 218), and the plan's course over them
      await expect(map.getByTestId('trade-map-cities')).toHaveText('*')
      expect(await chart.locator('[data-port-code]').count(), 'the map draws the cities').toBeGreaterThan(20)
      await expect(map.getByTestId('map-plan-course').first()).toBeAttached({ timeout: 60_000 })
      for (const id of ['map-merchant', 'map-merchant-lane', 'map-merchant-loop', 'map-merchant-track']) {
        await expect(chart.getByTestId(id), `a merchant (${id}) is on the trade's chart`).toHaveCount(0)
      }

      // the figures and the restrictions stand on the card (the supplies are the server's: 0225)
      await expect(card.getByTestId('plan-days')).toBeVisible()
      await expect(card.getByTestId('plan-supplies')).not.toContainText('—', { timeout: 60_000 })
      await expect(voyage.getByTestId('plan-crew-min')).toBeVisible()
      await expect(voyage.getByTestId('plan-restrictions')).toBeVisible()
      await expect(voyage.getByTestId('plan-sea-state')).not.toBeEmpty({ timeout: 30_000 })

      // a second sell row: figures change in place, the card and the chart stay where they were
      if ((await rows.count()) > 1) {
        const before = [await top(page, 'trade-card'), await top(page, 'small-chart')]
        await rows.nth(1).click()
        await page.waitForTimeout(800)
        expect([await top(page, 'trade-card'), await top(page, 'small-chart')], 'a press moved the trade').toEqual(before)
      }
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
    })
  })
}
