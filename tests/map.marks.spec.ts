import { test, expect, type Page } from '@playwright/test'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import type { ViewBox } from '../src/lib/geo'
import { buildChartModel, buildCoastline, mapFleetsOf, mapPortsOf, minTierForSpan, portMarks, visiblePorts } from '../src/chart'
import { REAL_PORTS, dockedFleet } from './mapWorld.fixture'
import { ready, reachable, zoomStepMs } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// EVERY HARBOUR ON THE SHEET — owner row 93 (2026-09-14): "i want to see all the countries, all
// the ports in the game when i zoom out, it can be a dot, then once zoomed in i will be able to
// see the marker".
//
// Pure: `portMarks` puts every port on the glass on the sheet, FULL or DOT by the tier bands that
// were already the zoom ladder; `visiblePorts` is its full half and keeps its pins; a port of
// yours is full at every zoom; the hit test reads the full half (a dot is not a target — the
// first run with tappable dots opened Sanlúcar for a tap on the word "Cadiz"). The countries: the body is every kept ring of the file, at every
// zoom — there is no culling to prove absent, only the count of countries the body carries.
//
// Browser: at the world view 224 harbour marks are in the DOM (dots and full marks together), and
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

  test('a dot is a picture, not a target: the Map tab hit-tests the full half', () => {
    // MEASURED 2026-09-14: with `portMarks` in the hit test, a tap on the word "Cadiz" at the
    // phone's opening frame opened Sanlúcar — a tier-2 dot 5 px away (tests/map.sendfleet.spec.ts).
    const screen = readFileSync(path.join(process.cwd(), 'src', 'features', 'map', 'MapScreen.tsx'), 'utf8')
    expect(screen).toMatch(/const tappable = visiblePorts\(ports, model\.portRoles, view, minTierForSpan\(view\.width\)\)/)
    expect(screen).not.toContain('portMarks(')
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
    test.describe(`all 224 harbours at the world view — ${scheme}, ${viewport.width}×${viewport.height}`, () => {
      test.use({ viewport, colorScheme: scheme })

      test('224 marks at the world view, and a dot becomes its full marker on the way in', async ({
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
        expect(world.harbours, 'every harbour is on the sheet at the world view').toBe(224)
        expect(world.full).toBe(35)
        expect(world.dots).toBe(224 - 35)
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
            const svg = document.querySelector('[data-testid="map-chart"] svg')!
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
