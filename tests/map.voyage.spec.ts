import { test, expect } from '@playwright/test'
import { project, type ViewBox } from '../src/lib/geo'
import {
  GLYPH,
  buildChartModel,
  driftedPoint,
  hitTest,
  mapFleetsOf,
  mapPortsOf,
  minTierForSpan,
  openingBounds,
  toggleSelection,
  visiblePorts,
} from '../src/chart'
import type { FleetView } from '../src/lib/rpc'
import { REAL_PORTS, anchoredFleet, dockedFleet, portAt, sailingFleet } from './mapWorld.fixture'

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
// WHAT IT PROVES NOW — the same discipline, one layer out (re-pointed for 0039):
//   · the glyph is drawn at EXACTLY the coordinate the server sent; nothing is re-derived,
//   · the model takes no clock at all, so there is nothing that could drift,
//   · THE WHOLE SERVED COURSE is drawn, split at the fleet, and no other water — the server
//     serves the verified polyline the voyage actually sails, and the chart adds nothing to it,
//   · a bare-water destination is ringed at its point; a fleet at open anchor is drawn where it
//     holds,
//   · a tap selects, and a selection is the only value this surface can produce.
//
// Pure Node: no `page` fixture is used, so no browser is launched.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const PORTS = mapPortsOf(REAL_PORTS)
const LISBON = portAt('LIS')
const CADIZ = portAt('CAD')

/** Aurora sails a three-point course Lisbon → Cádiz → Ceuta, 45% along its FIRST segment: the
 *  segment she is on is not the one she finishes on, which is the case the split has to keep
 *  honest — and under 0039 the WHOLE course is served, so the water ahead includes Ceuta. */
