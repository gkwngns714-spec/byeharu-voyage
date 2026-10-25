// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE SHEET IS CONTINUOUS EAST–WEST — owner, 2026-10-14
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
//   *"right now the map is not continuous from left to right. i want it to be continuous."*
//
// The projection is periodic (src/lib/geo `sheetCopies`, `xOnSheet`), the view is no longer
// clamped east–west (`clampView`), and the chart draws its marks once per copy of the sheet a view
// touches, the coast as one <use> per copy, the names planned once over the whole glass. This file
// holds the arithmetic and then the glass:
//
//   UNIT     which copies a box touches; a point on some copy of a range; the centre wraps and the
//            latitude still clamps; `portMarks` lists a harbour whose copy is on the sheet; the hit
//            test measures the short way round; `shipMarks` culls, thins, and never thins yours;
//            a Pacific course's two pieces meet where the copies meet
//   BROWSER  pulled back and panned to put the antimeridian in the middle of the glass: two copies
//            on the sheet, land and harbours on BOTH sides, ships on both sides, a <use> of the
//            coast, and a tap on a harbour in the second copy selects that harbour

import { test, expect, type Page } from '@playwright/test'
import { mkdirSync } from 'node:fs'
import path from 'node:path'
import { PHONE, reachable, ready } from './appReady.fixture'
import { deriveWorld } from '../scripts/lib/world-derive.mjs'
import { serveNpcOn } from './npcOn.fixture'
import { CHART_WIDTH, project, sheetCopies, xOnSheet, type ViewBox } from '../src/lib/geo'
import {
  buildChartModel,
  clampView,
  GLYPH,
  hitTest,
  MAX_SPAN_X,
  minTierForSpan,
  panBy,
  portMarks,
  sheetPieces,
  SHIP_CELL_PX,
  shipMarks,
  viewBoxOf,
  visiblePorts,
  type MapFleet,
  type MapPort,
  type MapTraffic,
} from '../src/chart'

const SHOTS = path.resolve('docs', 'map-wrap-sun')

// ── UNIT: THE PERIODIC SHEET ───────────────────────────────────────────────────────────────────

test('sheetCopies: one copy inside the world, two across the seam, exactly one for the whole world', () => {
  expect(sheetCopies({ x: -20, width: 30 })).toEqual([0])
  expect(sheetCopies({ x: 170, width: 30 })).toEqual([0, 1])
  expect(sheetCopies({ x: -200, width: 30 })).toEqual([-1, 0])
  // The whole world from −180 to 180 is ONE copy — half-open, so no seam-column duplicate.
  expect(sheetCopies({ x: -180, width: 360 })).toEqual([0])
  // …and the whole world centred elsewhere is two, both of which it really does touch.
  expect(sheetCopies({ x: -100, width: 360 })).toEqual([0, 1])
  // Far off the base copy, the copies are the ones it touches, nothing else.
  expect(sheetCopies({ x: 700, width: 20 })).toEqual([2])
  // A degenerate box is the base copy, never nothing.
  expect(sheetCopies({ x: 0, width: 0 })).toEqual([0])
  expect(sheetCopies({ x: Number.NaN, width: 10 })).toEqual([0])
})

test('xOnSheet: a point is on a range when some copy of it is', () => {
  expect(xOnSheet(175, 170, 200)).toBe(true)
  expect(xOnSheet(-175, 170, 200)).toBe(true) // 185 on the next copy
  expect(xOnSheet(-150, 170, 200)).toBe(false) // 210 — past the range
  expect(xOnSheet(160, 170, 200)).toBe(false)
  expect(xOnSheet(5, -10, 10)).toBe(true)
  expect(xOnSheet(365, -10, 10)).toBe(true)
  // A range a whole turn wide holds everything.
  expect(xOnSheet(123.4, -180, 180)).toBe(true)
  expect(xOnSheet(123.4, 0, 400)).toBe(true)
})

