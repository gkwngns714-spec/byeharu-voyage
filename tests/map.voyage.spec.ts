import { test, expect } from '@playwright/test'
import { haversineNm, project, type LatLon } from '../src/lib/geo'
import { TIME_COMPRESSION, formatEta, voyagePoint, voyageProgress } from '../src/features/map/voyage'
import { buildChartModel } from '../src/features/map/chartModel'
import { hitTest, toggleSelection } from '../src/features/map/hitTest'
import { GLYPH } from '../src/features/map/glyphs'
import { V0_PORTS, sampleFleets } from '../src/features/map/sampleVoyages'
import type { Voyage } from '../src/features/map/mapTypes'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE CLOSED FORM IS A PURE FUNCTION — DESIGN §D.2, proved rather than asserted in a comment.
//
// This is the single most important property on the map. If position were ever a function of
// anything but (voyage, instant) — a counter, a previous frame, a timer's drift — then tabbing
// away, throttling, or a dropped frame would move a fleet, and the client's picture would stop
// matching the server's answer. Every test below is an attack on that.
//
// Pure Node: no `page` fixture is used, so no browser is launched.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const LISBOA: LatLon = { lat: 38.71, lon: -9.14 }
const CADIZ: LatLon = { lat: 36.53, lon: -6.29 }
const CEUTA: LatLon = { lat: 35.89, lon: -5.32 }

const DEPARTED = 1_700_000_000_000

/** §B.3's Lisboa → Cádiz → Ceuta, 249 nm at a frozen 5 knots. */
const VOYAGE: Voyage = {
  departedAtMs: DEPARTED,
  legs: [
    { fromPort: 'LIS', toPort: 'CAD', distanceNm: 188, speedKn: 5 },
    { fromPort: 'CAD', toPort: 'CEU', distanceNm: 61, speedKn: 5 },
  ],
}
const WAYPOINTS = [LISBOA, CADIZ, CEUTA]

/** Real milliseconds for a number of voyage-hours, at §D.1's compression of 480. */
const realMsForSimHours = (hours: number) => (hours * 3_600_000) / TIME_COMPRESSION

test.describe('voyageProgress is a pure function of elapsed time', () => {
  test('same input, same output — called repeatedly, and out of order', () => {
    const instant = DEPARTED + 90_000
    const first = voyageProgress(VOYAGE, instant)

    // Ten more calls at the same instant.
    for (let i = 0; i < 10; i++) expect(voyageProgress(VOYAGE, instant)).toEqual(first)

    // And after being called at OTHER instants in between — if anything were cached or
    // accumulated, this is where it would show.
    voyageProgress(VOYAGE, DEPARTED)
    voyageProgress(VOYAGE, DEPARTED + 10_000_000)
    voyageProgress(VOYAGE, DEPARTED - 5_000)
    expect(voyageProgress(VOYAGE, instant)).toEqual(first)
  })

  test('the result depends on nothing outside its arguments', () => {
    // Sampling the same instant from two objects with identical values must agree — the function
    // may not close over identity, insertion order, or anything it was handed earlier.
    const twin: Voyage = { departedAtMs: DEPARTED, legs: VOYAGE.legs.map((l) => ({ ...l })) }
    const instant = DEPARTED + 120_000
    expect(voyageProgress(twin, instant)).toEqual(voyageProgress(VOYAGE, instant))
  })

  test('a jump forward and a walk forward land in the same place', () => {
    // THE DRIFT TEST. One caller sampled every 16 ms for the whole passage (a tab that stayed
    // open); another sampled once at the end (a tab that was asleep). They must agree exactly.
    const end = DEPARTED + realMsForSimHours(30)
    for (let t = DEPARTED; t < end; t += 16) voyageProgress(VOYAGE, t)
    const walked = voyageProgress(VOYAGE, end)
    const jumped = voyageProgress({ ...VOYAGE }, end)
    expect(walked).toEqual(jumped)
  })

  test('progress is monotonic — time only ever moves a fleet forward', () => {
    let previous = -1
    for (let hours = 0; hours <= 60; hours += 0.25) {
      const p = voyageProgress(VOYAGE, DEPARTED + realMsForSimHours(hours))
      expect(p.sailedNm).toBeGreaterThanOrEqual(previous)
      previous = p.sailedNm
    }
  })
})

