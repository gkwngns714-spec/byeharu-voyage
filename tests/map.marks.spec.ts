import { test, expect, type Page } from '@playwright/test'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import type { ViewBox } from '../src/lib/geo'
import { buildChartModel, buildCoastline, mapFleetsOf, mapPortsOf, minTierForSpan, portMarks, visiblePorts, dotPorts } from '../src/chart'
import { REAL_PORTS, dockedFleet } from './mapWorld.fixture'
import { ready, reachable, zoomStepMs } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// EVERY HARBOUR ON THE SHEET — owner row 94 (2026-09-14): "i want to see all the countries, all
// the ports in the game when i zoom out, it can be a dot, then once zoomed in i will be able to
// see the marker".
//
// Pure: `portMarks` puts every port on the glass on the sheet, FULL or DOT by the tier bands that
// were already the zoom ladder; `visiblePorts` is its full half and keeps its pins; a port of
// yours is full at every zoom; the hit test reads the full half (a dot is not a target — the
// first run with tappable dots opened Sanlúcar for a tap on the word "Cadiz"). The countries: the body is every kept ring of the file, at every
// zoom — there is no culling to prove absent, only the count of countries the body carries.
//
// Browser: at the world view all 246 harbours (224 until 0090, 238 until 0217) are in the DOM — 248 marks, Auckland and Wellington drawn in both copies of the sheet at the seam — (dots and full marks together), and
// zoomed in on a harbour that was a dot it wears its full mark; both glasses, both schemes; the
// frame cost of a zoom step at the world view with every dot on the sheet, printed.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const PORTS = mapPortsOf(REAL_PORTS)
const HARBOURS = PORTS.filter((p) => p.kind === 'HARBOUR').length
const WORLD: ViewBox = { x: -180, y: -90, width: 360, height: 180 }

test.describe('every port is on the sheet; the zoom decides dot or mark', () => {
  test('at the world view every harbour is drawn, 35 of them full; on a coast every one is full', () => {
    const none = new Map()
    const world = portMarks(PORTS, none, WORLD, minTierForSpan(WORLD.width))
    expect(world).toHaveLength(HARBOURS)
    expect(world.filter((m) => m.full)).toHaveLength(35)
    expect(world.filter((m) => !m.full)).toHaveLength(HARBOURS - 35)
    // The full half IS `visiblePorts` — the list the label planner, the roads and the hit test read.
    expect(visiblePorts(PORTS, none, WORLD, minTierForSpan(WORLD.width)).map((p) => p.code)).toEqual(
      world.filter((m) => m.full).map((m) => m.port.code),
    )
    // A sea's width: the middling ports join the full marks; the small ones stay dots.
    const sea = portMarks(PORTS, none, WORLD, minTierForSpan(40))
    expect(sea.filter((m) => m.full)).toHaveLength(35 + 79)
    // A coast: everything is a full mark, and nothing is a dot.
    const coast = portMarks(PORTS, none, WORLD, minTierForSpan(10))
    expect(coast.every((m) => m.full)).toBe(true)
  })

  test('a port of yours wears its full mark at every zoom, whatever its size', () => {
    const model = buildChartModel(mapFleetsOf([dockedFleet('g', 'Gaivota', 'VIS')]), PORTS)
    const world = portMarks(PORTS, model.portRoles, WORLD, minTierForSpan(WORLD.width))
    const visby = world.find((m) => m.port.code === 'VIS')!
    expect(visby.port.sizeTier).toBeLessThan(5)
    expect(visby.full).toBe(true)
  })

  test('a dot answers a tap SECOND: the Map tab hit-tests the full half first, then the dots at their own reach', () => {
    // MEASURED 2026-09-14: with `portMarks` in ONE hit test, a tap on the word "Cadiz" at the
    // phone's opening frame opened Sanlúcar — a tier-2 dot 5 px away (tests/map.sendfleet.spec.ts).
    // Row 104 (2026-09-18): a dot is the city it stands for, but only behind the names — the two
    // halves are both derived from `portMarks` and handed to hitTest in that order.
    const screen = readFileSync(path.join(process.cwd(), 'src', 'features', 'map', 'MapScreen.tsx'), 'utf8')
    expect(screen).toMatch(/const tappable = visiblePorts\(ports, model\.portRoles, view, minTier\)/)
    expect(screen).toMatch(/const dots = dotPorts\(ports, model\.portRoles, view, minTier\)/)
    // …and, since 2026-10-14, the merchants the sheet actually DREW (shipMarks' thinning), then — since
    // 2026-10-18 (#234, src/chart/placedNames.ts) — the harbour NAMES as drawn, which hitTest asks before
    // any reach is weighed. A name box is a full mark's own name, so a dot still answers second.
    expect(screen).toMatch(
      /hitTest\(model, tappable, at, GLYPH\.hitRadius \* unitsPerPx, dots, GLYPH\.dotHitRadius \* unitsPerPx, drawn\.traffic, placedNames\(\)\)/,
    )
    expect(screen).toMatch(/const drawn = shipMarks\(model\.fleets, model\.traffic, view, unitsPerPx\)/)
    expect(screen).not.toContain('portMarks(')
    // The two halves partition the sheet: no harbour in both, none in neither.
    const roles = buildChartModel(mapFleetsOf([]), PORTS).portRoles
    const full = visiblePorts(PORTS, roles, WORLD, minTierForSpan(WORLD.width)).map((p) => p.code)
    const dots = dotPorts(PORTS, roles, WORLD, minTierForSpan(WORLD.width)).map((p) => p.code)
    expect(full.filter((c) => dots.includes(c))).toEqual([])
    expect(full.length + dots.length).toBe(portMarks(PORTS, roles, WORLD, minTierForSpan(WORLD.width)).length)
  })

  test('only what is on the glass: a port off the sheet is neither dot nor mark', () => {
    const iberia: ViewBox = { x: -12, y: -45, width: 12, height: 10 }
    const marks = portMarks(PORTS, new Map(), iberia, minTierForSpan(iberia.width))
    expect(marks.map((m) => m.port.code)).toContain('LIS')
    expect(marks.map((m) => m.port.code)).not.toContain('NAG')
  })

  test('every country the file has a ring for is in the body at every zoom — there is no culling', () => {
    const world = JSON.parse(readFileSync(path.join(process.cwd(), 'data', 'world-110m.json'), 'utf8'))
    const coast = buildCoastline(world)
    const codes = new Set(
      (world.features as { properties: { ISO_A2_EH: string } }[]).map((f) => f.properties.ISO_A2_EH).filter((c) => /^[A-Z]{2}$/.test(c)),
    )
    // MEASURED 2026-09-14: 177 features, 175 with a two-letter code; every one of them keeps at
    // least one ring above COASTLINE_MIN_SPAN_DEG, so every country is in the one body path.
    expect(codes.size).toBe(175)
    expect(coast.countries.map((c) => c.iso).sort()).toEqual([...codes].sort())
    // …and the layer draws that one path whole: no per-zoom subset exists anywhere in the section.
    const layer = readFileSync(path.join(process.cwd(), 'src', 'chart', 'CoastlineLayer.tsx'), 'utf8')
    expect(layer).toContain('<path d={d} fillRule="evenodd" className="fill-chart-land" data-testid="map-coastline" />')
  })
})

