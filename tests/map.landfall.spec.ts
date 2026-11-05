import { test, expect, type Page } from '@playwright/test'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import { haversineNm, project, unproject } from '../src/lib/geo'
import {
  buildCoastline,
  LANDFALL_CAP_NM,
  LANDFALL_INSET_DEG,
  landfallPoint,
  landfallPorts,
  mapPortsOf,
  onDrawnLand,
} from '../src/chart'
import { deriveWorld } from '../scripts/lib/world-derive.mjs'
import { REAL_PORTS } from './mapWorld.fixture'
import { ready, reachable } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// LANDFALL — owner row 92 (2026-09-14): "some cities are in the ocean, not on land such as
// istanbul. I want you to fix it."
//
// The pure half MEASURES: every harbour the database holds (deriveWorld(), the rows world-guard
// proves the applied world equals) against the land the chart actually draws (buildCoastline over
// the vendored file — the same rings, the same decimation), prints the table, and holds the
// rule: after landfall no harbour's mark is in drawn water, with no exception: the 28 islands the
// 110m sheet lacked are in the file (HARBOUR_ISLAND). The browser half reads the DOM of the running
// chart and asks the SVG itself (`isPointInFill`, the fill-rule the body is drawn with) whether
// every harbour mark stands on the land body — at the world view, where every harbour is on the
// sheet, so the check is the whole table and not a sample.
//
// THE BROWSER HALF IS WRITTEN TO RUN AGAINST MAIN AS IT WAS (no `data-port-x`): it
// derives the mark's anchor from the triangle's box (glyphs.ts: the tip is 0.6 h above the
// anchor). Run unfixed it is red — 79 harbours in drawn water — which is the run the log records.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const ROOT = process.cwd()
const WORLD = JSON.parse(readFileSync(path.join(ROOT, 'data', 'world-110m.json'), 'utf8'))
const COAST = buildCoastline(WORLD)
const PORTS = deriveWorld().ports

test.describe('landfall, measured over the real world file', () => {
  test('the table: which harbours fall in drawn water, and how far the shore is', () => {
    const rows: string[] = []
    let inWater = 0
    let moved = 0
    let stranded = 0
    let widestMove = 0
    for (const p of PORTS) {
      const at = project(p)
      if (onDrawnLand(COAST.rings, at)) continue
      inWater++
      const r = landfallPoint(COAST.rings, at)
      if (r.moved) {
        moved++
        widestMove = Math.max(widestMove, r.nm)
        expect(onDrawnLand(COAST.rings, r.at), `${p.name} was moved onto water`).toBe(true)
        expect(r.nm).toBeLessThanOrEqual(LANDFALL_CAP_NM)
        // The whole move is the shore distance plus the inset, and never more.
        const total = haversineNm(p, unproject(r.at))
        expect(total).toBeLessThanOrEqual(r.nm + LANDFALL_INSET_DEG * 61)
      } else {
        stranded++
      }
      rows.push(
        `${p.code}\t${p.name}\t${p.country}\t${p.lat},${p.lon}\t${r.nm.toFixed(2)} nm\t${r.moved ? 'moved' : 'STRANDED'}`,
      )
    }
    console.log(
      `harbours ${PORTS.length} · in drawn water ${inWater} · moved onto the shore ${moved} (widest ${widestMove.toFixed(2)} nm) · stranded ${stranded}\n` +
        rows.join('\n'),
    )
    // MEASURED 2026-09-14 over data/world-110m.json at COASTLINE_TOLERANCE_DEG 0.2 and the 224
    // harbours of data/ports.json. These are pins of a measurement, not laws: a new harbour or a
    // new coast file moves them, and the move is made here, deliberately, with a date.
    // Moved deliberately 2026-09-14 with the Pacific Americas growth (migration 0090, owner row 99):
    // 224 → 238 harbours; ONE of the fourteen falls in drawn water and is moved onto the shore
    // (79 → 80 in water, 51 → 52 moved, widest move 8.58 nm); the islets stay 28. Re-measured by
    // this very test on the merged chain, not remembered.
    // Moved deliberately 2026-10-25 with the far-north, Australasian and northern-US growth
    // (migration 0217, owner row 186): 238 → 246 harbours; ONE of the eight (Fremantle, 0.43 nm)
    // falls in drawn water and is moved onto the shore (80 → 81, 52 → 53, widest still 8.58 nm);
    // the islets stay 28. Measured by this test on 2026-10-25, not remembered.
    expect(PORTS.length).toBe(246)
    // Moved deliberately 2026-11-05 (owner row 92): the 28 stranded harbours' islands are in the
    // file. 26 of the 28 stand inside their drawn island (81 -> 55 in drawn water); Santa Cruz and Banda
    // Neira stand just off it (0.08 and 1.69 nm) and are moved onto it (53 -> 55 moved); NONE is stranded.
    expect(inWater).toBe(55)
    expect(moved).toBe(55)
    // THE LAW: no harbour stands in drawn water. A new harbour on an island nobody drew turns this
    // red, and the island goes in the file (scripts/build-world.mjs, HARBOUR_ISLANDS).
    expect(stranded).toBe(0)
    expect(widestMove).toBeLessThan(LANDFALL_CAP_NM)
  })

  test('landfallPorts: harbours move, sea places and roadsteads do not, identity is kept', () => {
    const served = mapPortsOf(REAL_PORTS)
    const landed = landfallPorts(served, COAST)
    expect(landed).toHaveLength(served.length)
    let movedCount = 0
    for (let i = 0; i < served.length; i++) {
      const before = served[i]
      const after = landed[i]
      expect(after.code).toBe(before.code)
      expect(after.roadstead).toEqual(before.roadstead)
      expect(after.roadsteadNm).toBe(before.roadsteadNm)
      if (before.kind === 'SEA_PLACE') expect(after).toBe(before)
      if (after !== before) {
        movedCount++
        expect(haversineNm(before, after)).toBeLessThanOrEqual(LANDFALL_CAP_NM + LANDFALL_INSET_DEG * 61)
        expect(onDrawnLand(COAST.rings, project(after))).toBe(true)
      } else if (before.kind === 'HARBOUR') {
        // Unmoved: on drawn land already. There is no other way to be unmoved.
        expect(onDrawnLand(COAST.rings, project(before))).toBe(true)
      }
    }
    expect(movedCount).toBeGreaterThan(0)
    // Istanbul, the harbour the owner named: in drawn water at 110m (no Bosporus), moved.
    const ist = served.find((p) => p.code === 'IST')!
    const istAfter = landed.find((p) => p.code === 'IST')!
    expect(onDrawnLand(COAST.rings, project(ist))).toBe(false)
    expect(onDrawnLand(COAST.rings, project(istAfter))).toBe(true)
    // With no coast, nothing moves and the list is the same object.
    expect(landfallPorts(served, null)).toBe(served)
    // With nothing to move, the list is the same object.
    expect(landfallPorts(landed, COAST)).toBe(landed)
  })
})

