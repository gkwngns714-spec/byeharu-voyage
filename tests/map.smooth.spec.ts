import { test, expect } from '@playwright/test'
import {
  buildChartModel,
  driftedPoint,
  glideShare,
  mapFleetsOf,
  mapPortsOf,
  UNDERWAY_GLIDE_MS,
  UNDERWAY_SNAP_DEG,
  underwayStep,
} from '../src/chart'
import type { FleetView } from '../src/lib/rpc'
import { REAL_PORTS, dockedFleet, sailingFleet } from './mapWorld.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// SHE GLIDES — the owner, OWNER_REQUESTS row 169 (2026-10-20): *"I want the ship movement to be
// smooth, not by ticks."*
//
// 0075 already drew her between READS. What ticked was the model: it is a function of the shell's
// one clock, and that clock ticks once a second, so a hull held still for a second and then
// stepped. src/chart/underway.ts moves her in between, on one animation frame for the whole sheet,
// at ./drift.ts's own point for the frame's instant.
//
// The properties below are the whole of what that file is allowed to be. Three of them are about
// what it may NOT do — pass her arrival, snap when a read disagrees, or sweep the sheet at the
// seam — because "smooth" is only an improvement if she is still exactly where the server says.
//
// Pure Node: no `page` fixture is used, so no browser is launched. Nothing here measures a frame
// rate — a wall-clock threshold on a shared runner is a flake (tests/map.lag.spec.ts's header);
// what is held is the arithmetic that a frame carries out.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const PORTS = mapPortsOf(REAL_PORTS)
const READ_AT = 1_700_000_000_000

/** A LONG first leg: 200 nm still to run in an hour, on a 2 000 nm segment. The leg's far vertex is
 *  therefore nowhere near, so the 0075 clamp cannot be what stops her — only the arrival can. */
const LONG_LEG: FleetView = sailingFleet({
  id: 'patience',
  name: 'Patience',
  from: 'LIS',
  to: 'CAD',
  course: ['LIS', 'CAD', 'CEU'],
  legFrac: 0.5,
  sailedNm: 100,
  totalNm: 300,
  segNm: 2_000,
  etaMs: READ_AT + 3_600_000,
})

const voyageOf = (f: FleetView) => {
  const [m] = mapFleetsOf([f])
  if (m.kind !== 'sailing') throw new Error('fixture is not at sea')
  return m.voyage
}

test.describe('she stops when she arrives', () => {
  test('the drift reads no clock past the served arrival instant', () => {
    const v = voyageOf(LONG_LEG)
    const arrived = driftedPoint(v, { nowMs: v.etaMs, readAtMs: READ_AT })
    // 200 nm covered on a 2 000 nm segment is a tenth of it: 0.5 → 0.6, which is well short of the
    // vertex. So the only thing that can hold her here is the arrival instant.
    const a = v.course[v.segIndex]
    const b = v.course[v.segIndex + 1]
    expect(arrived.lat).toBeCloseTo(a.lat + (b.lat - a.lat) * 0.6, 9)
    // An hour late, a day late, a month late: the same point, which is the quay she reached.
    for (const late of [1, 60_000, 3_600_000, 86_400_000 * 30]) {
      const p = driftedPoint(v, { nowMs: v.etaMs + late, readAtMs: READ_AT })
      expect(p.lat).toBeCloseTo(arrived.lat, 9)
      expect(p.lon).toBeCloseTo(arrived.lon, 9)
    }
    // …and she really was still moving a minute before it, or the assertion above would hold for
    // a hull that had stopped long since and prove nothing about the arrival.
    expect(driftedPoint(v, { nowMs: v.etaMs - 60_000, readAtMs: READ_AT }).lat).not.toBeCloseTo(arrived.lat, 9)
  })
})