const AURORA: FleetView = sailingFleet({
  id: 'aurora',
  name: 'Aurora',
  from: 'LIS',
  to: 'CAD',
  course: ['LIS', 'CAD', 'CEU'],
  legFrac: 0.45,
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
    expect(fleet.voyage.at).toEqual({ lat: served.lat, lon: served.lon })
    expect(fleet.voyage.segIndex).toBe(served.seg_index)
    expect(fleet.voyage.sailedNm).toBe(served.nm_done)
    expect(fleet.voyage.totalNm).toBe(served.total_nm)
    expect(fleet.voyage.course).toEqual(
      AURORA.voyage!.course.map(([lat, lon]) => ({ lat, lon })),
    )
    expect(fleet.voyage.destinationCode).toBe(AURORA.voyage!.to)
    expect(fleet.voyage.etaMs).toBe(Date.parse(AURORA.voyage!.eta))
  })

  test('given no clock, the model still takes none — nothing can drift on its own', () => {
    // Built twice, at whatever moments these two calls happen to run: identical. The old failure
    // mode — a glyph that moves because a frame fired — cannot exist, because no frame is an input.
    //
    // 0075 gave this function an OPTIONAL fourth argument, and this test is what pins the word
    // optional: every caller that does not ask for drift gets the server's point, byte for byte,
    // exactly as it did before that slice. Only the Map tab asks.
    const first = buildChartModel(mapFleetsOf([AURORA, GAIVOTA]), PORTS)
    const again = buildChartModel(mapFleetsOf([AURORA, GAIVOTA]), PORTS)
    expect(again.fleets.map((f) => f.at)).toEqual(first.fleets.map((f) => f.at))
    expect(again.fleets.map((f) => f.track)).toEqual(first.fleets.map((f) => f.track))
    // (fleets, ports) — `considering` and `drift` both default, so neither is a required argument.
    expect(buildChartModel.length).toBe(2)
  })

  test('the model is BLIND to the roadstead — 0076 put two fields on MapPort and no rule here', () => {
    // 0076 gave every port the point of open water it is reached from. It is drawn by a layer of
    // its own and read by domain/passage when an order is composed; the MODEL has no business with
    // it. If it ever did, a docked fleet's glyph — or a track's first vertex — would move to a
    // point the server did not put her at, and D33's "a pure function of the last read" would have
    // quietly gained a second input.
    //
    // So: move every roadstead five degrees and call it 99 nm out. NOTHING may change.
    const moved = PORTS.map((p) => ({
      ...p,
      roadstead: { lat: p.lat + 5, lon: p.lon + 5 },
      roadsteadNm: 99,
    }))
    const shot = (fleetsAndPorts: ReturnType<typeof buildChartModel>) =>
      JSON.stringify({
        fleets: fleetsAndPorts.fleets,
        roles: [...fleetsAndPorts.portRoles],
        destinations: [...fleetsAndPorts.destinationPoints],
        seaDestinations: fleetsAndPorts.destinationSeaPoints,
        focus: fleetsAndPorts.focusPoints,
        motion: fleetsAndPorts.motionPoints,
      })
    const served = buildChartModel(mapFleetsOf([AURORA, GAIVOTA]), PORTS)
    expect(shot(buildChartModel(mapFleetsOf([AURORA, GAIVOTA]), moved))).toBe(shot(served))
    // …and the fixture really does carry roads that differ from the quays, or the two port tables
    // above would be the same table and this would prove nothing.
    expect(PORTS.filter((p) => p.roadsteadNm > 0).length).toBeGreaterThan(100)
  })

  // ═════════════════════════════════════════════════════════════════════════════════════════════
  // 0075 — SHE MOVES BETWEEN READS, AND SHE CANNOT MOVE FURTHER THAN THE SERVER WILL
  //
  // OWNER_REQUESTS row 50: *"my ship marker should be updated more frequently"*. Measured on
  // production before any of this was written: the marker held one pixel for three seconds, then
  // jumped 25–68 px, six times in a twenty-second passage.
  //
  // The ledger's constraint on the fix is the thing these tests exist to hold: *"a faster marker
  // must be a finer INTERPOLATION of the same authority, never a second mover."* Every property
  // below is a way of saying that once.
  // ═════════════════════════════════════════════════════════════════════════════════════════════
  test.describe('the marker between reads (0075)', () => {
    /** Half a leg still to run, an hour of real time to run it in, and a leg 200 nm long. */
    const DRIFTER: FleetView = sailingFleet({
      id: 'drifter',
      name: 'Drifter',
      from: 'LIS',
      to: 'CAD',
      course: ['LIS', 'CAD', 'CEU'],
      legFrac: 0.5,
      sailedNm: 100,
      totalNm: 300,
      segNm: 200,
      etaMs: 1_700_003_600_000,
    })
    const READ_AT = 1_700_000_000_000
    const voyageOf = (f: FleetView) => {
      const [m] = mapFleetsOf([f])
      if (m.kind !== 'sailing') throw new Error('fixture is not at sea')
      return m.voyage
    }

    test('the served leg and how far along it she is are COPIED, like everything else here', () => {
      const v = voyageOf(DRIFTER)
      expect(v.legFrac).toBe(DRIFTER.voyage!.position!.leg_frac)
      expect(v.segNm).toBe(200)
      // A server that does not serve it yields null, never 0 — 0 is a leg, null is no answer.
      expect(voyageOf(AURORA).segNm).toBeNull()
    })

    test('she advances along the leg as the clock runs, and the advance is the served pace', () => {
      const v = voyageOf(DRIFTER)
      const still = driftedPoint(v, { nowMs: READ_AT, readAtMs: READ_AT })
      expect(still).toEqual(v.at)

      // 200 nm still to run in 3 600 000 ms. After 900 000 ms she has made 50 nm, which on a
      // 200 nm leg is a quarter of it: 0.5 → 0.75. Worked here in the test's own words rather
      // than by re-running the implementation's expression.
      const later = driftedPoint(v, { nowMs: READ_AT + 900_000, readAtMs: READ_AT })
      const a = v.course[v.segIndex]
      const b = v.course[v.segIndex + 1]
      expect(later.lat).toBeCloseTo(a.lat + (b.lat - a.lat) * 0.75, 9)
      expect(later.lon).toBeCloseTo(a.lon + (b.lon - a.lon) * 0.75, 9)
    })

    test('THE CLAMP: she can never be drawn past the vertex the next read will hand back', () => {
      const v = voyageOf(DRIFTER)
      const b = v.course[v.segIndex + 1]
      // A read that never came: an hour late, then a day late. Both stop dead on the vertex —
      // this is the whole reason the file is not a second mover, so it is asserted at the edge
      // and far beyond it rather than just inside.
      for (const late of [3_600_000, 86_400_000, 86_400_000 * 30]) {
        const p = driftedPoint(v, { nowMs: READ_AT + late, readAtMs: READ_AT })
        expect(p.lat).toBeCloseTo(b.lat, 9)
        expect(p.lon).toBeCloseTo(b.lon, 9)
      }
    })

    test('she never goes backwards, and a clock behind the read moves nothing', () => {
      const v = voyageOf(DRIFTER)
      expect(driftedPoint(v, { nowMs: READ_AT - 60_000, readAtMs: READ_AT })).toEqual(v.at)
      let last = 0
      for (const ms of [0, 1_000, 60_000, 300_000, 900_000, 1_800_000]) {
        const p = driftedPoint(v, { nowMs: READ_AT + ms, readAtMs: READ_AT })
        const frac = (p.lat - v.course[v.segIndex].lat) /
          (v.course[v.segIndex + 1].lat - v.course[v.segIndex].lat)
        expect(frac).toBeGreaterThanOrEqual(last - 1e-9)
        last = frac
      }
    })

    test('with nothing to go on it draws her exactly where the server put her', () => {
      const v = voyageOf(DRIFTER)
      // No drift asked for; no read instant; and a server that serves no leg length. Three ways
      // of having no licence to move her, and all three answer with the served point itself.
      expect(driftedPoint(v, null)).toEqual(v.at)
      expect(driftedPoint(v, { nowMs: READ_AT + 900_000, readAtMs: null })).toEqual(v.at)
      expect(
        driftedPoint(voyageOf(AURORA), { nowMs: READ_AT + 900_000, readAtMs: READ_AT }),
      ).toEqual(voyageOf(AURORA).at)
    })

    test('the model moves the WHOLE fleet — glyph, track split and framing are one point', () => {
      const model = buildChartModel(mapFleetsOf([DRIFTER]), PORTS, [], {
        nowMs: READ_AT + 900_000,
        readAtMs: READ_AT,
      })
      const [f] = model.fleets
      const still = buildChartModel(mapFleetsOf([DRIFTER]), PORTS).fleets[0]
      expect(f.at).not.toEqual(still.at)
      // The split is taken AT the drifted point, not at the served one — otherwise the dot would
      // sit off the end of its own sailed track and the panel would disagree with the glyph.
      expect(f.track).not.toEqual(still.track)
      expect(model.focusPoints).toContainEqual(f.at)
      expect(model.motionPoints).toContainEqual(f.at)
    })
  })

  test('only the player’s own fleets are in the model — there is no field for anyone else', () => {
    expect(Object.keys(MODEL)).toEqual([
      'fleets',
      'portRoles',
      'destinationPoints',
      'destinationSeaPoints',
      'focusPoints',
      'motionPoints',
    ])
    expect(MODEL.fleets).toHaveLength(2)
  })

  test('the instant she left is COPIED when served, and absent when it is not (0063)', () => {
    // 0063 put `voyages.departed_at` on the wire so the map can count UP from it. The chart's
    // job is to parse it once and carry it; the elapsed figure itself is one subtraction against
    // the shell clock, exactly as `arrives` is.
    const left = '2026-08-18T04:05:06.000Z'
    const withDeparture: FleetView = {
      ...AURORA,
      voyage: { ...AURORA.voyage!, departed_at: left },
    }
    const mapped = mapFleetsOf([withDeparture])[0]
    expect(mapped.kind).toBe('sailing')
    if (mapped.kind !== 'sailing') throw new Error('unreachable')
    expect(mapped.voyage.departedMs).toBe(Date.parse(left))

    // AND THE OLDER SERVER CASE, which is the one that would go wrong quietly: an absent field
    // must read null, never NaN and never 0 — a fleet counted from 1970 would print an elapsed
    // time of fifty-odd years and look like a clock bug rather than a missing field.
    const older = mapFleetsOf([AURORA])[0]
    if (older.kind !== 'sailing') throw new Error('unreachable')
    expect(AURORA.voyage!.departed_at).toBeUndefined()
    expect(older.voyage.departedMs).toBeNull()
  })

  test('a voyage the server did not place is not parked at a guessed coordinate', () => {
    const unplaced: FleetView = { ...AURORA, voyage: { ...AURORA.voyage!, position: null } }
    expect(mapFleetsOf([unplaced])).toHaveLength(0)
    // …and one that is simply in port is placed on its quay.
    //
    // `enduranceDays` rides on every state because her stores are a fact about the FLEET and not
    // about where she is (mapTypes' FleetStores). It is asserted the way every other figure in
    // this file is — READ OFF THE SERVED PAYLOAD, never restated — so this line goes on proving
    // that the chart COPIES rather than computes, which is the whole point of the file.
    expect(mapFleetsOf([GAIVOTA])).toEqual([
      {
        kind: 'docked',
        id: 'gaivota',
        name: 'Gaivota',
        portCode: 'LIS',
        enduranceDays: GAIVOTA.endurance_days,
      },
    ])
    // …and one at open anchor is drawn exactly where it holds (0039).
    const holdfast = anchoredFleet('h', 'Holdfast', { lat: 33, lon: -15 })
    expect(mapFleetsOf([holdfast])).toEqual([
      {
        kind: 'anchored',
        id: 'h',
        name: 'Holdfast',
        at: { lat: 33, lon: -15 },
        enduranceDays: holdfast.endurance_days,
      },
    ])
  })
})

