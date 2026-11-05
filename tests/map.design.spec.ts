import { test, expect, type Page } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'
import { DESIGN_GLASSES } from './design.fixture'
import { pressCity } from './deskMap.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE MAP ON THE PAGE PATTERN — the owner's design order (row 267), 2026-11-04
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"…The past was better. right now everything is on left, too packed. this was a mistake."* The Map is ONE GLASS OF CHART, so the
// pattern means this (docs/dev-log/2026-11-04-map-design.md): the chart is the main column and stays whole; the selection panels are
// the SIDE column — a tray from `lg` is the page's side column (`--page-side`: 352 · 384 · 416 px, its right edge on the window's
// edge since row 278) and slides OVER the chart's right part; it never pushes or shrinks the chart. It was 39 rem flush to the glass's edge.
//
// THE LAWS (from 1,024 px unless said):
//   (a) THE CHART IS NEVER REDUCED: its box is the same shut and with a tray open.
//   (b) THE TRAY IS THE SIDE COLUMN: its width is the page's side width, its right edge 0 px from the window's edge. REVERSED BY THE OWNER
//       2026-11-05 (row 278; it was the page's margin, max(--page-pad, (glass − 1,280)/2)): "i want it to slide from the right slide from the edge of the page".
//   (c) THE CHROME GIVES WAY: the zoom column's right edge is left of the tray's left edge.
//   (d) BELOW 1,024 the tray is the glass, as it was.
//   (e) NOTHING SCROLLS BUT THE TRAY'S OWN BODY: the document stays flat.
// RED BEFORE: against origin/main (the 39-rem panel flush to the edge) (b) fails at every wide glass.

const SIDE = (w: number) => (w >= 1440 ? 416 : w >= 1280 ? 384 : 352)

async function pressLisbon(page: Page) {
  await page.waitForSelector('[data-testid="map-ports"] > g', { timeout: 300_000 })
  await page.waitForTimeout(1200)
  await pressCity(page, page.getByTestId('map-chart'), 'LIS')
}

for (const glass of DESIGN_GLASSES) {
  test(`the map's tray is the page's side column and the chart is not reduced, at ${glass.width}×${glass.height}`, async ({ page, request, baseURL }) => {
    test.setTimeout(600_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await page.setViewportSize(glass)
    await page.goto('map')
    await ready(page)
    const chart = page.getByTestId('map-chart')
    await expect(chart).toBeVisible({ timeout: 300_000 })
    const shut = await chart.boundingBox()
    await pressLisbon(page)
    const tray = page.locator('[data-tray-mode="side"]')
    await expect(tray).toBeVisible({ timeout: 60_000 })
    await page.waitForTimeout(700)
    const t = (await tray.boundingBox())!
    const open = await chart.boundingBox()
    const failures: string[] = []
    if (JSON.stringify(open) !== JSON.stringify(shut)) failures.push(`(a) the chart box changed: ${JSON.stringify(shut)} → ${JSON.stringify(open)}`)
    if (glass.width >= 1024) {
      if (Math.abs(t.width - SIDE(glass.width)) > 1) failures.push(`(b) the tray is ${Math.round(t.width)} px wide — the side column is ${SIDE(glass.width)}`)
      const right = glass.width - (t.x + t.width)
      // The owner, 2026-11-05: "i want it to slide from the right slide from the edge of the page".
      if (Math.abs(right) > 1) failures.push(`(b) the tray's right edge is ${Math.round(right)} px from the window's edge — it stands on the edge`)
      const controls = await page.getByTestId('map-view-controls').boundingBox()
      if (controls && controls.x + controls.width > t.x + 1) failures.push(`(c) the zoom column (right edge ${Math.round(controls.x + controls.width)}) stands under the tray (left edge ${Math.round(t.x)})`)
    } else if (Math.abs(t.width - glass.width) > 1) failures.push(`(d) below 1,024 the tray is ${Math.round(t.width)} px, the glass is ${glass.width}`)
    const doc = await page.evaluate(() => ({ sh: document.documentElement.scrollHeight, ch: document.documentElement.clientHeight, sw: document.documentElement.scrollWidth, cw: document.documentElement.clientWidth }))
    if (doc.sh > doc.ch + 1 || doc.sw > doc.cw + 1) failures.push(`(e) the document scrolls ${JSON.stringify(doc)}`)
    if (failures.length) console.log(`LAWS map @${glass.width}×${glass.height}\n  ${failures.join('\n  ')}`)
    expect(failures, 'The Map is not on the page pattern').toEqual([])
  })
}
