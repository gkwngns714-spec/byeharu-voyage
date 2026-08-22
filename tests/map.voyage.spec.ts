import { test, expect } from '@playwright/test'
import { project, type ViewBox } from '../src/lib/geo'
import {
  FIT_PADDING,
  GLYPH,
  LEG_SPAN_LIMIT,
  OPENING_MIN_SPAN_DEG,
  buildChartModel,
  hitTest,
  legWebPath,
  mapFleetsOf,
  mapPortsOf,
  minTierForSpan,
  openingBounds,
  toggleSelection,
  visiblePorts,
} from '../src/chart'
import type { FleetView } from '../src/lib/rpc'
import { REAL_PORTS, dockedFleet, leg, portAt, sailingFleet } from './mapWorld.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A VOYAGE ON THE CHART IS THE SERVER'S ANSWER, COPIED — and this file is the proof of it.
//
// WHAT THIS FILE USED TO PROVE, AND WHY IT DOES NOT ANY MORE. It proved that the map's own copy of
// DESIGN §D.2 — `progress(t) = (t − departed_at) × TIME_COMPRESSION × v_fleet / 3600`, in
// src/features/map/voyage.ts — was a pure function of (voyage, instant). It was. It was also a
// SECOND IMPLEMENTATION of the movement rule on the client, and the live store forbids exactly
// that: "voyage position … computed inside the transaction that owns it. The client's job is to
// print them. There is no second implementation of any of it on this side of the wire." The server
// now serves `voyage.position` (README §4.8), so voyage.ts is DELETED and the property worth
// proving changed with it.
//
// WHAT IT PROVES NOW — the same discipline, one layer out:
//   · the glyph is drawn at EXACTLY the coordinate the server sent; nothing is re-derived,
//   · the model takes no clock at all, so there is nothing that could drift,
//   · only the CURRENT leg is drawn, because only the current leg is served; a destination further
//     on is RINGED, never routed,
//   · the sea lanes are drawn close in and not at all when pulled back,
//   · a tap selects, and a selection is the only value this surface can produce.
//
// Pure Node: no `page` fixture is used, so no browser is launched.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const PORTS = mapPortsOf(REAL_PORTS)
const LISBON = portAt('LIS')
const CADIZ = portAt('CAD')

/** Aurora is on Lisbon → Cádiz, 45% of the way, but bound onward to Ceuta: the leg it is on is not
 *  the leg it finishes on, which is the case the chart has to keep honest. */
const AURORA: FleetView = sailingFleet({
  id: 'aurora',
  name: 'Aurora',
  from: 'LIS',
  to: 'CAD',
  legFrac: 0.45,
  destination: 'CEU',
  sailedNm: 111.5,
  totalNm: 309,
  etaMs: 1_700_000_600_000,
})

const GAIVOTA = dockedFleet('gaivota', 'Gaivota', 'LIS')

const MODEL = buildChartModel(mapFleetsOf([AURORA, GAIVOTA]), PORTS)

