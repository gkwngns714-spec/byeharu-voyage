import { test, expect } from '@playwright/test'
import { readFileSync, readdirSync } from 'node:fs'
import path from 'node:path'
import { project, type ViewBox } from '../src/lib/geo'
import {
  arrowPath,
  buildChartModel,
  buildCoastline,
  coastStrokeWidth,
  fitView,
  GLYPH,
  GREAT_PORT_TIER,
  headingDeg,
  LABEL_PRIORITY,
  LABEL_SPAN_LIMIT,
  mapFleetsOf,
  mapLabelRequests,
  mapPortsOf,
  mapSeasOf,
  MAX_SPAN_X,
  MIN_SPAN_X,
  minTierForSpan,
  openingBounds,
  planLabels,
  SEA_NAME_SPAN_LIMIT,
  seaNameRequests,
  shipPath,
  unitsPerPixel,
  viewBoxOf,
  visiblePorts,
  type MapSea,
} from '../src/chart'
import { REAL_PORTS, dockedFleet, sailingFleet } from './mapWorld.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE PICTURE — owner row 90 (2026-09-13): "map should be much more graphic... it is too blank."
//
// docs/MAP_ATMOSPHERE.md is the audit and the design; this file is what holds the design to
// account without a browser. Every rule below is DATA (a token in src/index.css, a request the
// planner was handed, a path string, a number in glyphs.ts), which is the only shape this harness
// can prove (tests/waters.panel.spec.ts:19-22 measured why a component cannot be rendered here).
// The COLOURS are proved by measuring the running chart — tests/chart.ink.spec.ts — and this file
// deliberately re-implements none of them.
//
//   · the land is FILLED, in a token, and the coast's weight rises with zoom;
//   · the seas' names are placed by the ONE planner, and at the opening frame none of them
//     touches a port's name or a port's mark — at 390×844 and at 1440×900;
//   · the ship is ONE path, used by every surface that draws a fleet at sea, and the course ends
//     in an arrowhead turned along its last segment;
//   · every `--color-chart-*` token the night defines, the day defines too;
//   · the new layer is furniture like the roadsteads: `ChartCanvas` composes it and nobody else
//     can reach it.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const ROOT = process.cwd()
const SRC = path.join(ROOT, 'src')
const read = (rel: string) => readFileSync(path.join(ROOT, rel), 'utf8')

/** The REAL seas, off disk — 51 named waters and their hand-placed anchors (data/seas.json). */
const SEAS: readonly MapSea[] = mapSeasOf(JSON.parse(read('data/seas.json')))
const PORTS = mapPortsOf(REAL_PORTS)

// ── 1. THE SEAS, AS DATA ───────────────────────────────────────────────────────────────────────

