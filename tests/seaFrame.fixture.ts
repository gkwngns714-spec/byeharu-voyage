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

/** How many merchant marks have their centre inside `zone`, and the chart's degrees per pixel. */
export async function merchantsInZone(page: Page, zone: GlassZone): Promise<{ inZone: number; unitsPerPx: number }> {
  return page.evaluate((z) => {
    const chart = document.querySelector('[data-testid="map-chart"]')!.getBoundingClientRect()
    const svg = document.querySelector('[data-testid="map-fleets"]')?.closest('svg')
    const unitsPerPx = svg && chart.width > 0 ? svg.viewBox.baseVal.width / chart.width : NaN
    let inZone = 0
    for (const g of document.querySelectorAll('[data-testid="map-merchant"]')) {
      const r = g.getBoundingClientRect()
      const cx = r.left + r.width / 2
      const cy = r.top + r.height / 2
      if (cx >= chart.left + z.left && cx <= chart.right - z.right && cy >= chart.top + z.top && cy <= chart.bottom - z.bottom) inZone++
    }
    return { inZone, unitsPerPx }
  }, zone)
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