test.describe('the position is the server’s, copied', () => {
  test('the glyph is drawn at exactly position.lat / position.lon', () => {
    const served = AURORA.voyage!.position!
    const drawn = MODEL.fleets.find((f) => f.fleet.id === 'aurora')
    expect(drawn).toBeDefined()
    // EXACT equality, not "close to": a chart that rounds, re-projects or re-derives the coordinate
    // would fail here, and it should.
    expect(drawn!.at).toEqual({ lat: served.lat, lon: served.lon })
  })

  test('nothing between the wire and the ink invents a number', () => {
    const served = AURORA.voyage!.position!
    const [fleet] = mapFleetsOf([AURORA])
    expect(fleet.kind).toBe('sailing')
    if (fleet.kind !== 'sailing') return
    expect(fleet.leg.at).toEqual({ lat: served.lat, lon: served.lon })
    expect(fleet.leg.legFrac).toBe(served.leg_frac)
    expect(fleet.leg.sailedNm).toBe(served.nm_done)
    expect(fleet.leg.totalNm).toBe(served.total_nm)
    expect(fleet.leg.fromCode).toBe(served.from_code)
    expect(fleet.leg.toCode).toBe(served.to_code)
    expect(fleet.leg.destinationCode).toBe(AURORA.voyage!.to)
    expect(fleet.leg.etaMs).toBe(Date.parse(AURORA.voyage!.eta))
  })

  test('the model takes no clock, so there is nothing that can drift', () => {
    // Built twice, at whatever moments these two calls happen to run: identical. The old failure
    // mode — a glyph that moves because a frame fired — cannot exist, because no frame is an input.
    const first = buildChartModel(mapFleetsOf([AURORA, GAIVOTA]), PORTS)
    const again = buildChartModel(mapFleetsOf([AURORA, GAIVOTA]), PORTS)
    expect(again.fleets.map((f) => f.at)).toEqual(first.fleets.map((f) => f.at))
    expect(again.fleets.map((f) => f.track)).toEqual(first.fleets.map((f) => f.track))
    expect(buildChartModel.length).toBe(2) // (fleets, ports) — and no third argument
  })

  test('only the player’s own fleets are in the model — there is no field for anyone else', () => {
    expect(Object.keys(MODEL)).toEqual([
      'fleets',
      'portRoles',
      'destinationPoints',
      'focusPoints',
      'motionPoints',
    ])
    expect(MODEL.fleets).toHaveLength(2)
  })

  test('a voyage the server did not place is not parked at a guessed coordinate', () => {
    const unplaced: FleetView = { ...AURORA, voyage: { ...AURORA.voyage!, position: null } }
    expect(mapFleetsOf([unplaced])).toHaveLength(0)
    // …and one that is simply in port is placed on its quay.
    expect(mapFleetsOf([GAIVOTA])).toEqual([
      { kind: 'docked', id: 'gaivota', name: 'Gaivota', portCode: 'LIS' },
    ])
  })
})

