import { test, expect } from '@playwright/test'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import { project, type ViewBox } from '../src/lib/geo'
import {
  GLYPH,
  MAX_SPAN_X,
  MIN_SPAN_X,
  OPENING_MIN_SPAN_DEG,
  mapPortsOf,
  minTierForSpan,
  roadsteadMarks,
  toPolylineD,
  visiblePorts,
  type MapPort,
} from '../src/chart'
import { REAL_PORTS } from './mapWorld.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE ROADSTEAD — the one point of open water a port is reached from, DRAWN (0076)
//
// The owner, OWNER_REQUESTS row 72: *"create a perpendicular helper line (dotted) that is the
// shortest point between the land city and nearby shore - sea. Then create a point there, and when
// the ship arrive at that point, consider it as the ship have landed on land."*
//
// WHAT THIS FILE PROVES, and every one of its controls was WATCHED going red before it was
// trusted (docs/NO_SPAGHETTI.md §7, docs/SECTIONS.md:8-9):
//
//   · the line drawn is exactly quay → the SERVED roads, through the chart's one path builder;
//   · a port that stands on its own water draws NOTHING, and that decision is made from the
//     served `roadsteadNm` rather than from a client comparison of two floats (§7C);
//   · below `GLYPH.roadsteadMinPx` of drawn separation nothing is drawn, and the ramp across the
//     three zooms this chart actually has is MEASURED here rather than asserted as a shape;
//   · a culled port draws no roads — the set is `visiblePorts`, the same list PortsLayer is handed;
//   · the layer is furniture: `ChartCanvas` composes it between the tracks and the ports, it
//     borrows the water-ahead dash, and it is exported to nobody (tests/sections.spec.ts holds the
//     last half).
//
// PURE NODE. No `page` fixture, so no browser is launched — and no component is rendered, because
// this harness cannot render one (tests/waters.panel.spec.ts:19-22 measured it). The DECISION is
// data (src/chart/roadsteads.ts) and the data is what is proved; the two facts that live only in
// the markup — the dash and the paint order — are read off disk, the way tests/sections.spec.ts
// reads the import graph.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const PORTS: readonly MapPort[] = mapPortsOf(REAL_PORTS)
const at = (code: string): MapPort => {
  const p = PORTS.find((q) => q.code === code)
  if (!p) throw new Error(`fixture: no port ${code}`)
  return p
}

/** Amsterdam: the worst-snapping harbour in the seeded world's north-west, 35.47 nm off her quay
 *  (measured by 0076's generator; the figure is in the migration and in the fixture). */
const AMS = at('AMS')
/** Bristol: her own cell is sailable water since the Severn channel opened in 0052, so she IS her
 *  own roadstead at 0.00 nm — the §2.4 rule, and 55 of the fixture's 214 harbours are like her. */
const BRS = at('BRS')

/** Chart units per CSS pixel at a given span, on the 390 px phone every rule here is sized for. */
const PHONE_PX = 390
const unitsPerPxAt = (spanDeg: number) => spanDeg / PHONE_PX

/** The drawn separation of a port's roads from its quay, in chart units. */
const separationOf = (p: MapPort) =>
  Math.hypot(project(p.roadstead).x - project(p).x, project(p.roadstead).y - project(p).y)

test.describe('the line drawn is the served point, and nothing else', () => {
  test('quay → roads, through the one path builder, with the circle standing on the roads', () => {
    const marks = roadsteadMarks([AMS], unitsPerPxAt(MIN_SPAN_X))
    expect(marks).toHaveLength(1)
    // EXACT, not "close to": the chart copies the served coordinate and never re-derives it.
    expect(marks[0].lineD).toBe(toPolylineD([project(AMS), project(AMS.roadstead)]))
    expect(marks[0].at).toEqual(project(AMS.roadstead))
    expect(marks[0].code).toBe('AMS')
    expect(marks[0].nm).toBe(35.47)
    // …and the served roads are NOT the quay, or the line above would be a line to itself and
    // every assertion in this file would pass over nothing.
    expect(AMS.roadstead).not.toEqual({ lat: AMS.lat, lon: AMS.lon })
    expect(AMS.roadsteadNm).toBeGreaterThan(20)
  })

  test('a port that stands on its own water draws nothing — a zero-length line is not a line', () => {
    expect(BRS.roadsteadNm).toBe(0)
    expect(BRS.roadstead).toEqual({ lat: BRS.lat, lon: BRS.lon })
    expect(roadsteadMarks([BRS], unitsPerPxAt(MIN_SPAN_X))).toEqual([])
  })

  test('the SERVED number decides, never a comparison of two floats', () => {
    // Amsterdam's roads are 35 nm away and would draw at this zoom — but the server says the
    // distance is zero, and the served number is the authority. A layer that compared the two
    // coordinates instead would draw this one, and would then disagree with the server about a
    // port whose roadstead the raster moved.
    const served0: MapPort = { ...AMS, roadsteadNm: 0 }
    expect(roadsteadMarks([served0], unitsPerPxAt(MIN_SPAN_X))).toEqual([])
  })
})