test.describe('the seas are read, not invented', () => {
  test('all 51 waters in data/seas.json come through, anchors copied to the degree', () => {
    const raw = JSON.parse(read('data/seas.json')) as { seas: { id: string; name: string; centroid: { lat: number; lon: number } }[] }
    expect(raw.seas).toHaveLength(51)
    expect(SEAS).toHaveLength(raw.seas.length)
    for (const [i, sea] of SEAS.entries()) {
      expect(sea.id).toBe(raw.seas[i].id)
      expect(sea.at).toEqual({ lat: raw.seas[i].centroid.lat, lon: raw.seas[i].centroid.lon })
    }
    // An ocean is a water the data names as one — six of them — and everything else is a sea.
    expect(SEAS.filter((s) => s.kind === 'ocean').map((s) => s.name)).toEqual([
      'Arctic Ocean',
      'North Atlantic Ocean',
      'South Atlantic Ocean',
      'Indian Ocean',
      'North Pacific Ocean',
      'South Pacific Ocean',
    ])
  })

  test('a malformed row is skipped, never thrown — a backdrop may not take the chart down', () => {
    expect(mapSeasOf(null)).toEqual([])
    expect(mapSeasOf({ seas: 'no' })).toEqual([])
    expect(
      mapSeasOf({
        seas: [
          { id: 'x', name: 'X Sea', centroid: { lat: 'north', lon: 0 } },
          { id: 1, name: 'Y', centroid: { lat: 0, lon: 0 } },
          { id: 'ok', name: 'Ok Sea', centroid: { lat: 1, lon: 2 } },
        ],
      }),
    ).toEqual([{ id: 'ok', name: 'Ok Sea', at: { lat: 1, lon: 2 }, kind: 'sea' }])
  })

  test('an ocean is named at every zoom; a sea only inside SEA_NAME_SPAN_LIMIT', () => {
    const world: ViewBox = { x: -180, y: -90, width: 360, height: 180 }
    const atWorld = seaNameRequests(SEAS, world)
    expect(atWorld.map((r) => r.id)).toEqual(SEAS.filter((s) => s.kind === 'ocean').map((s) => `sea:${s.id}`))
    expect(SEA_NAME_SPAN_LIMIT).toBeGreaterThan(LABEL_SPAN_LIMIT) // the water is named a step before the quiet harbours
    const europe: ViewBox = { x: -30, y: -70, width: 80, height: 50 }
    const atEurope = seaNameRequests(SEAS, europe)
    expect(atEurope.map((r) => r.text)).toEqual(expect.arrayContaining(['Bay of Biscay', 'North Sea', 'Mediterranean Sea']))
    // Every request is centred on its anchor, in the sea tone, below the quietest harbour.
    for (const r of atEurope) {
      expect(r.placement).toBe('centred')
      expect(r.tone).toBe('sea')
      expect(r.priority).toBeLessThan(LABEL_PRIORITY.quiet + 1)
    }
    // …and a water off the glass does not ask.
    expect(atEurope.map((r) => r.text)).not.toContain('Sea of Japan')
  })
})

// ── 2. THE ONE PLANNER — a sea's name never touches a place ────────────────────────────────────

/** Two at anchor, two at sea — the same house tests/map.labels.spec.ts plans for. */
const FLEETS = mapFleetsOf([
  dockedFleet('gaivota', 'Gaivota', 'LIS'),
  dockedFleet('levante', 'Levante', 'GOA'),
  sailingFleet({ id: 'aurora', name: 'Aurora', from: 'LIS', to: 'CAD', course: ['LIS', 'CAD', 'CEU'], legFrac: 0.45 }),
  sailingFleet({ id: 'ponente', name: 'Ponente', from: 'LIS', to: 'FNC', course: ['LIS', 'FNC', 'LPA'], legFrac: 0.35 }),
])
const MODEL = buildChartModel(FLEETS, PORTS)

/** The chart's live geometry at a given surface size — exactly as MapScreen computes it. */
function chartAt(widthPx: number, heightPx: number) {
  const aspect = widthPx / heightPx
  const bounds = openingBounds(MODEL.focusPoints, MODEL.motionPoints, PORTS, aspect)
  const view = fitView(bounds, aspect)
  const viewBox = viewBoxOf(view, aspect)
  return { viewBox, unitsPerPx: unitsPerPixel(view, widthPx) }
}

/** ONE plan — the places and the waters together, exactly as ChartCanvas hands them over. */
function planAt(widthPx: number, heightPx: number) {
  const { viewBox, unitsPerPx } = chartAt(widthPx, heightPx)
  const drawn = visiblePorts(PORTS, MODEL.portRoles, viewBox, minTierForSpan(viewBox.width))
  const requests = [
    ...mapLabelRequests(MODEL, drawn, null, viewBox.width <= LABEL_SPAN_LIMIT),
    ...seaNameRequests(SEAS, viewBox),
  ]
  const placed = planLabels(requests, {
    viewBox,
    unitsPerPx,
    fontSizePx: GLYPH.labelSize,
    gapPx: GLYPH.labelGapX,
    glyphRadiusPx: GLYPH.fleetHaloRadius,
  })
  return { viewBox, unitsPerPx, drawn, requests, placed }
}

