import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE DESK'S FACES CHANGE IN PLACE (2026-10-19, src/features/command/DeskFrame.tsx). The owner:
//   *"at top right, when pressing plans, city, invest, i want the screen of the original command tab
//    to stay same, meaning no pop ups or no new screen, but reloading on the same page. get it?"*
// Pinned at the owner's desktop (1440×900) and the phone (390×844), on a local build:
//   · pressing each face keeps the desk's header MOUNTED (the same element, a marker set on it before
//     the first press survives every press) and its faces strip where it was;
//   · the pressed face is the selected one;
//   · NO DIALOG stands after a press: no tray over the screen, at either size;
//   · WIDE: every face stands in the terminal's frame — the same three panes, the same boxes as Markets;
//     what a face opens (City's basket) stands INSIDE the right pane, not over the glass;
//   · a plan stands in the Plans face's own pane (wide: the right pane; phone: in flow), not a tray.
// Prices are the local world's; nothing here asserts a figure — only geometry and presence.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const FACES = [
  { name: 'Plans', id: 'desk-plans' },
  { name: 'City', id: 'desk-city' },
  { name: 'Invest', id: 'desk-invest' },
  { name: 'Profit', id: 'desk-profit' },
  { name: 'Markets', id: 'watch-row' },
] as const

const SIZES = [
  { width: 1440, height: 900 },
  { width: 390, height: 844 },
] as const

async function openDesk(page: Page, request: Parameters<typeof reachable>[0], baseURL: string | undefined) {
  test.setTimeout(480_000)
  test.skip(
    !(await reachable(request, baseURL ?? '')),
    `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
  )
  await page.goto('command')
  await ready(page)
  await expect(page.getByTestId('watch-row').first()).toBeVisible({ timeout: 120_000 })
}

const rect = (page: Page, sel: string) =>
  page.evaluate((s) => {
    const e = document.querySelector(s)
    if (!e) return null
    const r = e.getBoundingClientRect()
    return { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height) }
  }, sel)

/** The boxes that make the frame: on a wide glass the header and the three panes; on a phone the faces strip. */
const frame = async (page: Page, wide: boolean) =>
  wide
    ? {
        header: await rect(page, '[data-testid="desk-header"]'),
        list: await rect(page, '[data-testid="desk-pane-list"]'),
        main: await rect(page, '[data-testid="desk-pane-chart"]'),
        side: await rect(page, '[data-testid="desk-pane-ticket"]'),
      }
    : { faces: await rect(page, '[role="tablist"][aria-label="Desk faces"]') }

for (const size of SIZES) {
  const wide = size.width >= 1024
  test.describe(`the desk's faces at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size })

    test('each face changes in place: the frame stays mounted, no dialog opens', async ({ page, request, baseURL }) => {
      await openDesk(page, request, baseURL)
      const tabs = page.getByRole('tablist', { name: 'Desk faces' })
      // A marker on the element that holds the faces: a new screen would be a new element without it.
      const holder = wide ? '[data-testid="desk-header"]' : '[data-testid="command"]'
      await page.evaluate((s) => document.querySelector(s)!.setAttribute('data-inplace-marker', '1'), holder)
      const before = await frame(page, wide)
      expect(Object.values(before).every((b) => b !== null), 'the desk frame is not drawn').toBe(true)

      for (const f of FACES) {
        await tabs.getByRole('tab', { name: f.name, exact: true }).click()
        await expect(page.getByTestId(f.id).first(), `${f.name} drew nothing`).toBeVisible({ timeout: 60_000 })
        await page.waitForTimeout(500)
        await expect(tabs.getByRole('tab', { name: f.name, exact: true }), `${f.name} is not shown selected`).toHaveAttribute(
          'aria-selected',
          'true',
        )
        await expect(page.locator(`${holder}[data-inplace-marker="1"]`), `${f.name} replaced the desk`).toHaveCount(1)
        await expect(page.getByRole('dialog'), `${f.name} opened a pop-up`).toHaveCount(0)
        expect(await frame(page, wide), `${f.name} moved the desk's frame`).toEqual(before)
        if (wide) {
          await expect(page.locator('[data-desk-frame]'), `${f.name} is not in the desk's frame`).toHaveCount(1)
          // whatever a face opened by itself (City's basket) stands inside the right pane
          const loose = await page.evaluate(
            () =>
              [...document.querySelectorAll('[data-tray-mode]')].filter((t) => !t.closest('[data-testid="desk-pane-ticket"]'))
                .length,
          )
          expect(loose, `${f.name} stood a tray outside the right pane`).toBe(0)
        }
        expect(
          await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth),
          `${f.name} scrolls sideways`,
        ).toBe(true)
      }
    })

    test('a plan stands in the Plans face, not over it', async ({ page, request, baseURL }) => {
      await openDesk(page, request, baseURL)
      await page.getByRole('button', { name: 'Here', exact: true }).click()
      await page.getByTestId('watch-row').first().click()
      const plan = page.getByTestId('desk-plan').first()
      await expect(plan).toBeVisible({ timeout: 60_000 })
      await plan.click()
      await expect(page.getByTestId('plan-builder')).toBeVisible({ timeout: 30_000 })
      // On a phone the good's page (a press on a GOOD, on Markets) covers the faces; the press is sent
      // to the tab itself, as a keyboard or a screen reader would.
      await page.getByRole('tablist', { name: 'Desk faces' }).getByRole('tab', { name: 'Plans', exact: true }).dispatchEvent('click')
      await expect(page.getByTestId('desk-plans')).toBeVisible()
      const builder = page.getByTestId('plan-builder')
      await expect(builder).toBeVisible()
      await expect(page.getByRole('dialog'), 'the plan builder is a pop-up on Plans').toHaveCount(0)
      if (wide) {
        await expect(page.getByTestId('desk-pane-ticket').getByTestId('plan-builder')).toBeVisible()
      } else {
        // in flow: inside the desk's own face, which scrolls with the page
        await expect(page.getByTestId('desk-plans').getByTestId('plan-builder')).toBeVisible()
        expect(await builder.evaluate((e) => getComputedStyle(e).position)).not.toBe('fixed')
      }
      await expect(page.getByTestId('command-queue')).toBeVisible()
    })
  })
}