test.describe('voyageProgress numbers match DESIGN §B.3 and §D.1', () => {
  test('at departure, nothing is sailed', () => {
    const p = voyageProgress(VOYAGE, DEPARTED)
    expect(p.sailedNm).toBe(0)
    expect(p.fraction).toBe(0)
    expect(p.legIndex).toBe(0)
    expect(p.legFraction).toBe(0)
    expect(p.arrived).toBe(false)
    expect(p.totalNm).toBe(249)
  })

  test('249 nm at 5 knots is 49.8 voyage-hours — §D.4 calls that a ~6 minute passage', () => {
    const p = voyageProgress(VOYAGE, DEPARTED)
    expect(p.totalSimHours).toBeCloseTo(249 / 5, 9)
    const realMinutes = (p.etaMs - DEPARTED) / 60_000
    expect(realMinutes).toBeCloseTo(6.225, 3)
  })

  test('after 18.8 voyage-hours the fleet is 94 nm out — exactly half of the first leg', () => {
    const p = voyageProgress(VOYAGE, DEPARTED + realMsForSimHours(94 / 5))
    expect(p.sailedNm).toBeCloseTo(94, 6)
    expect(p.legIndex).toBe(0)
    expect(p.legFraction).toBeCloseTo(0.5, 6)
  })

  test('crossing into the second leg is continuous, not a jump', () => {
    const atJoint = voyageProgress(VOYAGE, DEPARTED + realMsForSimHours(188 / 5))
    expect(atJoint.sailedNm).toBeCloseTo(188, 6)
    expect(atJoint.legIndex).toBe(1)
    expect(atJoint.legFraction).toBeCloseTo(0, 6)

    const justBefore = voyageProgress(VOYAGE, DEPARTED + realMsForSimHours(188 / 5) - 1)
    expect(Math.abs(justBefore.sailedNm - atJoint.sailedNm)).toBeLessThan(0.01)
  })

  test('past the ETA it is arrived and pinned to the destination — never past it', () => {
    const p = voyageProgress(VOYAGE, DEPARTED + realMsForSimHours(10_000))
    expect(p.arrived).toBe(true)
    expect(p.fraction).toBe(1)
    expect(p.sailedNm).toBe(249)
    expect(p.remainingNm).toBe(0)
    expect(p.remainingMs).toBe(0)
  })

  test('a clock behind the departure draws the fleet on the quay it left, not behind it', () => {
    const p = voyageProgress(VOYAGE, DEPARTED - 60 * 60 * 1000)
    expect(p.sailedNm).toBe(0)
    expect(p.fraction).toBe(0)
  })

  test('a voyage with no legs is arrived, not NaN', () => {
    const p = voyageProgress({ departedAtMs: DEPARTED, legs: [] }, DEPARTED + 1000)
    expect(p.arrived).toBe(true)
    expect(Number.isNaN(p.fraction)).toBe(false)
    expect(p.totalNm).toBe(0)
  })

  test('a non-positive frozen speed stalls the fleet instead of producing NaN', () => {
    const broken: Voyage = {
      departedAtMs: DEPARTED,
      legs: [{ fromPort: 'LIS', toPort: 'CAD', distanceNm: 188, speedKn: 0 }],
    }
    const p = voyageProgress(broken, DEPARTED + 10_000_000)
    expect(Number.isNaN(p.sailedNm)).toBe(false)
    expect(p.sailedNm).toBe(0)
    expect(p.arrived).toBe(false)
  })
})