test('the view centre wraps east–west and the latitude still clamps', () => {
  const aspect = 390 / 752
  // Panned past the antimeridian, the centre comes back on the next copy — the same place.
  expect(clampView({ cx: 190, cy: 0, spanX: 30 }, aspect).cx).toBeCloseTo(-170, 9)
  expect(clampView({ cx: -190, cy: 0, spanX: 30 }, aspect).cx).toBeCloseTo(170, 9)
  expect(clampView({ cx: 540, cy: 0, spanX: 30 }, aspect).cx).toBeCloseTo(-180, 9)
  // Nothing happens to a centre already in range, and NO east–west clamp at any span: the view
  // may be centred on 179° with a 30° span and run to 194°.
  expect(clampView({ cx: 179, cy: 0, spanX: 30 }, aspect).cx).toBe(179)
  // North–south the world still has an edge.
  const tall = clampView({ cx: 0, cy: -200, spanX: 30 }, aspect)
  expect(tall.cy).toBeGreaterThan(-90)
  // A pan of 20° east from 170° lands at −170°, with the span untouched.
  const panned = panBy({ cx: 170, cy: 0, spanX: 30 }, aspect, -20, 0)
  expect(panned.cx).toBeCloseTo(-170, 9)
  expect(panned.spanX).toBe(30)
  // The whole world is still the whole world.
  expect(clampView({ cx: 0, cy: 0, spanX: MAX_SPAN_X }, aspect).spanX).toBe(MAX_SPAN_X)
})

const port = (code: string, lat: number, lon: number, tier = 5): MapPort => ({
  code, name: code, country: '', lat, lon, sizeTier: tier, kind: 'HARBOUR', roadstead: { lat, lon }, roadsteadNm: 0,
})
const AUCKLAND = port('AUC', -36.84, 174.76)
const HONOLULU = port('HNL', 21.31, -157.86)
const LISBON = port('LIS', 38.7, -9.14)
const PORTS = [AUCKLAND, HONOLULU, LISBON]

test('portMarks lists a harbour whose copy is on the sheet, once, and the hit test reaches across the seam', () => {
  // A view from 160° to 220°: Auckland (175°E) and Honolulu (158°W, i.e. 202° on the next copy)
  // are both on it; Lisbon is not.
  const view: ViewBox = { x: 160, y: -40, width: 60, height: 100 }
  const marks = portMarks(PORTS, new Map(), view, minTierForSpan(view.width))
  expect(marks.map((m) => m.port.code).sort()).toEqual(['AUC', 'HNL'])
  expect(visiblePorts(PORTS, new Map(), view, minTierForSpan(view.width)).map((p) => p.code).sort()).toEqual(['AUC', 'HNL'])
  // The same two on the mirror view, from −200° to −140°.
  const mirror: ViewBox = { x: -200, y: -40, width: 60, height: 100 }
  expect(portMarks(PORTS, new Map(), mirror, 5).map((m) => m.port.code).sort()).toEqual(['AUC', 'HNL'])

  // THE HIT TEST: a tap just east of the seam, at −179.9°, is 5.3° from Auckland (174.76°) the
  // short way round and 358° the long way — so the reach of 10° finds her.
  const model = buildChartModel([], PORTS, [])
  const at = project({ lat: -36.84, lon: -179.9 })
  expect(hitTest(model, PORTS, at, 10)).toEqual({ kind: 'port', code: 'AUC' })
  // …and from the other side.
  expect(hitTest(model, PORTS, project({ lat: 21.31, lon: 179.5 }), 30)).toEqual({ kind: 'port', code: 'HNL' })
  expect(hitTest(model, PORTS, project({ lat: 0, lon: 0 }), 10)).toBeNull()
})

const sailing = (id: string, lat: number, lon: number, hulls: readonly ('barca' | 'carlat' | 'nau')[]): MapTraffic => ({
  kind: 'sailing',
  id,
  name: id,
  hulls: [...hulls],
  voyage: {
    course: [{ lat, lon }, { lat: lat + 1, lon: lon + 1 }],
    segIndex: 0,
    legFrac: 0,
    segNm: 100,
    at: { lat, lon },
    sailedNm: 0,
    totalNm: 100,
    etaMs: 1_000_000,
    departedMs: 0,
    destinationCode: null,
    destPoint: null,
    waters: [],
  },
  enduranceDays: 20,
  company: 'Casa', ink: 'prt', docked: false, berthCode: null, berthIndex: 0, nextLapAtMs: null, loop: null, lane: null,
})

const mine = (id: string, lat: number, lon: number): MapFleet => ({
  kind: 'anchored',
  id,
  name: id,
  hulls: ['carlat'],
  enduranceDays: 20,
  at: { lat, lon },
})

