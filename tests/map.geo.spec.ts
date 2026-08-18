import { test, expect } from '@playwright/test'
import {
  CHART_WIDTH,
  WORLD_BOUNDS,
  boundsOf,
  cumulativeNm,
  densifyGreatCircle,
  fitToViewBox,
  haversineNm,
  interpolateAlongPath,
  interpolateGreatCircle,
  pathLengthNm,
  project,
  simplifyPath,
  unproject,
  unwrapLongitudes,
  type LatLon,
} from '../src/lib/geo'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// PURE PROOFS — no browser, no server, no DOM. `npx playwright test tests/map.geo.spec.ts` runs
// these as plain Node: nothing here touches a `page` fixture, so Playwright never launches a
// browser (which is why they pass on a machine with no browser binaries installed).
//
// What they are actually for: src/lib/geo is the ONE authority for geography, and the numbers it
// produces have to be the same numbers DESIGN §B.3 publishes and the same ones the SQL will
// compute. This file is where that stops being an intention.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const LISBOA: LatLon = { lat: 38.71, lon: -9.14 }
const CADIZ: LatLon = { lat: 36.53, lon: -6.29 }
const CEUTA: LatLon = { lat: 35.89, lon: -5.32 }
const FUNCHAL: LatLon = { lat: 32.65, lon: -16.91 }
const LAS_PALMAS: LatLon = { lat: 28.13, lon: -15.43 }
const MARSEILLE: LatLon = { lat: 43.3, lon: 5.37 }

// ── the projection round-trips ────────────────────────────────────────────────────────────────

test.describe('projection', () => {
  test('project → unproject returns the same point, everywhere', () => {
    // A spread that includes the poles, the antimeridian, the equator and the game's own water.
    const samples: LatLon[] = [
      { lat: 0, lon: 0 },
      { lat: 90, lon: 180 },
      { lat: -90, lon: -180 },
      { lat: 38.71, lon: -9.14 },
      { lat: -33.92, lon: 18.42 },
      { lat: 71.2, lon: -156.77 },
      { lat: 1.29, lon: 103.85 },
      { lat: -0.0001, lon: 179.9999 },
    ]
    for (const point of samples) {
      const back = unproject(project(point))
      expect(back.lat, `lat of ${JSON.stringify(point)}`).toBeCloseTo(point.lat, 10)
      expect(back.lon, `lon of ${JSON.stringify(point)}`).toBeCloseTo(point.lon, 10)
    }
  })

  test('the chart is one unit per degree, y down', () => {
    expect(project({ lat: 0, lon: 0 }).x).toBeCloseTo(0, 12)
    expect(project({ lat: 0, lon: 0 }).y).toBeCloseTo(0, 12)
    // North is UP: a point 10° further north has a SMALLER y.
    expect(project({ lat: 10, lon: 0 }).y).toBeLessThan(project({ lat: 0, lon: 0 }).y)
    // East is RIGHT.
    expect(project({ lat: 0, lon: 10 }).x).toBeGreaterThan(project({ lat: 0, lon: 0 }).x)
    // One degree of longitude is one chart unit, at every latitude.
    expect(project({ lat: 60, lon: 11 }).x - project({ lat: 60, lon: 10 }).x).toBeCloseTo(1, 12)
  })

  test('fitToViewBox contains the bounds and matches the surface aspect', () => {
    const bounds = boundsOf([LISBOA, CADIZ, MARSEILLE, LAS_PALMAS])
    expect(bounds).not.toBeNull()
    if (!bounds) return

    for (const aspect of [390 / 640, 1, 16 / 9, 3]) {
      const box = fitToViewBox(bounds, aspect, 0.1)
      expect(box.width / box.height, `aspect ${aspect}`).toBeCloseTo(aspect, 9)
      // Every corner of the requested rectangle is inside the fitted box.
      expect(box.x).toBeLessThanOrEqual(bounds.minLon)
      expect(box.x + box.width).toBeGreaterThanOrEqual(bounds.maxLon)
      expect(box.y).toBeLessThanOrEqual(-bounds.maxLat)
      expect(box.y + box.height).toBeGreaterThanOrEqual(-bounds.minLat)
    }
  })

  test('the whole world fits in a 360-unit-wide box', () => {
    const box = fitToViewBox(WORLD_BOUNDS, 2, 0)
    expect(box.width).toBeCloseTo(CHART_WIDTH, 9)
    expect(box.height).toBeCloseTo(180, 9)
  })

  test('boundsOf returns null rather than a silent world view for no points', () => {
    expect(boundsOf([])).toBeNull()
  })

  test('unwrapLongitudes turns an antimeridian crossing into a short hop', () => {
    const unwrapped = unwrapLongitudes([
      { lat: 0, lon: 179 },
      { lat: 0, lon: -179 },
    ])
    // Naively that is a 358° sweep across the whole chart; unwrapped it is 2°.
    expect(Math.abs(unwrapped[1].lon - unwrapped[0].lon)).toBeCloseTo(2, 9)
  })
})