// ── THE RUNNING CHART ──────────────────────────────────────────────────────────────────────────

async function marksOnSheet(page: Page) {
  return page.evaluate(() => {
    const groups = [...document.querySelectorAll('[data-testid="map-ports"] [data-port-code]')]
    const harbours = groups.filter((g) => g.getAttribute('data-port-kind') === 'HARBOUR')
    return {
      harbours: harbours.length,
      codes: harbours.map((g) => g.getAttribute('data-port-code') ?? ''),
      dots: harbours.filter((g) => g.getAttribute('data-port-mark') === 'dot').length,
      full: harbours.filter((g) => g.getAttribute('data-port-mark') === 'full').length,
      firstDot: harbours.find((g) => g.getAttribute('data-port-mark') === 'dot')?.getAttribute('data-port-code') ?? null,
      names: document.querySelectorAll('[data-testid="map-labels"] text').length,
      coastBytes: document.querySelector('[data-testid="map-coastline"]')?.getAttribute('d')?.length ?? 0,
    }
  })
}


for (const scheme of ['dark', 'light'] as const) {
  for (const viewport of [
    { width: 390, height: 844 },
    { width: 1440, height: 900 },
  ]) {
    test.describe(`all 246 harbours at the world view — ${scheme}, ${viewport.width}×${viewport.height}`, () => {
      test.use({ viewport, colorScheme: scheme })

      test('246 marks at the world view, and a dot becomes its full marker on the way in', async ({
        page,
        request,
        baseURL,
      }) => {
        test.setTimeout(420_000)
        test.skip(
          !(await reachable(request, baseURL ?? '')),
          `nothing served at ${baseURL} — run \`npm run build && npm run preview\` and re-run.`,
        )
        await page.goto('map')
        await ready(page)
        await page.waitForFunction(
          () => (document.querySelector('[data-testid="map-coastline"]')?.getAttribute('d') ?? '').length > 1000,
          undefined,
          { timeout: 60_000 },
        )
        const opening = await marksOnSheet(page)

        for (let i = 0; i < 12; i++) await page.getByRole('button', { name: 'Zoom out' }).click()
        await page.waitForTimeout(300)
        const world = await marksOnSheet(page)
        // Moved deliberately 2026-09-14: 224 → 238 harbours (the Pacific Americas growth, 0090);
        // the 35 great harbours are unchanged — every new one is mid or small.
        //
        // AND MOVED AGAIN 2026-10-12, owner row 125: at the world view NOT ONE harbour draws its
        // mark. This spec's own claim — THE CLAIM IT WAS WRITTEN FOR — is untouched and is the
        // line above and the two below: every harbour is on the sheet at every zoom, there is no
        // culling, and a dot becomes its full marker on the way in (asserted further down, where
        // it always was). What changed is WHICH RENDERING the widest band uses. `PORT_TIER_BANDS`
        // kept the 35 great ports as triangles longest, which is right on a working chart; past
        // the rung where the fleets have already given up their hulls it left 35 little outlines
        // sitting on top of 35 blooms, and the owner's answer to that sheet was *"i told you to
        // show in lights"*. They were right: it is a hybrid, and it fights the one thing that band
        // exists to show. ./src/chart/PortsLayer.tsx renders every harbour as its dot past
        // `DOT_SPAN_DEG` — a lamp on the night side of the terminator, a dark point by day
        // (2026-10-14, src/chart/sun.ts); the ships, since that date, stay hulls at every span.
        // Moved deliberately 2026-10-25: 238 → 246 harbours (the far-north, Australasian and
        // northern-US growth, 0217, owner row 186); every new one is small.
        // AND THE CLAIM IS NOW COUNTED BY HARBOUR, NOT BY MARK (2026-10-25). Since 2026-10-14 the sheet
        // repeats (src/chart/ChartCanvas.tsx, THE COPIES): the world view's box runs past ±180° and a
        // harbour is drawn once in every copy whose window holds it. Until 0217 no harbour stood near
        // enough to the seam for that to show; Auckland (174.76° E) and Wellington (174.78° E) do, and
        // CI measured 248 marks for 246 harbours (run 40195840956, all four schemes and sizes). So:
        // every harbour is on the sheet (246 distinct codes), the sheet draws 248 marks, and the two
        // drawn twice are exactly the two at the seam — a third would be a duplicate, not a copy.
        const distinct = new Set(world.codes)
        const twice = [...distinct].filter((c) => world.codes.filter((x) => x === c).length > 1).sort()
        expect(distinct.size, 'every harbour is on the sheet at the world view').toBe(246)
        expect(world.harbours, 'one mark per harbour per copy of the sheet').toBe(248)
        expect(twice, 'the harbours drawn in both copies are the two at the seam').toEqual(['AUK', 'WLG'])
        expect(world.full, 'past the dot rung a city is its dot and nothing else').toBe(0)
        expect(world.dots).toBe(248)
        // The whole body is drawn at the world view — the same path as at the opening frame.
        expect(world.coastBytes).toBe(opening.coastBytes)
        expect(world.coastBytes).toBeGreaterThan(70_000)
        const cost = await zoomStepMs(page)
        console.log(
          `${scheme} ${viewport.width}×${viewport.height}: opening ${opening.harbours} harbours (${opening.full} full, ${opening.dots} dots, ${opening.names} names); ` +
            `world ${world.harbours} (${world.full} full, ${world.dots} dots, ${world.names} names); zoom step at the world view ${cost.toFixed(1)} ms`,
        )

        // Zoom in on a dot until it wears its full marker: the dot is the same harbour.
        for (let i = 0; i < 12; i++) await page.getByRole('button', { name: 'Zoom out' }).click()
        const code = (await marksOnSheet(page)).firstDot
        expect(code).not.toBeNull()
        const at = await page.evaluate((c) => {
          const g = document.querySelector(`[data-port-code="${c}"]`)!
          return { x: Number(g.getAttribute('data-port-x')), y: Number(g.getAttribute('data-port-y')) }
        }, code)
        // Wheel-zoom about the dot, re-aiming every step: on a wide glass the world view is
        // letterboxed and `clampView` re-centres the first steps, so the point under the pointer
        // moves until the frame fits inside the world — re-reading where the mark is keeps the
        // pointer on it, which is what a player's eye does.
        const box = (await page.locator('[data-testid="map-chart"]').boundingBox())!
        for (let i = 0; i < 40; i++) {
          const svgBox = await page.evaluate(() => {
            const svg = document.querySelector('[data-testid="map-view"]')!
            const [x, y, w, h] = svg.getAttribute('viewBox')!.split(' ').map(Number)
            return { x, y, w, h }
          })
          const px = box.x + ((at.x - svgBox.x) / svgBox.w) * box.width
          const py = box.y + ((at.y - svgBox.y) / svgBox.h) * box.height
          await page.mouse.move(px, py)
          await page.mouse.wheel(0, -120)
          await page.waitForTimeout(30)
        }
        await page.waitForTimeout(300)
        const mark = await page.evaluate((c) => document.querySelector(`[data-port-code="${c}"]`)?.getAttribute('data-port-mark') ?? null, code)
        expect(mark, `${code} zoomed in`).toBe('full')
      })
    })
  }
}