test.describe('zoom is the precision control', () => {
  const AMS_SEPARATION = separationOf(AMS)
  /** The exact zoom at which Amsterdam's roads are `roadsteadMinPx` from her quay. */
  const EDGE = AMS_SEPARATION / GLYPH.roadsteadMinPx

  test('one notch inside the threshold draws, one notch outside draws nothing', () => {
    expect(roadsteadMarks([AMS], EDGE * 0.999)).toHaveLength(1)
    expect(roadsteadMarks([AMS], EDGE * 1.001)).toHaveLength(0)
  })

  test('the ramp across the three zooms this chart has, measured', () => {
    // Not a shape — the three numbers were taken off this fixture on 2026-09-04. 159 of the 214
    // harbours carry roads off the quay; at the whole world in one frame NONE of them is longer
    // than the smallest mark the chart draws, and at the tightest zoom every one is.
    const drawnAt = (spanDeg: number) => roadsteadMarks(PORTS, unitsPerPxAt(spanDeg)).length
    expect(PORTS.filter((p) => p.roadsteadNm > 0)).toHaveLength(159)
    expect(drawnAt(MAX_SPAN_X)).toBe(0)
    expect(drawnAt(OPENING_MIN_SPAN_DEG)).toBe(132)
    expect(drawnAt(MIN_SPAN_X)).toBe(159)
  })

  test('the threshold is the smallest mark this chart draws, and it is stated in pixels', () => {
    // 6 px = 2 × loudPortHalfWidth × portMarkScale(1) — the width of the smallest LOUD port mark.
    // A helper line shorter than a port mark is noise. It is a rule about the PICTURE, so it is in
    // pixels: on this equirectangular sheet a degree is a degree everywhere, which means the same
    // nautical mile buys more line the further from the equator a harbour lies. At the opening
    // frame (12° across a 390 px phone) 6 px is 0.185° — 11.1 nm at the equator, and under 6 nm
    // in the Baltic. That is the honest description of the rule; a distance threshold would be a
    // different rule and would draw lines shorter than the marks they leave.
    expect(GLYPH.roadsteadMinPx).toBeCloseTo(6, 9)
    expect(unitsPerPxAt(OPENING_MIN_SPAN_DEG) * GLYPH.roadsteadMinPx * 60).toBeCloseTo(11.08, 2)
  })
})

test.describe('the roads are drawn for the ports that are on the paper', () => {
  /** Iberia at a working zoom — the frame the §K.1 opening house sails out of. */
  const BOX: ViewBox = { x: -12, y: -44, width: 10, height: 10 }

  test('a culled port draws no roads', () => {
    const upp = unitsPerPxAt(BOX.width)
    const drawn = visiblePorts(PORTS, new Map(), BOX, minTierForSpan(BOX.width))
    const onPaper = roadsteadMarks(drawn, upp).map((m) => m.code)
    const wholeTable = roadsteadMarks(PORTS, upp).map((m) => m.code)

    expect(onPaper.length).toBeGreaterThan(0)
    expect(wholeTable.length).toBeGreaterThan(onPaper.length)
    // Every port that shows its roads is a port that was drawn…
    const visibleCodes = new Set(drawn.map((p) => p.code))
    for (const code of onPaper) expect(visibleCodes.has(code), `${code} is not on the paper`).toBe(true)
    // …and Amsterdam, which is off this frame entirely, shows none.
    expect(wholeTable).toContain('AMS')
    expect(onPaper).not.toContain('AMS')
  })
})

test.describe('the layer is furniture, and it says so in the file', () => {
  const SRC = path.resolve(process.cwd(), 'src', 'chart')
  const read = (name: string) => readFileSync(path.join(SRC, name), 'utf8')

  test('it borrows the water-ahead dash and invents none', () => {
    const layer = read('RoadsteadsLayer.tsx')
    // "1 5" is the water AHEAD of a fleet (FleetsLayer.tsx:40): the sparsest dot in the vocabulary,
    // already meaning "a line not yet made good".
    expect(layer).toContain('strokeDasharray="1 5"')
    // NOT the passage she has sailed, NOT a destination ring, and NOT brass — accent means YOURS
    // on this chart, and a roadstead is true of every harbour whether you use it or not.
    expect(layer).not.toContain('"1 3"')
    expect(layer).not.toContain('"3 3"')
    expect(layer).not.toContain('stroke-accent')
  })

  test('ChartCanvas composes it between the tracks and the ports, off the drawn set', () => {
    const canvas = read('ChartCanvas.tsx')
    const tracks = canvas.indexOf('<TracksLayer')
    const roads = canvas.indexOf('<RoadsteadsLayer')
    const ports = canvas.indexOf('<PortsLayer')
    expect(tracks, 'no <TracksLayer/> in ChartCanvas').toBeGreaterThan(-1)
    expect(roads, 'no <RoadsteadsLayer/> in ChartCanvas').toBeGreaterThan(-1)
    expect(ports, 'no <PortsLayer/> in ChartCanvas').toBeGreaterThan(-1)
    // Paint order is the only stacking SVG has, so it is a rule: a dotted line crossing a port
    // passes BEHIND it, and the city mark on top of its own roads is the right picture.
    expect(roads).toBeGreaterThan(tracks)
    expect(roads).toBeLessThan(ports)
    // …and it is handed the SAME list PortsLayer is handed, never the whole port table.
    expect(canvas).toMatch(/<RoadsteadsLayer\s+ports=\{drawnPorts\}/)
  })
})
