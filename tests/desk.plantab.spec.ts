import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// PLAN THIS TRADE OPENS THE TRADE FACE, AND ITS CHART HOLDS ONLY THE TRADE (owner row 183, 2026-10-20; the face
// became Trade with docs/COMMAND_REDESIGN.md R1, rows 190/194/202):
//   *"In command, when I press plan this trade, it should switch to plan tab and make planning there. It
//    should show map (without npcs or name of the cities that aren't associated with the route/plan …"*
// On a local build, at the owner's desktop (1440×900) and the phone (390×844):
//   · the press turns the desk to Trade (its tab selected) and the trade card stands inside it;
//   · the card's chart is drawn, and every harbour on it is one of the trade's cities (where the fleet is,
//     the ports on the way, the buy city, the sell city) — no other city's mark, so no other city's name;
//   · no merchant is on it (no merchant hull, lane, loop or track);
//   · the supplies line, the crew and "Can you go there?" stand on the card;
//   · a second sell row pressed changes the figures in place: the card and the chart do not move.
// Nothing here asserts a price or a requirement's figure; presence, membership and geometry are the claim.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const SIZES = [
  { width: 1440, height: 900 },
  { width: 390, height: 844 },
] as const

/** An element's offset within the Trade face: the sheet scrolls to reach a row, and a scroll is not a move. */
const top = (page: Page, id: string) =>
  page.getByTestId(id).first().evaluate((e) => {
    const face = e.closest('[data-testid="desk-plans"]') as HTMLElement
    return Math.round(e.getBoundingClientRect().top - face.getBoundingClientRect().top)
  })

for (const size of SIZES) {
  test.describe(`plan this trade at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size })

    test('the press opens Trade, and the chart holds only the trade', async ({ page, request, baseURL }) => {
      test.setTimeout(480_000)
      test.skip(
        !(await reachable(request, baseURL ?? '')),
        `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
      )
      await page.goto('command')
      await ready(page)
      await expect(page.getByTestId('watch-row').first()).toBeVisible({ timeout: 120_000 })
      await page.getByRole('button', { name: 'Here', exact: true }).click()
      await page.getByTestId('watch-row').first().click()

      // "Plan this trade" on the Best trade card; a Buy at row's Plan when the card offers none.
      const best = page.getByTestId('best-trade-plan')
      const row = page.getByTestId('desk-plan').first()
      await expect(best.or(row).first()).toBeVisible({ timeout: 60_000 })
      await ((await best.count()) > 0 ? best.first() : row).click()

      // the desk turned to Trade, and the trade is made there
      const plans = page.getByTestId('desk-plans')
      await expect(plans).toBeVisible({ timeout: 30_000 })
      await expect(
        page.getByRole('tablist', { name: 'Desk faces' }).getByRole('tab', { name: 'Trade', exact: true }),
      ).toHaveAttribute('aria-selected', 'true')
      const card = plans.getByTestId('trade-card')
      await expect(card).toBeVisible()
      await expect(page.getByRole('dialog'), 'the trade stands over the screen').toHaveCount(0)

      // the chart, once the board has chosen the cities
      const voyage = card.getByTestId('plan-voyage')
      await expect(voyage).toBeVisible()
      const chart = voyage.getByTestId('small-chart')
      await expect(chart.getByTestId('map-view')).toBeVisible({ timeout: 60_000 })
      await expect(card.getByTestId('plan-queue')).toHaveText('Go', { timeout: 60_000 })
      await expect(chart.locator('[data-port-code]').first()).toBeAttached({ timeout: 30_000 })

      const cities = ((await voyage.getByTestId('plan-chart-cities').textContent()) ?? '').trim().split(/\s+/)
      const drawn = await chart.locator('[data-port-code]').evaluateAll((els) => [
        ...new Set(els.map((e) => e.getAttribute('data-port-code') ?? '')),
      ])
      console.log(`trade cities ${JSON.stringify(cities)} · drawn ${JSON.stringify(drawn)}`)
      expect(cities.length).toBeGreaterThan(0)
      expect(drawn.length).toBeGreaterThan(0)
      for (const code of drawn) expect(cities, `${code} is on the chart and not in the trade`).toContain(code)
      for (const id of ['map-merchant', 'map-merchant-lane', 'map-merchant-loop', 'map-merchant-track']) {
        await expect(chart.getByTestId(id), `a merchant (${id}) is on the trade's chart`).toHaveCount(0)
      }

      // the figures and the restrictions stand on the card (the supplies are the server's: 0221)
      await expect(card.getByTestId('plan-days')).toBeVisible()
      await expect(card.getByTestId('plan-supplies')).not.toContainText('—', { timeout: 60_000 })
      await expect(voyage.getByTestId('plan-crew-min')).toBeVisible()
      await expect(voyage.getByTestId('plan-restrictions')).toBeVisible()
      await expect(voyage.getByTestId('plan-sea-state')).not.toBeEmpty({ timeout: 30_000 })

      // a second sell row: figures change in place, the card and the chart stay where they were
      const rows = page.getByTestId('trade-sell-row')
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