test.describe('voyagePoint puts the glyph on the track', () => {
  test('at departure it is on the first quay; at arrival, the last', () => {
    const start = voyagePoint(voyageProgress(VOYAGE, DEPARTED), WAYPOINTS)
    expect(haversineNm(start, LISBOA)).toBeCloseTo(0, 6)

    const end = voyagePoint(voyageProgress(VOYAGE, DEPARTED + realMsForSimHours(1000)), WAYPOINTS)
    expect(haversineNm(end, CEUTA)).toBeCloseTo(0, 6)
  })

  test('halfway down the first leg it is 94 nm from Lisboa and 94 from Cádiz', () => {
    const at = voyagePoint(voyageProgress(VOYAGE, DEPARTED + realMsForSimHours(94 / 5)), WAYPOINTS)
    expect(haversineNm(LISBOA, at)).toBeCloseTo(94, 0)
    expect(haversineNm(at, CADIZ)).toBeCloseTo(94, 0)
  })

  test('the position is a pure function too', () => {
    const instant = DEPARTED + 100_000
    const a = voyagePoint(voyageProgress(VOYAGE, instant), WAYPOINTS)
    voyagePoint(voyageProgress(VOYAGE, instant + 500_000), WAYPOINTS)
    const b = voyagePoint(voyageProgress(VOYAGE, instant), WAYPOINTS)
    expect(b).toEqual(a)
  })
})

test.describe('the whole picture is derived, and holds no one else', () => {
  test('buildChartModel at one instant is reproducible', () => {
    const fleets = sampleFleets(DEPARTED)
    const instant = DEPARTED + 90_000
    const first = buildChartModel(fleets, V0_PORTS, instant)
    buildChartModel(fleets, V0_PORTS, instant + 400_000)
    const again = buildChartModel(fleets, V0_PORTS, instant)
    expect(again.fleets.map((f) => f.at)).toEqual(first.fleets.map((f) => f.at))
    expect([...again.portRoles].sort()).toEqual([...first.portRoles].sort())
  })

  test('only the player’s own fleets are in the model — there is no field for anyone else', () => {
    const model = buildChartModel(sampleFleets(DEPARTED), V0_PORTS, DEPARTED + 60_000)
    expect(model.fleets).toHaveLength(4)
    expect(Object.keys(model)).toEqual([
      'fleets',
      'portRoles',
      'destinationPoints',
      'focusPoints',
      'motionPoints',
    ])
  })

  test('a fleet at sea gets a split track; a docked one gets none', () => {
    const model = buildChartModel(sampleFleets(DEPARTED), V0_PORTS, DEPARTED + 60_000)
    const atSea = model.fleets.filter((f) => f.dockedAtCode === null)
    const docked = model.fleets.filter((f) => f.dockedAtCode !== null)
    expect(atSea.length).toBeGreaterThan(0)
    expect(docked.length).toBeGreaterThan(0)
    for (const f of atSea) {
      expect(f.track).not.toBeNull()
      expect(f.track?.sailedD.startsWith('M')).toBe(true)
      expect(f.track?.aheadD.startsWith('M')).toBe(true)
    }
    for (const f of docked) expect(f.track).toBeNull()
  })

  test('the destination ring is placed once per port, not once per fleet', () => {
    const model = buildChartModel(sampleFleets(DEPARTED), V0_PORTS, DEPARTED + 60_000)
    // Two sample voyages, two different destinations.
    expect(model.destinationPoints.size).toBe(2)
  })

  test('port roles rank correctly, and a port no fleet touches has none', () => {
    const model = buildChartModel(sampleFleets(DEPARTED), V0_PORTS, DEPARTED + 60_000)
    expect(model.portRoles.get('CEU')).toBe('destination') // Aurora is bound there
    expect(model.portRoles.get('LPA')).toBe('destination') // Ponente is bound there
    expect(model.portRoles.get('LIS')).toBe('anchorage') // Gaivota lies there, and 2 routes start there
    expect(model.portRoles.get('GOA')).toBe('anchorage') // Levante lies there
    expect(model.portRoles.get('CAD')).toBe('route') // Aurora passes through
    expect(model.portRoles.get('SVQ')).toBeUndefined() // nothing of yours goes near Sevilla
    expect(model.portRoles.get('NAP')).toBeUndefined()
  })

  test('the opening frame is what is HAPPENING, not the whole port table', () => {
    const model = buildChartModel(sampleFleets(DEPARTED), V0_PORTS, DEPARTED + 60_000)
    // Fleet positions, destinations and anchorages — never a port nothing of yours touches.
    const points = model.focusPoints
    expect(points.length).toBeGreaterThan(0)
    const napoli = V0_PORTS.find((p) => p.code === 'NAP')
    expect(points.some((p) => p.lat === napoli?.lat && p.lon === napoli?.lon)).toBe(false)
  })

  test('with no fleets the whole port table stands in, so the map never opens on empty ocean', () => {
    const model = buildChartModel([], V0_PORTS, DEPARTED)
    expect(model.focusPoints).toHaveLength(V0_PORTS.length)
  })
})