// ── haversine matches the published table ─────────────────────────────────────────────────────

test.describe('haversine, against DESIGN §B.3', () => {
  // §B.3's "worked distances", computed from §B.2's coordinate table. The doc rounds to whole
  // nautical miles, so 1 nm is the tolerance — anything looser would not be a proof of agreement.
  const PUBLISHED: readonly { leg: string; from: LatLon; to: LatLon; nm: number }[] = [
    { leg: 'Lisboa → Cádiz', from: LISBOA, to: CADIZ, nm: 188 },
    { leg: 'Cádiz → Ceuta', from: CADIZ, to: CEUTA, nm: 61 },
    { leg: 'Lisboa → Funchal', from: LISBOA, to: FUNCHAL, nm: 525 },
    { leg: 'Lisboa → Marseille', from: LISBOA, to: MARSEILLE, nm: 712 },
    { leg: 'Lisboa → Las Palmas', from: LISBOA, to: LAS_PALMAS, nm: 709 },
    { leg: 'Ceuta → Tunis', from: CEUTA, to: { lat: 36.8, lon: 10.18 }, nm: 751 },
    { leg: 'Lisboa → Amsterdam', from: LISBOA, to: { lat: 52.37, lon: 4.9 }, nm: 1007 },
    { leg: 'Venezia → Alexandria', from: { lat: 45.44, lon: 12.34 }, to: { lat: 31.2, lon: 29.92 }, nm: 1185 },
    { leg: 'Cádiz → Havana', from: CADIZ, to: { lat: 23.11, lon: -82.37 }, nm: 3944 },
    { leg: 'Cidade do Cabo → Goa', from: { lat: -33.92, lon: 18.42 }, to: { lat: 15.5, lon: 73.83 }, nm: 4338 },
    { leg: 'Lisboa → Malaca (great circle)', from: LISBOA, to: { lat: 2.19, lon: 102.25 }, nm: 6310 },
  ]

  for (const { leg, from, to, nm } of PUBLISHED) {
    test(`${leg} = ${nm} nm`, () => {
      // The doc rounds to whole nautical miles, so agreement means within 1 nm. Anything looser
      // would not be a proof that the two implementations are the same formula.
      expect(Math.abs(haversineNm(from, to) - nm)).toBeLessThanOrEqual(1)
    })
  }

  test('distance is symmetric and zero to itself', () => {
    expect(haversineNm(LISBOA, CADIZ)).toBeCloseTo(haversineNm(CADIZ, LISBOA), 9)
    expect(haversineNm(LISBOA, LISBOA)).toBe(0)
  })

  test('pathLengthNm adds the legs up', () => {
    const path = [LISBOA, CADIZ, CEUTA]
    expect(pathLengthNm(path)).toBeCloseTo(haversineNm(LISBOA, CADIZ) + haversineNm(CADIZ, CEUTA), 9)
    expect(cumulativeNm(path)).toHaveLength(3)
    expect(cumulativeNm(path)[0]).toBe(0)
    expect(cumulativeNm(path)[2]).toBeCloseTo(pathLengthNm(path), 9)
  })
})

// ── interpolation lands where it should ───────────────────────────────────────────────────────