const overlaps = (a: { x: number; y: number; width: number; height: number }, b: { x: number; y: number; width: number; height: number }) =>
  a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height

test.describe('the seas are named on the water, and never over a place', () => {
  for (const [w, h] of [
    [390, 844],
    [1440, 900],
  ]) {
    test(`${w}x${h}, the opening frame: the water is named, and no sea name touches a port's name or mark`, () => {
      const { unitsPerPx, drawn, requests, placed } = planAt(w, h)
      const seaNames = placed.filter((l) => l.tone === 'sea')
      const places = placed.filter((l) => l.tone !== 'sea')

      // NON-VACUITY: the opening frame off Iberia holds a named water (the Bay of Biscay's anchor
      // is inside both frames) and it ASKED. A guard over nothing proves nothing. Whether it is
      // PLACED is the frame's business: on the desktop it is; on this fixture's phone frame the
      // anchor sits 1.6° from the right edge and a 4.4°-wide name runs off the glass, so it is
      // dropped — the same edge rule every port name obeys (measured 2026-09-13: the frame ends
      // at x=−2.93, the name would span −6.7…−2.3). The rules below bind whatever was placed.
      expect(requests.filter((r) => r.tone === 'sea').length, 'no sea asked to be named').toBeGreaterThan(0)
      if (w >= 1440) expect(seaNames.length, 'no sea name was placed on the opening frame').toBeGreaterThan(0)
      expect(places.length).toBeGreaterThan(0)

      // Every sea name sits on its own anchor — centred, never nudged beside a glyph.
      for (const sea of seaNames) expect(sea.side, sea.text).toBe('centre')

      // No sea name overlaps a place's name…
      for (const sea of seaNames) {
        for (const place of places) {
          expect(overlaps(sea.box, place.box), `"${sea.text}" overprints "${place.text}"`).toBe(false)
        }
        // …nor any drawn port's MARK (the glyph's square, as the planner counts it).
        const glyph = GLYPH.fleetHaloRadius * unitsPerPx
        for (const port of drawn) {
          const at = project(port)
          const mark = { x: at.x - glyph, y: at.y - glyph, width: 2 * glyph, height: 2 * glyph }
          expect(overlaps(sea.box, mark), `"${sea.text}" is printed across ${port.name}'s mark`).toBe(false)
        }
      }
      // And a place is never dropped FOR a sea: every place placed without the seas is still
      // placed with them, on the same side — the water fills what the places left.
      const { placed: alone } = (() => {
        const { viewBox, unitsPerPx: u } = chartAt(w, h)
        return {
          placed: planLabels(mapLabelRequests(MODEL, drawn, null, viewBox.width <= LABEL_SPAN_LIMIT), {
            viewBox,
            unitsPerPx: u,
            fontSizePx: GLYPH.labelSize,
            gapPx: GLYPH.labelGapX,
            glyphRadiusPx: GLYPH.fleetHaloRadius,
          }),
        }
      })()
      expect(places.map((l) => `${l.id}:${l.side}`)).toEqual(alone.map((l) => `${l.id}:${l.side}`))
    })
  }

  test('a sea name that would touch a place is DROPPED, not moved — one placement, or nothing', () => {
    const VIEW = { x: 0, y: 0, width: 100, height: 100 }
    const OPTS = { viewBox: VIEW, unitsPerPx: 1, fontSizePx: 10, gapPx: 5, glyphRadiusPx: 4, edgeInsetPx: 0 }
    const placed = planLabels(
      [
        { id: 'port:a', text: 'Aport', at: { x: 50, y: 50 }, priority: LABEL_PRIORITY.quiet, tone: 'port-quiet' },
        { id: 'sea:s', text: 'Some Sea', at: { x: 56, y: 50 }, priority: LABEL_PRIORITY.sea, tone: 'sea', placement: 'centred', spacingEm: 0.14 },
      ],
      OPTS,
    )
    expect(placed.map((l) => l.id)).toEqual(['port:a'])
    // Moved off the place, it is placed — centred, and at the size and spacing it asked for.
    // (At 14 px with 0.14 em of spacing "Some Sea" is ~87 units wide, so it is anchored at the
    // frame's centre; anchored at x=60 it would run off the right edge and be dropped, which is
    // the edge rule doing its job, not this rule.)
    const [, sea] = planLabels(
      [
        { id: 'port:a', text: 'Aport', at: { x: 20, y: 20 }, priority: LABEL_PRIORITY.quiet, tone: 'port-quiet' },
        { id: 'sea:s', text: 'Some Sea', at: { x: 50, y: 70 }, priority: LABEL_PRIORITY.sea, tone: 'sea', placement: 'centred', sizePx: 14, spacingEm: 0.14 },
      ],
      OPTS,
    )
    expect(sea, 'the sea name was dropped with the whole frame free').toBeTruthy()
    expect(sea.side).toBe('centre')
    expect(sea.anchor).toBe('middle')
    expect(sea.sizePx).toBe(14)
    expect(sea.spacingEm).toBe(0.14)
    expect(sea.box.width).toBeGreaterThan('Some Sea'.length * 0.6 * 14) // the spacing is in the box
    expect(sea.box.x + sea.box.width / 2).toBeCloseTo(50, 6)
    // And the edge rule: the same name anchored where it cannot fit is dropped, never clipped.
    expect(
      planLabels(
        [{ id: 'sea:s', text: 'Some Sea', at: { x: 90, y: 70 }, priority: LABEL_PRIORITY.sea, tone: 'sea', placement: 'centred', sizePx: 14, spacingEm: 0.14 }],
        OPTS,
      ),
    ).toHaveLength(0)
  })
})

