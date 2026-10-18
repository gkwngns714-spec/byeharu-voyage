// THE SEA NEAR LISBON IS NOT A FIXTURE — the one precondition-setter for "merchants on the glass"
// (2026-10-17), shared by every spec that needs merchant hulls to look at.
//
// WHY THIS FILE EXISTS. The merchants-on world (./npcOn.fixture.ts) sails on the REAL clock, so how
// many hulls stand inside one frame is the sea's business at that minute, not a property of the
// build. Two specs asserted it anyway and went red on a correct chart:
//
//   map.hulls (CI 38917698523, 38864772736, 38845860625) resizes 390 → 1280 and asks the 1280 glass
//   for two merchants. The view keeps its CENTRE AND HORIZONTAL SPAN on a resize (./chartView.ts
//   header), so the same 14.9° that is 28.8° tall on a phone is 8.8° tall on a 1280 × 844 desktop —
//   a band from 34.3°N to 43.1°N. Measured in the failing trace: of the 13 merchants the phone drew,
//   exactly ONE lay inside that band, and the 1280 glass drew exactly that one. No mark was lost; the
//   band was nearly empty sea for the whole 60 s wait, because the merchants were off Morocco and
//   the Canaries. Reproduced locally the same way: 7 of 20 phone marks inside the band, 7 drawn.
//
//   map.merchants "wide" (CI 38810111728, 38831207542) waited for two merchants on the WHOLE glass
//   and then hunted a hull in the tap zone (60 / 120 / 100 / 120 px in from the edges) — a smaller
//   region than the one it waited on — and threw "no merchant hull on the glass" 24 s in.
//
// THE RULE: a spec SETS this precondition instead of assuming it — pull back a press at a time
// until the region it is about to use holds what it needs — and it counts in the SAME region it
// then uses. One helper, so the wait and the use cannot drift apart again.

import { expect, type Page } from '@playwright/test'
import { ZOOM_STEP } from '../src/chart'
import { WORLD_BOOT_MS } from './appReady.fixture'

/** A region of the chart, as insets in CSS px from the chart's own edges. */
export interface GlassZone {
  readonly left: number
  readonly right: number
  readonly top: number
  readonly bottom: number
}

/** The whole chart. */
export const WHOLE_GLASS: GlassZone = { left: 0, right: 0, top: 0, bottom: 0 }

/** Where a hull can be TAPPED: clear of the corner chrome and the tray's peek. */
export const TAP_ZONE: GlassZone = { left: 60, right: 120, top: 100, bottom: 120 }

/** THE VIEW SHEET (src/chart/ChartCanvas.tsx): the one svg whose viewBox IS the view. The sea's
 *  svgs are pictures of the glass on a unit square since the no-blink fix (SeaLayer.tsx header), so
 *  "the first svg" or "the svg around the marks" is not how the view is read — this selector is. */
const VIEW_SHEET = '[data-testid="map-view"]'

/**
 * THE CHART IS OPEN: its view sheet is on the glass. `ready()` (./appReady.fixture.ts) cannot see
 * this. On the map route the world's boot shows as the chart's own "opening the chart…" line
 * (src/features/map/ChartMessage.tsx), not as the gate's "Opening the world." that `ready()` waits
 * out — so `ready()` returns while PGlite is still loading the world image, and a spec that counts
 * merchants next counts them on a chart that is not there. CI runs 39088373678 and 39092641268
 * (map.merchants "wide" and "Porto lists …"): the first count came 0.8 s after the goto, every one
 * of the twenty-two reads over the next 22 s said "0 merchants, NaN °/px", the screencast at 22.9 s
 * still read "opening the chart…", and the chart was open by the time the failure screenshot was
 * taken four seconds later. The budget is `ready()`'s world-boot budget, because it is the same boot.
 *
 * Since 2026-10-18 `ready()` itself waits for the store's load phase (the shell's `data-world`), so
 * the boot is behind every spec on every route before it gets here; what stays is this helper's own
 * precondition — the view sheet it reads is on the glass.
 */
export async function chartOpen(page: Page): Promise<void> {
  await page.locator(VIEW_SHEET).waitFor({ state: 'attached', timeout: WORLD_BOOT_MS })
}

/** How many merchant marks have their centre inside `zone`, and the chart's degrees per pixel.
 *  Throws, rather than answering NaN, when the chart is not open: a density of NaN is not a
 *  measurement, and the one caller's guard read it as "the next press would pass the limit". */
export async function merchantsInZone(page: Page, zone: GlassZone): Promise<{ inZone: number; unitsPerPx: number }> {
  return page.evaluate(
    ([z, viewSheet]) => {
      const view = document.querySelector(viewSheet) as SVGSVGElement | null
      if (!view) throw new Error(`the chart is not open: no view sheet (${viewSheet}) on the glass`)
      const chart = document.querySelector('[data-testid="map-chart"]')!.getBoundingClientRect()
      if (!(chart.width > 0)) throw new Error('the chart has no width')
      const unitsPerPx = view.viewBox.baseVal.width / chart.width
      let inZone = 0
      for (const g of document.querySelectorAll('[data-testid="map-merchant"]')) {
        const r = g.getBoundingClientRect()
        const cx = r.left + r.width / 2
        const cy = r.top + r.height / 2
        if (cx >= chart.left + z.left && cx <= chart.right - z.right && cy >= chart.top + z.top && cy <= chart.bottom - z.bottom) inZone++
      }
      return { inZone, unitsPerPx }
    },
    [zone, VIEW_SHEET] as const,
  )
}

/**
 * WAIT FOR `min` MERCHANTS IN `zone`, PULLING BACK A PRESS AT A TIME IF THE SEA THERE IS EMPTY.
 * Returns how many presses it took, so a caller that needs its frame back presses Zoom in as many
 * times (the zoom is about the glass's centre). `maxUnitsPerPx` keeps a press from crossing a density
 * the caller's own claims depend on — the hull-group collapse, for one — and is checked BEFORE the
 * press, so the helper fails loudly rather than handing back a sheet that changed character.
 */
export async function pullBackUntilMerchants(
  page: Page,
  { min = 2, zone = WHOLE_GLASS, maxPresses = 4, maxUnitsPerPx = Infinity, waitMs = 20_000 }: {
    min?: number
    zone?: GlassZone
    maxPresses?: number
    maxUnitsPerPx?: number
    waitMs?: number
  } = {},
): Promise<number> {
  // The precondition's own precondition: the chart is open before anything on it is counted.
  await chartOpen(page)
  for (let presses = 0; ; presses++) {
    const enough = await expect
      .poll(async () => (await merchantsInZone(page, zone)).inZone, { timeout: waitMs })
      .toBeGreaterThanOrEqual(min)
      .then(() => true, () => false)
    if (enough) return presses
    const { inZone, unitsPerPx } = await merchantsInZone(page, zone)
    if (presses === maxPresses || !(unitsPerPx * ZOOM_STEP <= maxUnitsPerPx)) {
      throw new Error(
        `${inZone} merchant(s) in the zone, fewer than ${min}, after ${presses} press(es) of Zoom out ` +
          `(${unitsPerPx.toFixed(4)} °/px; the next press would pass ${maxUnitsPerPx} or the ${maxPresses}-press limit)`,
      )
    }
    await page.getByLabel('Zoom out').click()
    await page.waitForTimeout(800)
  }
}