// ── THE RUNNING CHART ──────────────────────────────────────────────────────────────────────────

/** Every harbour mark on the sheet: its anchor in chart units, and whether the SVG says that point
 *  is inside the land body (evenodd, the body's own rule). */
async function harboursOnLand(page: Page) {
  return page.evaluate(() => {
    const svg = document.querySelector('[data-testid="map-chart"] svg') as SVGSVGElement | null
    const body = document.querySelector('[data-testid="map-coastline"]') as SVGGeometryElement | null
    if (!svg || !body) return null
    const out: { code: string; x: number; y: number; land: boolean }[] = []
    for (const g of document.querySelectorAll('[data-testid="map-ports"] [data-port-code]')) {
      if (g.getAttribute('data-port-kind') !== 'HARBOUR') continue
      const code = g.getAttribute('data-port-code') ?? ''
      let x = Number(g.getAttribute('data-port-x'))
      let y = Number(g.getAttribute('data-port-y'))
      if (!Number.isFinite(x) || !Number.isFinite(y) || g.getAttribute('data-port-x') === null) {
        // main as it was: the anchor from the triangle's box (tip 0.6 h above the anchor).
        const mark = g.querySelector('path, circle') as SVGGraphicsElement | null
        if (!mark) continue
        const b = mark.getBBox()
        x = b.x + b.width / 2
        y = mark.tagName === 'circle' ? b.y + b.height / 2 : b.y + b.height * 0.6
      }
      const pt = svg.createSVGPoint()
      pt.x = x
      pt.y = y
      out.push({ code, x, y, land: body.isPointInFill(pt) })
    }
    return { marks: out }
  })
}

async function openMap(page: Page) {
  await page.goto('map')
  await ready(page)
  await page.waitForFunction(
    () => (document.querySelector('[data-testid="map-coastline"]')?.getAttribute('d') ?? '').length > 1000,
    undefined,
    { timeout: 60_000 },
  )
  await page.waitForTimeout(250)
}

for (const viewport of [
  { width: 390, height: 844 },
  { width: 1440, height: 900 },
]) {
  test.describe(`no harbour mark stands in drawn water at ${viewport.width}×${viewport.height}`, () => {
    test.use({ viewport })

    test('at the opening frame and at the world view, every harbour is on the body', async ({
      page,
      request,
      baseURL,
    }) => {
      test.setTimeout(420_000)
      test.skip(
        !(await reachable(request, baseURL ?? '')),
        `nothing served at ${baseURL} — run \`npm run build && npm run preview\` and re-run.`,
      )
      await openMap(page)

      const opening = await harboursOnLand(page)
      expect(opening).not.toBeNull()
      const wetOpening = opening!.marks.filter((m) => !m.land).map((m) => m.code)
      console.log(`opening frame: ${opening!.marks.length} harbours drawn, ${wetOpening.length} in drawn water: ${wetOpening.join(' ')}`)

      // Out to the world, so every harbour is on the sheet and the check is the whole table.
      for (let i = 0; i < 12; i++) await page.getByRole('button', { name: 'Zoom out' }).click()
      await page.waitForTimeout(300)
      const world = await harboursOnLand(page)
      expect(world).not.toBeNull()
      const wet = world!.marks.filter((m) => !m.land).map((m) => m.code)
      console.log(
        `world view: ${world!.marks.length} harbours drawn, ${wet.length} in drawn water: ${wet.join(' ')}`,
      )
      expect(wetOpening, 'harbours drawn in water at the opening frame').toEqual([])
      expect(wet, 'harbours drawn in water at the world view').toEqual([])
      // Row 94: at the world view EVERY harbour is on the sheet, so this was the whole table.
      // Moved deliberately 2026-09-14: 224 → 238 harbours (the Pacific Americas growth, 0090).
      // Moved deliberately 2026-10-25: 238 → 246 harbours (the far-north, Australasian and
      // northern-US growth, 0217, owner row 186) — counted by HARBOUR: the sheet repeats past ±180°
      // (src/chart/ChartCanvas.tsx, THE COPIES), and Auckland and Wellington, the first harbours
      // near the seam, are drawn in both copies at the world view (248 marks, measured by CI run
      // 40195840956 in tests/map.marks.spec.ts). Every mark, copies included, is checked for land above.
      expect(new Set(world!.marks.map((m) => m.code)).size).toBe(246)
      expect(world!.marks.length).toBe(248)
    })
  })
}