test('shipMarks culls to the view across the seam, thins the merchants to one per cell, and never thins yours', () => {
  const traffic = [
    sailing('a', 0, 179.5, ['barca']),
    sailing('b', 0, -179.5, ['nau']),
    sailing('c', 0, 179.52, ['barca']), // in a's cell at a wide zoom
    sailing('far', 0, 0, ['nau']),
  ]
  const fleets = [mine('own', 0, 179.51)]
  const model = buildChartModel(fleets, [], [], null, traffic)
  expect(model.traffic).toHaveLength(4)
  const view: ViewBox = { x: 170, y: -20, width: 20, height: 40 }
  // 1 °/px: a cell is SHIP_CELL_PX degrees — wide enough that a, c and the fleet of yours share one.
  const wide = shipMarks(model.fleets, model.traffic, view, 1)
  expect(wide.fleets.map((f) => f.fleet.id)).toEqual(['own'])
  // Yours is drawn; the merchants in her cell give way to her; the one across the seam is drawn;
  // the one at Greenwich is off the glass.
  expect(wide.traffic.map((t) => t.fleet.id).sort()).toEqual(['b'])
  // Close in (0.001 °/px) every ship on the glass is its own ship.
  const close = shipMarks(model.fleets, model.traffic, view, 0.001)
  expect(close.traffic.map((t) => t.fleet.id).sort()).toEqual(['a', 'b', 'c'])
  // Two merchants in one cell: the one with more hulls is kept, then the lower id.
  const two = [sailing('x', 10, 10, ['barca']), sailing('y', 10, 10.01, ['nau', 'nau'])]
  const m2 = buildChartModel([], [], [], null, two)
  expect(shipMarks([], m2.traffic, { x: 0, y: -20, width: 20, height: 40 }, 1).traffic.map((t) => t.fleet.id)).toEqual(['y'])
  const tie = [sailing('q', 10, 10, ['barca']), sailing('p', 10, 10.01, ['barca'])]
  const m3 = buildChartModel([], [], [], null, tie)
  expect(shipMarks([], m3.traffic, { x: 0, y: -20, width: 20, height: 40 }, 1).traffic.map((t) => t.fleet.id)).toEqual(['p'])
  // The cell is the largest hull bow to stern — one legible ship.
  expect(SHIP_CELL_PX).toBeCloseTo(2 * GLYPH.hullHalfLength[3], 9)
  // A docked fleet of yours is her port's mark, not a ship.
  const docked: MapFleet = { kind: 'docked', id: 'd', name: 'd', hulls: ['nau'], enduranceDays: 20, portCode: 'LIS' }
  const m4 = buildChartModel([docked], [LISBON], [])
  expect(shipMarks(m4.fleets, [], { x: -20, y: -50, width: 30, height: 30 }, 0.1).fleets).toEqual([])
})

test('a Pacific course is two pieces that meet at the seam latitude — the second copy closes the gap', () => {
  const TOKYO = { lat: 35.125, lon: 140.375 }
  const CALLAO = { lat: -12.125, lon: -77.375 }
  const pieces = sheetPieces([TOKYO, CALLAO])
  expect(pieces).toHaveLength(2)
  const off = pieces[0][pieces[0].length - 1]
  const on = pieces[1][0]
  expect(off.x).toBe(180)
  expect(on.x).toBe(-180)
  expect(off.y).toBeCloseTo(on.y, 9)
  // Drawn in copies 0 and 1, the two ends are the same point on the glass.
  expect(on.x + CHART_WIDTH).toBe(off.x)
  // And the whole course, both pieces, is on a view centred on the seam.
  const view = viewBoxOf({ cx: 180, cy: -10, spanX: 120 }, 1.6)
  expect(sheetCopies(view)).toEqual([0, 1])
})

// ── THE GLASS ──────────────────────────────────────────────────────────────────────────────────

async function wrapOnTheGlass(page: Page) {
  return page.evaluate(() => {
    const chart = document.querySelector('[data-testid="map-chart"]')
    const root = chart?.querySelector('[data-sheet-copies]')
    const svg = chart?.querySelector('[data-testid="map-view"]')
    // Null-safe: before the world has opened there is no chart, and the poll reads an empty sheet.
    if (!chart || !root || !svg) {
      return { viewX: Number.NaN, spanDeg: Number.NaN, copies: [] as number[], perCopy: [] as { k: number; ports: number; ships: number }[], coastBodies: 0, coastUses: 0, dayCoastUses: 0, labels: 0 }
    }
    const [x, , w] = svg.getAttribute('viewBox')!.split(/\s+/).map(Number)
    const copies = (root.getAttribute('data-sheet-copies') ?? '').split(' ').map(Number)
    // THE MARKS' group for the copy — not the coast sheets', which carry the same attribute and come
    // first in the DOM (the night one, and since 2026-10-18 the day one beside it).
    const perCopy = copies.map((k) => {
      const g = [...chart.querySelectorAll(`svg g[data-sheet-copy="${k}"]`)].find((el) => !el.closest('[data-testid="map-coast-sheet"], [data-testid="map-coast-sheet-day"]'))
      return {
        k,
        ports: g ? g.querySelectorAll('[data-port-code]').length : 0,
        ships: g ? g.querySelectorAll('[data-testid="map-merchant"], [data-testid="map-ship"]').length : 0,
      }
    })
    const sheet = document.querySelector('[data-testid="map-coast-sheet"]')!
    return {
      viewX: x,
      spanDeg: w,
      copies,
      perCopy,
      coastBodies: sheet.querySelectorAll('[data-testid="map-coastline"]').length,
      // The night coast's own <use>s: the day coast is a second picture with its own copies, counted
      // apart — since 2026-10-18 on a sheet of its own beside this one, under a mask of the glass
      // (src/chart/ChartCanvas.tsx, CoastSheet).
      coastUses: sheet.querySelectorAll(':scope > svg use[data-sheet-copy]').length,
      dayCoastUses: document.querySelectorAll('[data-testid="map-coast-sheet-day"] use[data-sheet-copy]').length,
      labels: document.querySelectorAll('[data-testid="map-labels"] text').length,
    }
  })
}