test.describe('interpolateAlongPath', () => {
  const PATH = [LISBOA, CADIZ, CEUTA] // 188 + 61 = 249 nm, per §B.3

  test('fraction 0 is the first waypoint', () => {
    const at = interpolateAlongPath(PATH, 0)
    expect(at.lat).toBeCloseTo(LISBOA.lat, 9)
    expect(at.lon).toBeCloseTo(LISBOA.lon, 9)
  })

  test('fraction 1 is the last waypoint', () => {
    const at = interpolateAlongPath(PATH, 1)
    expect(at.lat).toBeCloseTo(CEUTA.lat, 9)
    expect(at.lon).toBeCloseTo(CEUTA.lon, 9)
  })

  test('fraction 0.5 is half the DISTANCE along, not half the waypoints', () => {
    const total = pathLengthNm(PATH)
    const at = interpolateAlongPath(PATH, 0.5)

    // Half of 249 nm is 124.5 nm — which is still on the FIRST leg (188 nm). A naive
    // "half the waypoints" reading would put it at Cádiz, 188 nm along; this asserts it does not.
    const sailed = haversineNm(LISBOA, at)
    expect(sailed).toBeCloseTo(total / 2, 0)
    expect(haversineNm(at, CADIZ)).toBeGreaterThan(50)

    // And it really is between the two, not off to one side.
    expect(sailed + haversineNm(at, CADIZ)).toBeCloseTo(haversineNm(LISBOA, CADIZ), 0)
  })

  test('the midpoint of a single long leg is equidistant from both ends', () => {
    const leg = [CADIZ, { lat: 23.11, lon: -82.37 }] // Cádiz → Havana, 3,944 nm
    const middle = interpolateAlongPath(leg, 0.5)
    expect(haversineNm(leg[0], middle)).toBeCloseTo(haversineNm(middle, leg[1]), 3)
  })

  test('fractions outside [0, 1] are clamped, never extrapolated', () => {
    const before = interpolateAlongPath(PATH, -5)
    const after = interpolateAlongPath(PATH, 12)
    expect(before.lat).toBeCloseTo(LISBOA.lat, 9)
    expect(after.lat).toBeCloseTo(CEUTA.lat, 9)
  })

  test('an empty path throws instead of returning the Gulf of Guinea', () => {
    expect(() => interpolateAlongPath([], 0.5)).toThrow()
  })

  test('a path of coincident points has no length to divide by, and does not produce NaN', () => {
    const at = interpolateAlongPath([LISBOA, LISBOA], 0.5)
    expect(Number.isNaN(at.lat)).toBe(false)
    expect(at.lat).toBeCloseTo(LISBOA.lat, 9)
  })

  test('great-circle interpolation stays on the sphere, not on the flat chart', () => {
    // Two points on the same parallel: the great circle between them bows POLEWARD of the
    // straight chart line, which is exactly why the track is not drawn as a straight segment.
    const west: LatLon = { lat: 50, lon: -60 }
    const east: LatLon = { lat: 50, lon: 10 }
    expect(interpolateGreatCircle(west, east, 0.5).lat).toBeGreaterThan(50)
  })

  test('densifyGreatCircle keeps the ends and adds points in between', () => {
    const dense = densifyGreatCircle(LISBOA, { lat: 23.11, lon: -82.37 }, 2)
    expect(dense.length).toBeGreaterThan(20)
    expect(dense[0].lat).toBeCloseTo(LISBOA.lat, 9)
    expect(dense[dense.length - 1].lat).toBeCloseTo(23.11, 9)
    const short = densifyGreatCircle(LISBOA, CADIZ, 90)
    expect(short).toHaveLength(2)
  })
})

// ── simplification, which is what makes the coastline affordable ──────────────────────────────

test.describe('simplifyPath', () => {
  test('drops collinear points and keeps the ends', () => {
    const line = [
      { x: 0, y: 0 },
      { x: 1, y: 0 },
      { x: 2, y: 0 },
      { x: 3, y: 0 },
      { x: 4, y: 0 },
    ]
    expect(simplifyPath(line, 0.1)).toEqual([
      { x: 0, y: 0 },
      { x: 4, y: 0 },
    ])
  })

  test('keeps a corner that is further from the chord than the tolerance', () => {
    const corner = [
      { x: 0, y: 0 },
      { x: 2, y: 5 },
      { x: 4, y: 0 },
    ]
    expect(simplifyPath(corner, 1)).toHaveLength(3)
    expect(simplifyPath(corner, 10)).toHaveLength(2)
  })

  test('a non-positive tolerance is a no-op, not an error', () => {
    const points = [
      { x: 0, y: 0 },
      { x: 1, y: 0 },
      { x: 2, y: 0 },
    ]
    expect(simplifyPath(points, 0)).toEqual(points)
  })
})
