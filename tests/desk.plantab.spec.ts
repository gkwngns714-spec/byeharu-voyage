import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// PLAN THIS TRADE OPENS THE PLANS FACE, AND ITS CHART HOLDS ONLY THE PLAN (owner row 183, 2026-10-20):
//   *"In command, when I press plan this trade, it should switch to plan tab and make planning there. It
//    should show map (without npcs or name of the cities that aren't associated with the route/plan …"*
// On a local build, at the owner's desktop (1440×900) and the phone (390×844):
//   · the press turns the desk to Plans (its tab selected) and the plan builder stands inside it;
//   · the plan's chart is drawn, and every harbour on it is one of the plan's cities (where the fleet is,
//     the ports on the way, the buy city, the sell city) — no other city's mark, so no other city's name;
//   · no merchant is on it (no merchant hull, lane, loop or track);
//   · the voyage's figures and "Can you go there?" stand under the estimate;
//   · a second sell city pressed changes the figures in place: the estimate and the chart do not move.
// Nothing here asserts a price or a requirement's figure; presence, membership and geometry are the claim.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const SIZES = [
  { width: 1440, height: 900 },
  { width: 390, height: 844 },
] as const

const top = (page: Page, id: string) =>
  page.getByTestId(id).first().evaluate((e) => Math.round(e.getBoundingClientRect().top))

for (const size of SIZES) {
  test.describe(`plan this trade at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size })

    test('the press opens Plans, and the chart holds only the plan', async ({ page, request, baseURL }) => {
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

      // the desk turned to Plans, and the plan is made there
      const plans = page.getByTestId('desk-plans')
      await expect(plans).toBeVisible({ timeout: 30_000 })
      await expect(
        page.getByRole('tablist', { name: 'Desk faces' }).getByRole('tab', { name: 'Plans', exact: true }),
      ).toHaveAttribute('aria-selected', 'true')
      const builder = plans.getByTestId('plan-builder')
      await expect(builder).toBeVisible()
      await expect(page.getByRole('dialog'), 'the plan stands over the screen').toHaveCount(0)

      // the chart, once the board has chosen the cities
      const voyage = builder.getByTestId('plan-voyage')
      await expect(voyage).toBeVisible()
      const chart = voyage.getByTestId('small-chart')
      await expect(chart.getByTestId('map-view')).toBeVisible({ timeout: 60_000 })
      await expect(builder.getByTestId('plan-estimate')).toContainText('Net', { timeout: 60_000 })
      await expect(chart.locator('[data-port-code]').first()).toBeAttached({ timeout: 30_000 })

      const cities = ((await voyage.getByTestId('plan-chart-cities').textContent()) ?? '').trim().split(/\s+/)
      const drawn = await chart.locator('[data-port-code]').evaluateAll((els) => [
        ...new Set(els.map((e) => e.getAttribute('data-port-code') ?? '')),
      ])
      console.log(`plan cities ${JSON.stringify(cities)} · drawn ${JSON.stringify(drawn)}`)
      expect(cities.length).toBeGreaterThan(0)
      expect(drawn.length).toBeGreaterThan(0)
      for (const code of drawn) expect(cities, `${code} is on the chart and not in the plan`).toContain(code)
      for (const id of ['map-merchant', 'map-merchant-lane', 'map-merchant-loop', 'map-merchant-track']) {
        await expect(chart.getByTestId(id), `a merchant (${id}) is on the plan's chart`).toHaveCount(0)
      }

      // the voyage and the restrictions stand under the estimate
      await expect(voyage.getByTestId('plan-days')).toBeVisible()
      await expect(voyage.getByTestId('plan-supplies')).toBeVisible()
      await expect(voyage.getByTestId('plan-crew-min')).toBeVisible()
      await expect(voyage.getByTestId('plan-restrictions')).toBeVisible()
      await expect(voyage.getByTestId('plan-sea-state')).not.toBeEmpty({ timeout: 30_000 })

      // a second sell city: figures change in place, the estimate and the chart stay where they were
      const sellChips = builder.getByRole('group', { name: 'Sell at' }).getByRole('button')
      if ((await sellChips.count()) > 1) {
        const before = [await top(page, 'plan-estimate'), await top(page, 'small-chart')]
        await sellChips.nth(1).click()
        await page.waitForTimeout(800)
        expect([await top(page, 'plan-estimate'), await top(page, 'small-chart')], 'a press moved the plan').toEqual(before)
      }
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
    })
  })
}
