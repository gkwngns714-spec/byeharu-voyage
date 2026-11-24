import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { pressFirstPricedCard, pressNearCity } from './deskMap.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A TRIP STANDS ON THE FACE IT WAS PRESSED ON (owner row 183, 2026-10-20; row 218; row 229,
// 2026-10-26 — a city she is not at, a good pressed: the panel's one button is "Sail & buy"):
// On a local build, at the owner's desktop (1440×900) and the phone (390×844):
//   · a good of a city she is not at leaves the player on HQ (the URL does not move) and the trade sheet stands over it;
//   · the days, the supplies, the crew and "Can you go there?" stand in the panel;
//   · a step of the units changes the figures in place: the panel's button does not move.
// H3 (2026-11-24): the Trade desk is gone, and with it the draft trip's mini route map beside the panel (row 191); the map of
// her ORDERS is a page of her sheet (tests/trade.map.spec.ts).
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

    test('Sail & buy stands over HQ, its figures and restrictions in the panel', async ({ page, request, baseURL }) => {
      test.setTimeout(480_000)
      test.skip(
        !(await reachable(request, baseURL ?? '')),
        `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
      )
      await page.goto('city')
      await ready(page)
      await pressNearCity(page)
      const url = page.url()
      await pressFirstPricedCard(page)

      // she stays on HQ, and the trade is made there
      expect(page.url(), 'the Buy left HQ').toBe(url)
      await expect(page.getByTestId('city-screen')).toBeVisible()
      const card = page.getByTestId('good-detail')
      await expect(card).toBeVisible({ timeout: 30_000 })
      await expect(page.getByTestId('trade-act')).toHaveAttribute('data-act', 'sail-buy')

      const voyage = card.getByTestId('plan-voyage')
      await expect(voyage).toBeAttached({ timeout: 60_000 })

      // the figures and the restrictions stand in the panel (the supplies are the server's: 0225)
      await expect(card.getByTestId('plan-days')).toBeAttached()
      await expect(card.getByTestId('plan-supplies')).not.toContainText('—', { timeout: 60_000 })
      await expect(voyage.getByTestId('plan-crew-min')).toBeAttached()
      await expect(voyage.getByTestId('plan-restrictions')).toBeAttached()

      // A STEP OF THE UNITS (the press law): a press changes the figures in place and moves nothing that follows it.
      const before = [await top(page, 'trade-act'), await top(page, 'stepper-figure')]
      await card.getByRole('button', { name: 'Less', exact: true }).click()
      await page.waitForTimeout(800)
      expect([await top(page, 'trade-act'), await top(page, 'stepper-figure')], 'a press moved the trade').toEqual(before)
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
    })
  })
}