test.describe('the chart draws the leg it was given, and no other water', () => {
  const aurora = () => MODEL.fleets.find((f) => f.fleet.id === 'aurora')!

  test('the track runs from the leg’s origin to the leg’s arrival port, split at the fleet', () => {
    const track = aurora().track
    expect(track).not.toBeNull()
    const from = project(LISBON)
    const to = project(CADIZ)
    const at = project(aurora().at)
    const two = (a: { x: number; y: number }, b: { x: number; y: number }) =>
      `M${round(a.x)} ${round(a.y)}L${round(b.x)} ${round(b.y)}`
    expect(track!.sailedD).toBe(two(from, at))
    expect(track!.aheadD).toBe(two(at, to))
  })

  test('the ship sits ON its own track — the client geometry is the server’s geometry', () => {
    // `voyage.position()` interpolates LINEARLY in lat/lon; on an equirectangular chart that is the
    // straight segment ./route.ts draws. A great-circle arc would bow away from the very point the
    // server put the ship at. This is the seam, asserted rather than assumed.
    const at = aurora().at
    const t = aurora().leg!.legFrac
    expect(at.lat).toBeCloseTo(LISBON.lat + (CADIZ.lat - LISBON.lat) * t, 3)
    expect(at.lon).toBeCloseTo(LISBON.lon + (CADIZ.lon - LISBON.lon) * t, 3)
  })

  test('a destination beyond this leg is RINGED, never routed', () => {
    // Aurora is bound for Ceuta but is sailing Lisbon → Cádiz. The ring goes on Ceuta; the line
    // stops at Cádiz, because the leg Cádiz → Ceuta is not served (README §4.8).
    expect(aurora().destinationCode).toBe('CEU')
    expect([...MODEL.destinationPoints.keys()]).toEqual(['CEU'])
    const ceuta = portAt('CEU')
    expect(MODEL.destinationPoints.get('CEU')).toEqual({ lat: ceuta.lat, lon: ceuta.lon })
    expect(aurora().track!.aheadD).not.toContain(String(ceuta.lat))
  })

  test('the destination ring is placed once per port, not once per fleet', () => {
    const two = buildChartModel(
      mapFleetsOf([
        AURORA,
        sailingFleet({ id: 'b', name: 'Bonança', from: 'SAF', to: 'CEU', legFrac: 0.2, destination: 'CEU' }),
      ]),
      PORTS,
    )
    expect(two.destinationPoints.size).toBe(1)
  })

  test('a docked fleet gets no track and no destination', () => {
    const docked = MODEL.fleets.find((f) => f.fleet.id === 'gaivota')!
    expect(docked.track).toBeNull()
    expect(docked.leg).toBeNull()
    expect(docked.destinationCode).toBeNull()
    expect(docked.dockedAtCode).toBe('LIS')
  })

  test('port roles rank correctly, and a port no fleet touches has none', () => {
    expect(MODEL.portRoles.get('CEU')).toBe('destination') // Aurora is bound there
    expect(MODEL.portRoles.get('LIS')).toBe('anchorage') // Gaivota lies there, and Aurora left it
    expect(MODEL.portRoles.get('CAD')).toBe('route') // the far end of the leg Aurora is on
    expect(MODEL.portRoles.get('SVL')).toBeUndefined()
    expect(MODEL.portRoles.get('NAP')).toBeUndefined()
  })

  test('the opening frame is what is HAPPENING, not the 214-port table', () => {
    const points = MODEL.focusPoints
    expect(points.length).toBeGreaterThan(0)
    const nagasaki = portAt('NAG')
    expect(points.some((p) => p.lat === nagasaki.lat && p.lon === nagasaki.lon)).toBe(false)
    const bounds = openingBounds(MODEL.focusPoints, MODEL.motionPoints, PORTS, 1280 / 800)
    expect(bounds.maxLon - bounds.minLon).toBeLessThan(60)
  })

  test('with no fleets the frame falls back to the world, because that is the honest answer', () => {
    const empty = buildChartModel([], PORTS)
    expect(empty.focusPoints).toHaveLength(0)
    const bounds = openingBounds(empty.focusPoints, empty.motionPoints, PORTS, 1280 / 800)
    // Every port in the table is inside it — the map never opens on empty ocean.
    for (const port of PORTS) {
      expect(port.lon).toBeGreaterThanOrEqual(bounds.minLon)
      expect(port.lon).toBeLessThanOrEqual(bounds.maxLon)
    }
  })
})