/** Where a harbour's mark is on the glass, in client pixels — from the SECOND copy's group. A full
 *  mark if the span draws one there, else a dot (row 104: a dot answers a tap too, at half a touch);
 *  the mark's own core element is what is measured, so the tap lands on the harbour and not on its
 *  light's bloom. */
async function markOnGlass(page: Page, k: number) {
  return page.evaluate((copy) => {
    const chart = document.querySelector('[data-testid="map-chart"]')!.getBoundingClientRect()
    const marks = [...document.querySelectorAll(`[data-testid="map-chart"] svg g[data-sheet-copy="${copy}"] [data-port-code]`)].filter(
      (el) => !el.closest('[data-testid="map-coast-sheet"], [data-testid="map-coast-sheet-day"]'),
    )
    const onGlass = marks
      .map((g) => {
        const core = g.getAttribute('data-port-mark') === 'full' ? g.querySelector('path') : g.querySelector('circle:last-of-type')
        const r = core!.getBoundingClientRect()
        return { code: g.getAttribute('data-port-code')!, full: g.getAttribute('data-port-mark') === 'full', x: r.left + r.width / 2, y: r.top + r.height / 2 }
      })
      .filter((m) => m.x > chart.left + 80 && m.x < chart.right - 80 && m.y > chart.top + 80 && m.y < chart.bottom - 80)
    return onGlass.find((m) => m.full) ?? onGlass[0] ?? null
  }, k)
}