test.describe('a frame’s arithmetic (underwayStep)', () => {
  const share = glideShare(1_000 + 1000 / 60, 1_000, UNDERWAY_GLIDE_MS)

  test('one frame pays part of what is owed, and the first frame pays something', () => {
    expect(share).toBeGreaterThan(0)
    expect(share).toBeLessThan(1)
    // A rAF timestamp is the frame's START and can be earlier than the clock a handler just read:
    // the elapsed time is floored at one frame, so no frame ever pays a NEGATIVE share.
    expect(glideShare(900, 1_000, UNDERWAY_GLIDE_MS)).toBeGreaterThan(0)
  })

  test('her first frame puts her exactly where the served figures say', () => {
    const target = { lat: 38, lon: -9 }
    expect(underwayStep(null, target, share)).toEqual(target)
  })

  test('a read that disagrees is ABSORBED, not snapped — and she lands on it', () => {
    const target = { lat: 38, lon: -9 }
    // A sixth of a degree is about ten nautical miles: the most a read can disagree with this
    // chart's own pace after one beat of the shell.
    let drawn = { lat: 38, lon: -9 - 1 / 6 }
    const first = underwayStep(drawn, target, share)
    const gap = Math.abs(drawn.lon - target.lon)
    // The first frame moves her a small fraction of the way — not the whole way, which would be
    // the jump this slice removes, and not nothing.
    expect(Math.abs(first.lon - drawn.lon)).toBeLessThan(gap / 2)
    expect(Math.abs(first.lon - drawn.lon)).toBeGreaterThan(0)
    let last = drawn.lon
    for (let i = 0; i < 60; i++) {
      drawn = underwayStep(drawn, target, share)
      // Always toward it, never past it: her longitude rises monotonically and stays west of the
      // target until it reaches it.
      expect(drawn.lon).toBeGreaterThanOrEqual(last)
      expect(drawn.lon).toBeLessThanOrEqual(target.lon + 1e-12)
      last = drawn.lon
    }
    // One second of frames is a correction the eye has seen the end of.
    expect(Math.abs(drawn.lon - target.lon)).toBeLessThan(gap / 100)
  })

  test('a gap too big to be a correction is taken at once', () => {
    const target = { lat: 38, lon: -9 }
    const elsewhere = { lat: 38, lon: -9 - UNDERWAY_SNAP_DEG - 0.01 }
    expect(underwayStep(elsewhere, target, share)).toEqual(target)
    // Just inside it is eased, so the rule is a threshold and not a shrug.
    const near = { lat: 38, lon: -9 - UNDERWAY_SNAP_DEG + 0.01 }
    expect(underwayStep(near, target, share).lon).toBeLessThan(target.lon)
  })

  test('a correction across the antimeridian closes the SHORT way, and stays on the sheet', () => {
    // Drawn just west of the seam, served just east of it: 0.2° apart, not 359.8°.
    const drawn = { lat: 10, lon: 179.9 }
    const target = { lat: 10, lon: -179.9 }
    let at = drawn
    for (let i = 0; i < 60; i++) at = underwayStep(at, target, share)
    expect(Math.abs(at.lon)).toBeGreaterThan(179.8)
    expect(at.lon).toBeGreaterThanOrEqual(-180)
    expect(at.lon).toBeLessThanOrEqual(180)
    // And one frame of it never leaves the neighbourhood of the seam.
    const one = underwayStep(drawn, target, share)
    expect(Math.abs(one.lon)).toBeGreaterThan(179.8)
  })

  test('nonsense moves nothing: no share, no step', () => {
    const drawn = { lat: 38, lon: -9 }
    // Near enough to be a correction, so it is the share being asked about and not the snap.
    const target = { lat: 38.1, lon: -8.9 }
    expect(underwayStep(drawn, target, Number.NaN)).toEqual(target)
    expect(underwayStep(drawn, target, 0)).toEqual(drawn)
    expect(underwayStep(drawn, target, 1)).toEqual(target)
  })
})

test.describe('the model carries the instant her figures were true', () => {
  test('a fleet at sea carries the read’s instant; a fleet at a quay carries none', () => {
    const model = buildChartModel(mapFleetsOf([LONG_LEG, dockedFleet('gaivota', 'Gaivota', 'LIS')]), PORTS, [], {
      nowMs: READ_AT + 1_000,
      readAtMs: READ_AT,
    })
    const sailing = model.fleets.find((f) => f.fleet.id === 'patience')
    const docked = model.fleets.find((f) => f.fleet.id === 'gaivota')
    expect(sailing?.readAtMs).toBe(READ_AT)
    expect(docked?.readAtMs).toBeNull()
  })

  test('a model asked for no clock carries no instant — there is nothing to glide', () => {
    const still = buildChartModel(mapFleetsOf([LONG_LEG]), PORTS)
    expect(still.fleets[0].readAtMs).toBeNull()
    // The clock-free model is still the server's point, byte for byte (tests/map.voyage.spec.ts
    // holds the rest of that promise).
    expect(still.fleets[0].at).toEqual(voyageOf(LONG_LEG).at)
  })
})
