import { test, expect, type Page } from '@playwright/test'
import { mkdirSync } from 'node:fs'
import path from 'node:path'
import { PHONE, reachable, ready } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A SHIP'S PANEL STANDS OVER HER FLEET'S (src/components/ui/Tray.tsx, the side-next layer)
//
// Map → press a fleet → press one of her ships. The fleet's tray is `Tray mode="side"` and the
// ship's panel is `Tray mode="side-next"`, two FIXED siblings (VoyageTray.tsx mounts the second
// beside the first, not inside it). From `lg` they stand side by side — the ship's panel to the
// fleet tray's LEFT, one layer under it so it slides out from under its edge
// (screenLayout.ts traySideNextClass). Below `lg` both cover the whole width at the same right
// edge, so the layer order alone decides which one a player sees — and until 2026-10-18 it was the
// desktop order: the ship's panel opened BEHIND the fleet tray, invisible and unpressable, on
// every phone. The fix is the one stacking rule in Tray.tsx; this file holds it to what the player
// sees, in both shapes:
//
//   · at 390×844 the ship's panel is the one a finger lands on, its ✕ works, and closing it gives
//     the fleet tray back exactly as it stood (pressing a control SELECTS; nothing restructures);
//   · at 1280×800 the two stand side by side, each the topmost thing at its own centre, the
//     ship's panel's right edge on the fleet tray's left edge — the desktop shape, unchanged.
//
// "On top" is asked of the browser (`document.elementFromPoint`), never of a class name: a
// z-index read off the DOM would pass a panel that is still covered by a sibling in another
// stacking context. Run it: npm run build && npm run preview, then
// `npx playwright test map.shipPanel.spec.ts`.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const WIDE = { width: 1280, height: 800 }
const SHOTS = path.resolve('docs', 'dev-log', '2026-10-18-ship-panel-over-tray')

/** Map → the fleets corner → her row → the fleet tray → her first ship → the ship's panel. */
async function openHerShip(page: Page) {
  await page.goto('map')
  await ready(page)
  await page.waitForSelector('[data-testid="map-ports"] > g', { timeout: 300_000 })
  const pill = page.getByTestId('map-fleets-corner').locator('button[aria-expanded]')
  await pill.click()
  await page.getByTestId('map-fleet-row').first().click()
  const tray = page.getByTestId('map-detail-tray')
  await expect(tray).toBeVisible()
  await expect(tray).toHaveAttribute('data-tray-mode', 'side')
  await page.getByTestId('tray-ship').first().click()
  const panel = page.getByTestId('map-ship-panel')
  await expect(panel).toBeVisible()
  await expect(panel).toHaveAttribute('data-tray-mode', 'side-next')
  return { tray, panel }
}

/** The tray a finger at (x, y) would land on — the browser's own answer, by test id; null off any tray. */
async function trayUnder(page: Page, x: number, y: number): Promise<string | null> {
  return page.evaluate(([px, py]) => {
    const hit = document.elementFromPoint(px, py)
    return hit?.closest('[data-tray-mode]')?.getAttribute('data-testid') ?? null
  }, [x, y] as const)
}

async function centre(locator: ReturnType<Page['getByTestId']>) {
  const box = await locator.boundingBox()
  expect(box).not.toBeNull()
  return { x: box!.x + box!.width / 2, y: box!.y + box!.height / 2, box: box! }
}

test.describe('a ship opened from her fleet', () => {
  test.beforeEach(async ({ request, baseURL }) => {
    test.skip(
      !(await reachable(request, baseURL ?? '')),
      `nothing served at ${baseURL} — run \`npm run build && npm run preview\` and re-run`,
    )
    mkdirSync(SHOTS, { recursive: true })
  })

  test('phone: her panel stands OVER the fleet tray, its ✕ works, and closing it gives the tray back', async ({ page }) => {
    test.setTimeout(600_000)
    await page.setViewportSize(PHONE)
    const { tray, panel } = await openHerShip(page)
    // the slide (240 ms) has ended before anything is measured
    await page.waitForTimeout(500)

    // BOTH COVER THE GLASS (screenLayout.ts: below `lg` a side panel is the whole width) …
    const p = await centre(panel)
    expect(Math.round(p.box.x)).toBe(0)
    expect(Math.round(p.box.width)).toBe(PHONE.width)
    await expect(tray).toHaveCount(1)
    // … so the LAYER decides what is seen. At the panel's own centre, and at its ✕, the browser
    // must hand the press to the ship's panel — not to the fleet tray behind it.
    expect(await trayUnder(page, p.x, p.y), 'the ship panel is behind the fleet tray').toBe('map-ship-panel')
    const close = await centre(panel.getByTestId('tray-close'))
    expect(await trayUnder(page, close.x, close.y), "the ship panel's ✕ is behind the fleet tray").toBe('map-ship-panel')
    // what she is, readable: the equipment page and the spec are hers
    await expect(panel.getByTestId('ship-equipment')).toBeVisible()
    await expect(panel.getByTestId('ship-stats')).toBeVisible()
    await page.screenshot({ path: path.join(SHOTS, 'ship-panel-390.png') })

    // CLOSING RETURNS TO THE FLEET TRAY, which never moved: a real press on the ✕ (Playwright
    // refuses a press on a covered control), then the tray is the thing under the finger again.
    await panel.getByTestId('tray-close').click()
    await expect(panel).toHaveCount(0)
    await expect(tray).toBeVisible()
    await expect(tray).toHaveAttribute('data-tray-mode', 'side')
    const t = await centre(tray)
    expect(await trayUnder(page, t.x, t.y)).toBe('map-detail-tray')
    await expect(page.getByTestId('tray-ship').first()).toBeVisible()
    await page.screenshot({ path: path.join(SHOTS, 'ship-panel-closed-390.png') })
  })

  test('wide: the two stand side by side, each on top at its own centre — the desktop shape', async ({ page }) => {
    test.setTimeout(600_000)
    await page.setViewportSize(WIDE)
    const { tray, panel } = await openHerShip(page)
    await page.waitForTimeout(500)
    const rem = await page.evaluate(() => parseFloat(getComputedStyle(document.documentElement).fontSize))

    const t = await centre(tray)
    const p = await centre(panel)
    // the fleet tray at the right edge, 39rem wide; the ship's panel to its left, 26rem wide,
    // its right edge on the tray's left edge (traySideEdgeClass / traySideNextClass)
    expect(Math.round(t.box.x + t.box.width)).toBe(WIDE.width)
    expect(Math.abs(t.box.width - 39 * rem)).toBeLessThanOrEqual(1)
    expect(Math.abs(p.box.width - 26 * rem)).toBeLessThanOrEqual(1)
    expect(Math.abs(p.box.x + p.box.width - t.box.x)).toBeLessThanOrEqual(1)
    // no overlap, so each is the topmost thing at its own centre
    expect(await trayUnder(page, p.x, p.y)).toBe('map-ship-panel')
    expect(await trayUnder(page, t.x, t.y)).toBe('map-detail-tray')
    await expect(panel.getByTestId('ship-equipment')).toBeVisible()
    await page.screenshot({ path: path.join(SHOTS, 'ship-panel-1280.png') })

    await panel.getByTestId('tray-close').click()
    await expect(panel).toHaveCount(0)
    await expect(tray).toBeVisible()
  })
})
