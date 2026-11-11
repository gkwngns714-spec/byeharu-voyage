import { test, expect, type Page } from '@playwright/test'
import { RAIL_REM } from '../src/components/ui/screenLayout'
import { ready } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE SHELL'S TWO LEFTOVERS (2026-11-11, after S9: docs/dev-log/2026-11-11-shell-polish.md)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// S9 put a rail down the window's left edge from `lg` and gave the HQ the status strip. Two things were left standing as they
// were before it:
//   1. the trade's toast centred on the WINDOW, so beside the rail it stood half a rail (48 px) left of the page it speaks for;
//   2. the HQ's "Your earnings" card printed the purse the strip now prints on the same glass.
// Both are measured here, on a phone (no rail: nothing may have moved) and at 1280 (the rail).

test.use({ locale: 'en-US' })

const GLASSES = [
  { width: 1280, height: 800 },
  { width: 390, height: 844 },
] as const

/** The glass the page stands on: what the rail leaves. Read from the nav itself (a rail is taller than wide; a bar takes
 *  nothing off the side), and from the status strip, which spans that glass. Two readings, so neither is taken on trust. */
async function contentGlass(page: Page, navId: string) {
  return page.evaluate((id) => {
    const nav = document.querySelector(`[data-testid="${id}"]`)!.getBoundingClientRect()
    const strip = document.querySelector('header')!.getBoundingClientRect()
    const isRail = nav.height > nav.width
    const left = isRail ? nav.right : 0
    return { isRail, railWidth: isRail ? nav.width : 0, centre: (left + innerWidth) / 2, stripCentre: (strip.left + strip.right) / 2 }
  }, navId)
}

for (const glass of GLASSES) {
  test.describe(`at ${glass.width}×${glass.height}`, () => {
    test.use({ viewport: glass })

    test('the trade toast is centred on the page beside the rail, not on the window', async ({ page }) => {
      test.setTimeout(480_000)
      await page.goto('command')
      await ready(page)
      await page.getByRole('tablist', { name: 'Desk faces' }).getByRole('tab', { name: 'Goods', exact: true }).click()
      const card = page.getByTestId('desk-trade').getByTestId('trade-board').getByTestId('trade-good').first()
      await expect(card).toBeVisible({ timeout: 120_000 })
      await card.getByTestId('trade-buy').click()
      const panel = page.getByTestId('good-detail')
      await expect(panel.getByRole('button', { name: 'Max', exact: true })).toBeVisible({ timeout: 60_000 })
      await panel.getByTestId('stepper-figure').fill('1')
      await panel.getByTestId('stepper-figure').press('Enter')
      const act = page.getByTestId('trade-act')
      await expect(act).toBeEnabled({ timeout: 60_000 })
      await act.click()

      const toast = page.getByTestId('trade-toast')
      await expect(toast).toContainText(/^Bought 1 /, { timeout: 60_000 })
      const box = (await toast.boundingBox())!
      const toastCentre = box.x + box.width / 2
      const area = await contentGlass(page, 'app-nav')
      console.log(
        `toast @${glass.width}: centre ${toastCentre.toFixed(1)}, page centre ${area.centre.toFixed(1)} (strip ${area.stripCentre.toFixed(1)}), window centre ${glass.width / 2}, rail ${area.railWidth}`,
      )
      // NON-VACUITY: the rail stands at 1280 and not on a phone, so the two glasses measure two different things
      expect(area.isRail, 'the nav is a rail from 1,024 and a bar below it').toBe(glass.width >= 1024)
      if (area.isRail) expect(area.railWidth).toBe(RAIL_REM * 16)
      expect(Math.abs(area.stripCentre - area.centre), 'the status strip does not span the glass beside the rail').toBeLessThanOrEqual(1)
      // THE LAW: the toast's middle is the page's middle
      expect(Math.abs(toastCentre - area.centre), `the toast stands ${(toastCentre - area.centre).toFixed(1)} px off the page's centre`).toBeLessThanOrEqual(1)
      // … and it is whole on that glass
      expect(box.x).toBeGreaterThanOrEqual(area.centre * 2 - glass.width)
      expect(box.x + box.width).toBeLessThanOrEqual(glass.width)
    })

    test('the HQ prints the purse once, in the status strip: no "Your earnings" card', async ({ page }) => {
      test.setTimeout(480_000)
      await page.goto('city')
      await ready(page)
      const screen = page.getByTestId('city-screen')
      await expect(screen).toBeVisible()
      await expect(page.getByTestId('city-hall-panel')).toBeVisible({ timeout: 120_000 })
      // the strip's purse is there, with a figure (the fact the card repeated)
      const purse = screen.getByTestId('purse')
      await expect(purse).toHaveCount(1)
      await expect(purse).toHaveText(/\d/, { timeout: 60_000 })
      const figure = (await purse.innerText()).replace(/[^\d]/g, '')
      console.log(`HQ @${glass.width}: the strip's purse reads "${(await purse.innerText()).replace(/\s+/g, ' ')}"`)
      // on every place of the HQ: no earnings card, no earnings word, and the purse's figure stands nowhere under the strip
      for (const place of ['hall', 'market', 'port', 'inn', 'production']) {
        await page.getByTestId(`city-building-${place}`).click()
        await expect(page.locator('.animate-pulse')).toHaveCount(0, { timeout: 120_000 })
        await expect(page.getByTestId('city-summary'), `${place}: the earnings card stands`).toHaveCount(0)
        await expect(screen.getByText('Your earnings'), `${place}: the earnings word stands`).toHaveCount(0)
        await expect(screen.getByTestId('purse'), `${place}: the strip's purse is gone`).toHaveCount(1)
      }
      expect(figure.length, 'the purse had no figure to repeat').toBeGreaterThan(0)
    })
  })
}