test.describe('the sea lanes are a hairline close in, and nothing at all pulled back', () => {
  const LEGS = [leg('CAD', 'LIS', 247.7), leg('CAD', 'CEU', 61), leg('LIS', 'NAG', 12_000)]
  const byCode = new Map(PORTS.map((p) => [p.code, p]))

  test('the lanes in view are drawn, as ONE path with one subpath each', () => {
    const iberia: ViewBox = { x: -12, y: -42, width: 10, height: 8 }
    const d = legWebPath(LEGS, byCode, iberia)
    // Lisbon, Cádiz and Ceuta are all on this sheet, so both short lanes are drawn — as two `M…L…`
    // subpaths of ONE string, because 782 lanes must never become 782 elements.
    expect(d.split('M').filter(Boolean)).toHaveLength(2)
    expect(d.startsWith('M')).toBe(true)
    expect(d).toContain(`M${round(project(CADIZ).x)}`)
  })

  test('a leg with one end off the glass is dropped whole, never clipped to a stub', () => {
    // The same three lanes, framed on Portugal: Ceuta (lon −5.3) is off the right edge, so the
    // Cádiz–Ceuta lane goes entirely, and Lisbon–Nagasaki was never a candidate. That last one is
    // what keeps a lane straddling the antimeridian off the sheet: no view holds both its ends.
    const portugal: ViewBox = { x: -12, y: -42, width: 6, height: 8 }
    const d = legWebPath(LEGS, byCode, portugal)
    expect(d.split('M').filter(Boolean)).toHaveLength(1)
    expect(d).not.toContain(String(round(project(portAt('CEU')).x)))
  })

  test('a lane the view does not contain contributes nothing, not a stub', () => {
    const pacific: ViewBox = { x: 120, y: -40, width: 10, height: 8 }
    expect(legWebPath(LEGS, byCode, pacific)).toBe('')
  })

  test('the layer covers the OPENING frame, and is dropped — not faded — above it', () => {
    // MEASURED in the browser and then pinned here: a lone fleet at Lisbon frames
    // OPENING_MIN_SPAN_DEG, which FIT_PADDING opens to 12 × 1.24 = 14.88° on the glass. If the lane
    // limit sat below that, a new player would see no sea routes on the one screen that exists to
    // answer "where can I go from here" — which is exactly what a run in Chrome showed.
    const openingSpan = OPENING_MIN_SPAN_DEG * (1 + 2 * FIT_PADDING)
    expect(openingSpan).toBeCloseTo(14.88, 6)
    expect(LEG_SPAN_LIMIT).toBeGreaterThan(openingSpan)
    // …and it is still a coast, not a hemisphere.
    expect(LEG_SPAN_LIMIT).toBeLessThan(45)
  })

  test('a lane joins two MARKS, never a mark and blank water', () => {
    // Iberia at 14° across: the tier floor is 3, so Ceuta (tier 2) has no triangle. The Cádiz–Ceuta
    // lane must go with it — a hairline ending in empty sea reads as a route to nowhere.
    const iberia: ViewBox = { x: -14, y: -43, width: 14, height: 9 }
    expect(minTierForSpan(iberia.width)).toBe(3)
    const drawn = visiblePorts(PORTS, new Map(), iberia, minTierForSpan(iberia.width))
    expect(drawn.map((p) => p.code)).toContain('CAD')
    expect(drawn.map((p) => p.code)).not.toContain('CEU')
    const d = legWebPath(LEGS, new Map(drawn.map((p) => [p.code, p])), iberia)
    expect(d.split('M').filter(Boolean)).toHaveLength(1) // Cádiz–Lisbon only
    // Give Ceuta a role — a fleet is bound there — and it is drawn again, lane and all.
    const withRole = visiblePorts(PORTS, MODEL.portRoles, iberia, minTierForSpan(iberia.width))
    const withLane = legWebPath(LEGS, new Map(withRole.map((p) => [p.code, p])), iberia)
    expect(withLane.split('M').filter(Boolean)).toHaveLength(2)
  })

  test('a leg naming a port the snapshot does not carry is skipped, never guessed', () => {
    expect(legWebPath([leg('LIS', 'ZZZ', 100)], byCode, { x: -20, y: -50, width: 40, height: 30 })).toBe('')
  })
})