// ── 3. THE LAND, THE COAST, THE SHIP AND THE ARROW — as arithmetic and as paths ────────────────

test.describe('the land is a body and the coast has a weight', () => {
  test('the land is FILLED in a token, the coast is stroked in a token, and both come from one file', () => {
    const layer = read('src/chart/CoastlineLayer.tsx')
    // The two elements the ink spec measures: the body's fill, and the line's stroke.
    expect(layer).toMatch(/className="fill-chart-land"[\s\S]*?data-testid="map-coastline"/)
    expect(layer).toMatch(/className="fill-none stroke-chart-coast"[\s\S]*?data-testid="map-coast"/)
    // The shallows, the relief and the clip are the same two paths — no second outline anywhere.
    expect(layer).toContain('stroke-chart-shallow')
    expect(layer).toContain('stroke-chart-relief')
    expect(layer).toContain('clipPath')
    expect(layer).not.toMatch(/buildCoastline|fetch\(/)
  })

  test('the line drops the inland borders the file shares between countries; the body keeps every ring', () => {
    // Two squares sharing one edge (x = 10): two countries. The body is two rings; the LINE is the
    // outline of the pair — six edges, never the seventh they share. Vertices are exact, as they
    // are in Natural Earth (measured 2026-09-13: 2,664 of 10,365 segments are shared by exactly two
    // rings, none by more).
    const pair = {
      type: 'FeatureCollection',
      features: [
        { type: 'Feature', geometry: { type: 'Polygon', coordinates: [[[0, 0], [10, 0], [10, 10], [0, 10], [0, 0]]] } },
        { type: 'Feature', geometry: { type: 'Polygon', coordinates: [[[10, 0], [20, 0], [20, 10], [10, 10], [10, 0]]] } },
      ],
    }
    const built = buildCoastline(pair)
    expect(built.ringCount).toBe(2)
    expect(built.sharedSegmentCount).toBe(1)
    expect(built.d.match(/Z/g)).toHaveLength(2)
    // The shared edge runs from (10,0) to (10,10) — in chart units (10, 0)→(10, −10). Neither
    // direction of it may appear in the line.
    expect(built.coastD).not.toMatch(/M10 0L10 -10|L10 0L10 -10|M10 -10L10 0|L10 -10L10 0/)
    // …while the outer corners all do (each run starts at the border, so a corner arrives as an
    // `L`), and nothing in the line is closed: two open runs, one per country.
    const has = (x: number, y: number) => new RegExp(`[ML]${x} ${y}(?=[LMZ]|$)`).test(built.coastD)
    for (const [x, y] of [[0, 0], [20, 0], [20, -10], [0, -10]]) expect(has(x, y), `corner ${x},${y}`).toBe(true)
    expect(built.coastD.match(/M/g)).toHaveLength(2)
    expect(built.coastD).not.toContain('Z')
    // A lone island is one closed run: its line IS its ring.
    const island = buildCoastline({ type: 'FeatureCollection', features: [pair.features[0]] })
    expect(island.sharedSegmentCount).toBe(0)
    expect(island.coastD.match(/Z/g)).toHaveLength(1)
  })

  test('the coast thickens as you zoom in, and is a hairline over the globe', () => {
    expect(coastStrokeWidth(MAX_SPAN_X)).toBeCloseTo(GLYPH.coastStroke, 6)
    expect(coastStrokeWidth(MIN_SPAN_X)).toBeGreaterThan(coastStrokeWidth(MAX_SPAN_X) * 1.6)
    let last = coastStrokeWidth(MAX_SPAN_X)
    for (const span of [200, 90, 45, 20, 12, 5, 1.5]) {
      const w = coastStrokeWidth(span)
      expect(w, `span ${span}`).toBeGreaterThanOrEqual(last)
      last = w
    }
    // Bad input is the hairline, never NaN.
    for (const bad of [0, -1, Number.NaN, Number.POSITIVE_INFINITY]) expect(Number.isFinite(coastStrokeWidth(bad))).toBe(true)
  })

  test('a great harbour wears a ring, and it is the top tier the zoom bands already single out', () => {
    expect(GREAT_PORT_TIER).toBe(5)
    expect(GLYPH.greatPortRingRadius).toBeLessThan(GLYPH.destinationRingRadius) // never mistaken for "bound here"
    expect(GLYPH.greatPortRingRadius).toBeGreaterThan(GLYPH.loudPortHalfWidth * 1.4) // clears the biggest mark
    expect(read('src/chart/PortsLayer.tsx')).toContain('GREAT_PORT_TIER')
  })
})

test.describe('the ship is one hull, and the course points where it goes', () => {
  test('shipPath is a closed hull with its bow up, and the arrow is an open chevron at the origin', () => {
    const hull = shipPath(GLYPH.shipHalfLength)
    expect(hull.startsWith(`M0 ${-GLYPH.shipHalfLength}`)).toBe(true) // the bow, at −y
    expect(hull.endsWith('Z')).toBe(true)
    const arrow = arrowPath(GLYPH.arrowHalfWidth)
    expect(arrow).toContain('L0 0') // the tip is the origin
    expect(arrow.endsWith('Z')).toBe(false) // open, so it never reads as a fifth filled mark
  })

  test('the heading is degrees clockwise from north, in chart space', () => {
    expect(headingDeg({ x: 0, y: 0 }, { x: 0, y: -1 })).toBeCloseTo(0, 6) // north (−y) is 0
    expect(headingDeg({ x: 0, y: 0 }, { x: 1, y: 0 })).toBeCloseTo(90, 6) // east
    expect(headingDeg({ x: 0, y: 0 }, { x: 0, y: 1 })).toBeCloseTo(180, 6) // south
    expect(headingDeg({ x: 0, y: 0 }, { x: 0, y: 0 })).toBeNull()
  })

  test('every fleet at sea carries the heading of the served segment it is on; a docked one none', () => {
    const aurora = MODEL.fleets.find((f) => f.fleet.id === 'aurora')!
    const gaivota = MODEL.fleets.find((f) => f.fleet.id === 'gaivota')!
    const lis = project(PORTS.find((p) => p.code === 'LIS')!)
    const cad = project(PORTS.find((p) => p.code === 'CAD')!)
    expect(aurora.heading).toBeCloseTo(headingDeg(lis, cad)!, 6)
    expect(gaivota.heading).toBeNull()
    // …and the track's arrowhead sits on the course's LAST vertex, turned along the last segment.
    const ceu = project(PORTS.find((p) => p.code === 'CEU')!)
    expect(aurora.track!.end).toEqual(ceu)
    expect(aurora.track!.endHeading).toBeCloseTo(headingDeg(cad, ceu)!, 6)
  })

  test('one hull for every surface — FleetsLayer and Minimap draw `shipPath`, and no dot survives', () => {
    const fleets = read('src/chart/FleetsLayer.tsx')
    const minimap = read('src/chart/Minimap.tsx')
    expect(fleets).toContain('shipPath(GLYPH.shipHalfLength)')
    expect(minimap).toContain('shipPath(GLYPH.shipHalfLength)')
    expect(fleets).not.toContain('fleetDotRadius')
    expect(minimap).not.toContain('fleetDotRadius')
    expect(GLYPH).not.toHaveProperty('fleetDotRadius')
    // The passage made is SOLID, the water ahead is dashed and ends in the arrow.
    expect(fleets).toContain('arrowPath(GLYPH.arrowHalfWidth)')
    expect(fleets).toMatch(/d=\{f\.track\.sailedD\}[\s\S]*?vectorEffect/)
    expect(fleets.slice(fleets.indexOf('d={f.track.sailedD}'), fleets.indexOf('d={f.track.sailedD}') + 300)).not.toContain('strokeDasharray')
  })
})

// ── 4. BOTH SCHEMES DEFINE EVERY CHART TOKEN ───────────────────────────────────────────────────

/** The `--color-chart-*` names declared inside the block that starts at `opener`. */
function chartTokensIn(css: string, opener: string): string[] {
  const start = css.indexOf(opener)
  expect(start, `no "${opener}" block in src/index.css`).toBeGreaterThan(-1)
  let depth = 0
  let i = css.indexOf('{', start)
  const from = i
  for (; i < css.length; i++) {
    if (css[i] === '{') depth++
    else if (css[i] === '}' && --depth === 0) break
  }
  const block = css.slice(from, i)
  return [...block.matchAll(/^\s*(--color-chart-[a-z0-9-]+)\s*:/gm)].map((m) => m[1]).sort()
}

test('every --color-chart-* token the night sea defines, the day sea defines too', () => {
  const css = read('src/index.css')
  const night = chartTokensIn(css, '@theme')
  const day = chartTokensIn(css, ":root[data-theme='light']")
  expect(night.length).toBeGreaterThanOrEqual(8) // sea, land, coast + deep, shallow, relief, grid, sea-name
  expect(day).toEqual(night)
  // …and every one of them is spent: a token nobody paints with is a second palette waiting.
  const painted = readdirSync(path.join(SRC, 'chart'))
    .map((f) => read(path.join('src', 'chart', f)))
    .join('\n')
  for (const token of night) {
    const utility = token.replace('--color-', '')
    expect(painted.includes(utility), `${token} is defined and never drawn`).toBe(true)
  }
})

// ── 5. THE NEW LAYER IS FURNITURE ──────────────────────────────────────────────────────────────

test('SeaLayer is composed by ChartCanvas and reachable by nobody else', () => {
  const entrance = read('src/chart/index.ts')
  expect(entrance.includes('SeaLayer')).toBe(false)
  const importers = readdirSync(path.join(SRC, 'chart'))
    .filter((f) => /\.tsx?$/.test(f) && read(path.join('src', 'chart', f)).includes("from './SeaLayer'"))
  expect(importers).toEqual(['ChartCanvas.tsx'])
  // Painted FIRST — the sea is the ground — and the coast on it, at the zoom's weight.
  const canvas = read('src/chart/ChartCanvas.tsx')
  expect(canvas.indexOf('<SeaLayer')).toBeLessThan(canvas.indexOf('<CoastlineLayer'))
  expect(canvas).toContain('strokeWidth={coastStrokeWidth(box.width)}')
})
