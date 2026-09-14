import { test, expect, type Page } from '@playwright/test'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import { haversineNm, project, unproject } from '../src/lib/geo'
import {
  buildCoastline,
  GLYPH,
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
// LANDFALL — owner row 91 (2026-09-14): "some cities are in the ocean, not on land such as
// istanbul. I want you to fix it."
//
// The pure half MEASURES: every harbour the database holds (deriveWorld(), the rows world-guard
// proves the applied world equals) against the land the chart actually draws (buildCoastline over
// the vendored file — the same rings, the same decimation), prints the table, and holds the
// rule: after landfall no harbour's mark is in drawn water unless it is an island the file has no
// polygon for, and then it wears an islet. The browser half reads the DOM of the running chart
// and asks the SVG itself (`isPointInFill`, the fill-rule the body is drawn with) whether every
// harbour mark stands on the land body or on an islet — at the world view, where all 224 are on
// the sheet, so the check is the whole table and not a sample.
//
// THE BROWSER HALF IS WRITTEN TO RUN AGAINST MAIN AS IT WAS (no `data-port-x`, no islets): it
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
    let islets = 0
    let widestMove = 0
    let nearestIslet = Infinity
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
        expect(r.stranded).toBe(true)
        islets++
        nearestIslet = Math.min(nearestIslet, r.nm)
        expect(r.nm).toBeGreaterThan(LANDFALL_CAP_NM)
      }
      rows.push(
        `${p.code}\t${p.name}\t${p.country}\t${p.lat},${p.lon}\t${r.nm.toFixed(2)} nm\t${r.moved ? 'moved' : 'ISLET'}`,
      )
    }
    console.log(
      `harbours ${PORTS.length} · in drawn water ${inWater} · moved onto the shore ${moved} (widest ${widestMove.toFixed(2)} nm) · islets ${islets} (nearest shore ${nearestIslet.toFixed(2)} nm)\n` +
        rows.join('\n'),
    )
    // MEASURED 2026-09-14 over data/world-110m.json at COASTLINE_TOLERANCE_DEG 0.2 and the 224
    // harbours of data/ports.json. These are pins of a measurement, not laws: a new harbour or a
    // new coast file moves them, and the move is made here, deliberately, with a date.
    expect(PORTS.length).toBe(224)
    expect(inWater).toBe(79)
    expect(moved).toBe(51)
    expect(islets).toBe(28)
    // The cap sits in the gap the measurement found: every coarseness move is under it, every
    // island the file lacks is over it. If either side crosses the cap, the cap is wrong — or a
    // harbour is — and this is where it is found.
    expect(widestMove).toBeLessThan(LANDFALL_CAP_NM)
    expect(nearestIslet).toBeGreaterThan(LANDFALL_CAP_NM)
  })

  test('landfallPorts: harbours move, sea places and roadsteads do not, identity is kept', () => {
    const served = mapPortsOf(REAL_PORTS)
    const landed = landfallPorts(served, COAST)
    expect(landed.ports).toHaveLength(served.length)
    let movedCount = 0
    for (let i = 0; i < served.length; i++) {
      const before = served[i]
      const after = landed.ports[i]
      expect(after.code).toBe(before.code)
      expect(after.roadstead).toEqual(before.roadstead)
      expect(after.roadsteadNm).toBe(before.roadsteadNm)
      if (before.kind === 'SEA_PLACE') expect(after).toBe(before)
      if (after !== before) {
        movedCount++
        expect(haversineNm(before, after)).toBeLessThanOrEqual(LANDFALL_CAP_NM + LANDFALL_INSET_DEG * 61)
        expect(onDrawnLand(COAST.rings, project(after))).toBe(true)
      } else if (before.kind === 'HARBOUR') {
        // Unmoved: either on drawn land already, or an islet.
        const at = project(before)
        expect(onDrawnLand(COAST.rings, at) || landed.islets.some((i) => i.x === at.x && i.y === at.y)).toBe(true)
      }
    }
    expect(movedCount).toBeGreaterThan(0)
    // Istanbul, the harbour the owner named: in drawn water at 110m (no Bosporus), moved.
    const ist = served.find((p) => p.code === 'IST')!
    const istAfter = landed.ports.find((p) => p.code === 'IST')!
    expect(onDrawnLand(COAST.rings, project(ist))).toBe(false)
    expect(onDrawnLand(COAST.rings, project(istAfter))).toBe(true)
    // With no coast, nothing moves and the list is the same object.
    expect(landfallPorts(served, null).ports).toBe(served)
    // With nothing to move, the list is the same object.
    expect(landfallPorts(landed.ports, COAST).ports).toBe(landed.ports)
  })
})

// ── THE RUNNING CHART ──────────────────────────────────────────────────────────────────────────

/** Every harbour mark on the sheet: its anchor in chart units, and whether the SVG says that point
 *  is inside the land body (evenodd, the body's own rule) or inside an islet. */
async function harboursOnLand(page: Page) {
  return page.evaluate((isletRadius) => {
    const svg = document.querySelector('[data-testid="map-chart"] svg') as SVGSVGElement | null
    const body = document.querySelector('[data-testid="map-coastline"]') as SVGGeometryElement | null
    if (!svg || !body) return null
    const islets = [...document.querySelectorAll('[data-testid="map-islets"] circle')].map((c) => ({
      x: Number(c.getAttribute('cx')),
      y: Number(c.getAttribute('cy')),
      r: Number(c.getAttribute('r')),
    }))
    const out: { code: string; x: number; y: number; land: boolean; islet: boolean }[] = []
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
      const land = body.isPointInFill(pt)
      const islet = islets.some((i) => Math.hypot(i.x - x, i.y - y) <= i.r)
      out.push({ code, x, y, land, islet })
    }
    return { marks: out, islets: islets.length, isletRadius }
  }, GLYPH.isletRadius)
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

    test('at the opening frame and at the world view, every harbour is on the body or on an islet', async ({
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
      const wetOpening = opening!.marks.filter((m) => !m.land && !m.islet).map((m) => m.code)
      console.log(`opening frame: ${opening!.marks.length} harbours drawn, ${wetOpening.length} in drawn water: ${wetOpening.join(' ')}`)

      // Out to the world, so every harbour is on the sheet and the check is the whole table.
      for (let i = 0; i < 12; i++) await page.getByRole('button', { name: 'Zoom out' }).click()
      await page.waitForTimeout(300)
      const world = await harboursOnLand(page)
      expect(world).not.toBeNull()
      const wet = world!.marks.filter((m) => !m.land && !m.islet).map((m) => m.code)
      console.log(
        `world view: ${world!.marks.length} harbours drawn, ${world!.islets} islets, ${wet.length} in drawn water: ${wet.join(' ')}`,
      )
      expect(wetOpening, 'harbours drawn in water at the opening frame').toEqual([])
      expect(wet, 'harbours drawn in water at the world view').toEqual([])
      // Row 93: at the world view EVERY harbour is on the sheet, so this was the whole table.
      expect(world!.marks.length).toBe(224)
    })
  })
}