test.describe('formatEta says it in as few words as possible', () => {
  test('minutes, hours, days — and never a negative clock', () => {
    expect(formatEta(0)).toBe('now')
    expect(formatEta(-5000)).toBe('now')
    expect(formatEta(60_000)).toBe('1m')
    expect(formatEta(11 * 60_000)).toBe('11m')
    expect(formatEta(60 * 60_000)).toBe('1h')
    expect(formatEta(72 * 60_000)).toBe('1h 12m')
    expect(formatEta(27 * 60 * 60_000)).toBe('1d 3h')
  })
})

test.describe('hitTest — nearest wins, at every zoom', () => {
  const MODEL = buildChartModel(sampleFleets(DEPARTED), V0_PORTS, DEPARTED + 60_000)
  const port = (code: string) => {
    const found = V0_PORTS.find((p) => p.code === code)
    if (!found) throw new Error(code)
    return found
  }

  // The opening view of a 390 px phone: 38.66 deg across, so 1 px = 0.099 deg. At that scale a
  // 44 px reach is 2.18 deg — and Cadiz to Sevilla is 54 nm, about 0.9 deg. Overlapping touch
  // circles would make paint order decide; nearest must not.
  const PHONE_UNITS_PER_PX = 38.66 / 390
  const REACH = GLYPH.hitRadius * PHONE_UNITS_PER_PX

  test('a tap ON a port picks THAT port, not its crowded neighbour', () => {
    expect(hitTest(MODEL, V0_PORTS, project(port('CAD')), REACH)).toEqual({ kind: 'port', code: 'CAD' })
    expect(hitTest(MODEL, V0_PORTS, project(port('SVQ')), REACH)).toEqual({ kind: 'port', code: 'SVQ' })
    // Both are well inside one reach of each other, which is the case that used to be a coin toss.
    const apart = Math.hypot(port('CAD').lon - port('SVQ').lon, port('CAD').lat - port('SVQ').lat)
    expect(apart).toBeLessThan(REACH)
  })

  test('a tap between two ports picks the closer one', () => {
    const a = project(port('CAD'))
    const b = project(port('SVQ'))
    const nearCadiz = { x: a.x + (b.x - a.x) * 0.3, y: a.y + (b.y - a.y) * 0.3 }
    const nearSevilla = { x: a.x + (b.x - a.x) * 0.7, y: a.y + (b.y - a.y) * 0.7 }
    expect(hitTest(MODEL, V0_PORTS, nearCadiz, REACH)).toEqual({ kind: 'port', code: 'CAD' })
    expect(hitTest(MODEL, V0_PORTS, nearSevilla, REACH)).toEqual({ kind: 'port', code: 'SVQ' })
  })

  test('a fleet at anchor wins the tie with the port it lies in', () => {
    // Gaivota is docked at Lisboa, so both are at exactly the same point.
    expect(hitTest(MODEL, V0_PORTS, project(port('LIS')), REACH)).toEqual({ kind: 'fleet', id: 'gaivota' })
  })

  test('open water selects nothing', () => {
    expect(hitTest(MODEL, V0_PORTS, { x: -40, y: -20 }, REACH)).toBeNull()
  })

  test('the reach is a distance, so it shrinks with the scale as the chart zooms in', () => {
    const justOutside = project(port('CAD'))
    const nudged = { x: justOutside.x + REACH * 2, y: justOutside.y }
    expect(hitTest(MODEL, V0_PORTS, nudged, REACH)).not.toEqual({ kind: 'port', code: 'CAD' })
    // Zoomed in 10x, the same 44 px is a tenth of the ground, so a far tap misses everything.
    expect(hitTest(MODEL, V0_PORTS, nudged, REACH / 10)).toBeNull()
  })
})

test.describe('toggleSelection', () => {
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
})