test('panned across the antimeridian, the sheet continues: land, harbours and ships on both sides, and a tap works there', async ({
  page,
  request,
  baseURL,
}) => {
  test.setTimeout(1_200_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  mkdirSync(SHOTS, { recursive: true })
  await serveNpcOn(page)
  await page.setViewportSize({ width: 1440, height: 900 })
  await page.goto('map')
  await ready(page)
  await expect.poll(async () => (await wrapOnTheGlass(page)).perCopy[0]?.ships ?? 0, { timeout: 180_000 }).toBeGreaterThanOrEqual(1)

  // Pull back to a sea-wide span, then DRAG the sheet west until the antimeridian is in the middle
  // of the glass — a real pan, through the one gesture surface.
  // TO A SEA-WIDE SPAN THE SPEC SETS ITSELF, not "five presses out from wherever the chart
  // opened". The opening frame is fitted to the house's fleets AND the traffic in motion
  // (chartView.ts `openingBounds`), so it is the world's to decide: on CI's merchants-on world
  // (run 38728407504) five presses ran into the globe (360°), where every harbour is a nameless dot
  // and the tap below fell on a merchant leaving Acapulco instead — measured locally the same way,
  // a hull 2.8 px from the dot. 120°–200° is the sea-wide span this test was written for (five
  // presses from the opening of a fresh house land at ~156°).
  const out = page.getByLabel('Zoom out')
  const zoomIn = page.getByLabel('Zoom in')
  for (let i = 0; i < 12; i++) {
    const { spanDeg } = await wrapOnTheGlass(page)
    if (spanDeg < 120) await out.click()
    else if (spanDeg > 200) await zoomIn.click()
    else break
    await page.waitForTimeout(400)
  }
  {
    const { spanDeg } = await wrapOnTheGlass(page)
    expect(spanDeg, 'the drive did not reach a sea-wide span').toBeGreaterThanOrEqual(120)
    expect(spanDeg).toBeLessThanOrEqual(200)
  }
  const chart = (await page.locator('[data-testid="map-chart"]').boundingBox())!
  const centre = { x: chart.x + chart.width / 2, y: chart.y + chart.height / 2 }
  // Each drag moves the paper by half the glass. The view opens on Iberia (−9°); the seam is 189°
  // east of it, so drag the paper WEST (view moves east) until the view's centre sits on it.
  for (let guard = 0; guard < 40; guard++) {
    const { viewX, spanDeg } = await wrapOnTheGlass(page)
    const cx = viewX + spanDeg / 2
    const want = 180
    const delta = ((want - cx + 540) % 360) - 180 // the short way, in degrees
    if (Math.abs(delta) < spanDeg * 0.05) break
    const stepDeg = Math.sign(delta) * Math.min(Math.abs(delta), spanDeg * 0.4)
    const stepPx = (stepDeg / spanDeg) * chart.width
    await page.mouse.move(centre.x, centre.y)
    await page.mouse.down()
    await page.mouse.move(centre.x - stepPx / 2, centre.y, { steps: 4 })
    await page.mouse.move(centre.x - stepPx, centre.y, { steps: 4 })
    await page.mouse.up()
    await page.waitForTimeout(80)
  }
  await page.waitForTimeout(600)
  const across = await wrapOnTheGlass(page)
  // THE SEAM IS ON THE GLASS and both copies are drawn.
  expect(across.copies).toEqual([0, 1])
  expect(across.viewX).toBeLessThan(180)
  expect(across.viewX + across.spanDeg).toBeGreaterThan(180)
  // LAND ON BOTH SIDES: one body drawn, one <use> of it, so the coast continues past 180°.
  expect(across.coastBodies).toBe(1)
  expect(across.coastUses).toBe(1)
  expect(across.dayCoastUses, 'the day coast continues past 180° the same way').toBe(1)
  // HARBOURS on both sides of the seam (New Zealand and Japan west of it; Hawaii and the Americas
  // east), and SHIPS on both sides — the Pacific is sailed.
  for (const c of across.perCopy) {
    expect(c.ports, `copy ${c.k} harbours`).toBeGreaterThan(0)
  }
  expect(across.perCopy.reduce((n, c) => n + c.ships, 0)).toBeGreaterThanOrEqual(2)
  expect(across.labels).toBeGreaterThan(0)
  console.log(
    `across the seam at ${across.spanDeg.toFixed(1)}° from x=${across.viewX.toFixed(1)}: ` +
      across.perCopy.map((c) => `copy ${c.k}: ${c.ports} harbours, ${c.ships} ships`).join(' · ') +
      `; coast bodies ${across.coastBodies}, uses ${across.coastUses}, names ${across.labels}`,
  )
  await page.screenshot({ path: path.join(SHOTS, 'pacific-1440.png') })

  // A TAP ON A HARBOUR IN THE SECOND COPY SELECTS THAT HARBOUR — the hit test reaches across. The
  // detail tray opens on the harbour's own name (the real port table says which name that is).
  const mark = await markOnGlass(page, 1)
  expect(mark, 'a harbour mark in the second copy, on the glass').not.toBeNull()
  // The name comes from the ONE derivation of the served world (scripts/lib/world-derive.mjs, which the
  // world guard holds the database equal to), not from tests/mapWorld.fixture.ts: that table is a frozen
  // 214-harbour measurement and never carried the 0090 or 0217 harbours. CI run 40197017998 tapped
  // Astoria (0217) here and the frozen table had no name for it.
  const named = deriveWorld().ports.find((p: { code: string }) => p.code === mark!.code)
  expect(named, `${mark!.code} is in the derived world`).toBeDefined()
  await page.mouse.click(mark!.x, mark!.y)
  const tray = page.getByTestId('map-detail-tray')
  await expect(tray).toBeVisible({ timeout: 10_000 })
  await expect(tray).toContainText(named!.name)
  console.log(`tapped ${mark!.code} (${named!.name}) in copy 1 at ${mark!.x.toFixed(0)},${mark!.y.toFixed(0)} — ${mark!.full ? 'a full mark' : 'a dot'}`)
  await page.getByTestId('tray-close').first().click()

  // THE PHONE, the same water.
  await page.setViewportSize(PHONE)
  await page.waitForTimeout(600)
  const phone = await wrapOnTheGlass(page)
  expect(phone.copies.length).toBeGreaterThanOrEqual(1)
  expect(phone.perCopy.reduce((n, c) => n + c.ports, 0)).toBeGreaterThan(0)
  await page.screenshot({ path: path.join(SHOTS, 'pacific-390.png') })
})