test.describe('the chart draws the course it was given — whole — and no other water', () => {
  const aurora = () => MODEL.fleets.find((f) => f.fleet.id === 'aurora')!

  test('the track is the WHOLE served course, split at the fleet (0039)', () => {
    const track = aurora().track
    expect(track).not.toBeNull()
    const from = project(LISBON)
    const cadiz = project(CADIZ)
    const ceuta = project(portAt('CEU'))
    const at = project(aurora().at)
    const line = (pts: { x: number; y: number }[]) =>
      `M${round(pts[0].x)} ${round(pts[0].y)}` +
      pts.slice(1).map((q) => `L${round(q.x)} ${round(q.y)}`).join('')
    // Sailed: the course up to her segment, then the ship. Ahead: the ship, then EVERYTHING the
    // server said she will sail — including Ceuta, which the old leg model could not draw.
    expect(track!.sailedD).toBe(line([from, at]))
    expect(track!.aheadD).toBe(line([at, cadiz, ceuta]))
  })

  test('the ship sits ON its own track — the client geometry is the server’s geometry', () => {
    // `voyage.position()` interpolates LINEARLY in lat/lon along the segment — the same
    // interpolation the server's water law samples (0039), and on an equirectangular chart the
    // straight stroke ./route.ts draws. A great-circle arc would bow away from the very point
    // the server put the ship at. This is the seam, asserted rather than assumed.
    const at = aurora().at
    const t = AURORA.voyage!.position!.leg_frac
    expect(at.lat).toBeCloseTo(LISBON.lat + (CADIZ.lat - LISBON.lat) * t, 3)
    expect(at.lon).toBeCloseTo(LISBON.lon + (CADIZ.lon - LISBON.lon) * t, 3)
  })

  test('the destination is RINGED, and — new under 0039 — the water to it is drawn too', () => {
    expect(aurora().destinationCode).toBe('CEU')
    expect([...MODEL.destinationPoints.keys()]).toEqual(['CEU'])
    const ceuta = portAt('CEU')
    expect(MODEL.destinationPoints.get('CEU')).toEqual({ lat: ceuta.lat, lon: ceuta.lon })
  })

  test('a bare-water destination is ringed at its point (0039)', () => {
    const toSea = buildChartModel(
      mapFleetsOf([
        sailingFleet({
          id: 's',
          name: 'Sonda',
          from: 'LIS',
          to: 'LIS',
          course: ['LIS'],
          toPoint: { lat: 33, lon: -15 },
          legFrac: 0.5,
        }),
      ]),
      PORTS,
    )
    expect(toSea.destinationSeaPoints).toEqual([{ lat: 33, lon: -15 }])
    expect(toSea.destinationPoints.size).toBe(0)
    const [f] = toSea.fleets
    expect(f.destinationCode).toBeNull()
    expect(f.voyage!.destPoint).toEqual({ lat: 33, lon: -15 })
  })

  test('the destination ring is placed once per port, not once per fleet', () => {
    const two = buildChartModel(
      mapFleetsOf([
        AURORA,
        sailingFleet({ id: 'b', name: 'Bonança', from: 'SAF', to: 'CEU', legFrac: 0.2 }),
      ]),
      PORTS,
    )
    expect(two.destinationPoints.size).toBe(1)
  })

  test('a docked fleet gets no track and no destination', () => {
    const docked = MODEL.fleets.find((f) => f.fleet.id === 'gaivota')!
    expect(docked.track).toBeNull()
    expect(docked.voyage).toBeNull()
    expect(docked.destinationCode).toBeNull()
    expect(docked.dockedAtCode).toBe('LIS')
  })

  test('port roles rank correctly, and a port no fleet touches has none', () => {
    expect(MODEL.portRoles.get('CEU')).toBe('destination') // Aurora is bound there
    expect(MODEL.portRoles.get('LIS')).toBe('anchorage') // Gaivota lies there, and Aurora left it
    // 0039: the 'route' role is retired with the leg graph — a waypoint on a free course is not
    // a port fact any more, so Cádiz (mid-course) is quiet unless something else makes it loud.
    expect(MODEL.portRoles.get('CAD')).toBeUndefined()
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