test.describe('hitTest — nearest wins, at every zoom, over the ports actually drawn', () => {
  // A 390 px phone looking at Iberia: 10° across, so 1 px = 0.0256°, and a 44 px reach is 0.56°.
  const VIEW: ViewBox = { x: -12, y: -44, width: 10, height: 8 }
  const REACH = GLYPH.hitRadius * (VIEW.width / 390)
  const DRAWN = visiblePorts(PORTS, MODEL.portRoles, VIEW, minTierForSpan(VIEW.width))

  test('a tap ON a port picks THAT port, not its crowded neighbour', () => {
    expect(hitTest(MODEL, DRAWN, project(CADIZ), REACH)).toEqual({ kind: 'port', code: 'CAD' })
    const sanlucar = portAt('SNL')
    expect(hitTest(MODEL, DRAWN, project(sanlucar), REACH)).toEqual({ kind: 'port', code: 'SNL' })
    // The two are well inside one reach of each other, which is the case that used to be a coin toss.
    const apart = Math.hypot(CADIZ.lon - sanlucar.lon, CADIZ.lat - sanlucar.lat)
    expect(apart).toBeLessThan(REACH)
  })

  test('a tap between two ports picks the closer one', () => {
    const a = project(CADIZ)
    const b = project(portAt('SNL'))
    const nearCadiz = { x: a.x + (b.x - a.x) * 0.3, y: a.y + (b.y - a.y) * 0.3 }
    const nearSanlucar = { x: a.x + (b.x - a.x) * 0.7, y: a.y + (b.y - a.y) * 0.7 }
    expect(hitTest(MODEL, DRAWN, nearCadiz, REACH)).toEqual({ kind: 'port', code: 'CAD' })
    expect(hitTest(MODEL, DRAWN, nearSanlucar, REACH)).toEqual({ kind: 'port', code: 'SNL' })
  })

  test('a fleet at anchor wins the tie with the port it lies in', () => {
    expect(hitTest(MODEL, DRAWN, project(LISBON), REACH)).toEqual({ kind: 'fleet', id: 'gaivota' })
  })

  test('a port the chart is not drawing cannot be tapped', () => {
    // At world zoom only the 35 great ports (and yours) are on the sheet, so a tap on a tier-2
    // harbour finds nothing — which is right: there is no mark there to have meant.
    const world: ViewBox = { x: -180, y: -90, width: 360, height: 180 }
    const drawnFar = visiblePorts(PORTS, MODEL.portRoles, world, minTierForSpan(world.width))
    const roadstead = portAt('BRI') // Bridgetown, tier 2, nothing of yours near it
    expect(drawnFar.map((p) => p.code)).not.toContain('BRI')
    expect(hitTest(MODEL, drawnFar, project(roadstead), 1)).toBeNull()
  })

  test('open water selects nothing', () => {
    expect(hitTest(MODEL, DRAWN, { x: -40, y: -20 }, REACH)).toBeNull()
  })

  test('the reach is a distance, so it shrinks with the scale as the chart zooms in', () => {
    const nudged = { x: project(CADIZ).x + REACH * 3, y: project(CADIZ).y }
    expect(hitTest(MODEL, DRAWN, nudged, REACH)).not.toEqual({ kind: 'port', code: 'CAD' })
    expect(hitTest(MODEL, DRAWN, nudged, REACH / 10)).toBeNull()
  })
})

test.describe('toggleSelection — and a selection is the ONLY thing this surface produces', () => {
  test('tapping the same thing twice clears it', () => {
    expect(toggleSelection({ kind: 'port', code: 'LIS' }, { kind: 'port', code: 'LIS' })).toBeNull()
    expect(toggleSelection({ kind: 'fleet', id: 'a' }, { kind: 'fleet', id: 'a' })).toBeNull()
  })

  test('tapping a different thing selects it', () => {
    expect(toggleSelection({ kind: 'port', code: 'LIS' }, { kind: 'port', code: 'CAD' })).toEqual({
      kind: 'port',
      code: 'CAD',
    })
    expect(toggleSelection({ kind: 'port', code: 'LIS' }, { kind: 'fleet', id: 'a' })).toEqual({
      kind: 'fleet',
      id: 'a',
    })
  })

  test('tapping nothing clears whatever was selected', () => {
    expect(toggleSelection({ kind: 'port', code: 'LIS' }, null)).toBeNull()
    expect(toggleSelection(null, null)).toBeNull()
  })

  test('a hit is a NAME, never a verb: the only shapes it can return are two selections or null', () => {
    const hit = hitTest(MODEL, PORTS, project(CADIZ), 1)
    expect(hit && Object.keys(hit).sort()).toEqual(['code', 'kind'])
  })
})

/** ./svgPath.ts prints two decimals and trims trailing zeros; the track assertions above have to
 *  speak the same dialect to compare a whole `d` string rather than a fuzzy prefix. */
function round(n: number): string {
  const s = n.toFixed(2)
  const trimmed = s.replace(/\.?0+$/, '')
  return trimmed === '' || trimmed === '-' || trimmed === '-0' ? '0' : trimmed
}
