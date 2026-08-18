// ═══════════════════════════════════════════════════════════════════════════════════════════════
// GREAT-CIRCLE MATHS — the client's copy of DESIGN §B.3, and nothing more.
//
// WHOSE NUMBER IS THIS. §B.3 is explicit: distance is implemented once, in SQL, as
// `voyage.gc_distance_nm(...)` — "immutable, one authority, never re-derived client-side. The
// client may compute the same number for display only." So: every function here is FOR DISPLAY.
// Nothing in this module may ever decide whether a voyage has arrived, what a leg costs, or
// whether an order is legal. It draws the picture the server's numbers describe.
//
// It uses the same constant and the same formula as the SQL will, so the picture and the ledger
// agree. tests/map.geo.spec.ts pins that against §B.3's published table of worked distances — if
// the two ever drift, a test says so rather than a player noticing a dot in the wrong sea.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import type { LatLon } from './projection'

/** Mean Earth radius in nautical miles — DESIGN §B.3, verbatim. */
export const EARTH_RADIUS_NM = 3440.065

const toRad = (deg: number): number => (deg * Math.PI) / 180
const toDeg = (rad: number): number => (rad * 180) / Math.PI

/** The angular separation of two points, in radians. The shared core of distance and interpolation. */
function centralAngle(a: LatLon, b: LatLon): number {
  const phi1 = toRad(a.lat)
  const phi2 = toRad(b.lat)
  const dPhi = phi2 - phi1
  const dLambda = toRad(b.lon - a.lon)
  const h =
    Math.sin(dPhi / 2) ** 2 + Math.cos(phi1) * Math.cos(phi2) * Math.sin(dLambda / 2) ** 2
  return 2 * Math.asin(Math.min(1, Math.sqrt(h)))
}

/**
 * Great-circle (haversine) distance in nautical miles — DESIGN §B.3:
 *
 *     a    = sin²(Δφ/2) + cos φ₁ · cos φ₂ · sin²(Δλ/2)
 *     d_nm = 2R · asin(√a)
 */
export function haversineNm(a: LatLon, b: LatLon): number {
  return EARTH_RADIUS_NM * centralAngle(a, b)
}

/**
 * The point a given fraction of the way from `a` to `b` ALONG THE GREAT CIRCLE (spherical
 * interpolation, not a straight line on the flat chart). `fraction` is clamped to [0, 1], so a
 * clock that has run past arrival can only ever put the glyph on the quay.
 */
export function interpolateGreatCircle(a: LatLon, b: LatLon, fraction: number): LatLon {
  const f = Math.min(1, Math.max(0, fraction))
  const delta = centralAngle(a, b)
  // Coincident (or all but coincident) endpoints: sin(delta) → 0 and the weights blow up. The
  // answer there is simply `a`.
  if (!(delta > 1e-12)) return { lat: a.lat, lon: a.lon }

  const sinDelta = Math.sin(delta)
  const A = Math.sin((1 - f) * delta) / sinDelta
  const B = Math.sin(f * delta) / sinDelta

  const phi1 = toRad(a.lat)
  const lam1 = toRad(a.lon)
  const phi2 = toRad(b.lat)
  const lam2 = toRad(b.lon)

  const x = A * Math.cos(phi1) * Math.cos(lam1) + B * Math.cos(phi2) * Math.cos(lam2)
  const y = A * Math.cos(phi1) * Math.sin(lam1) + B * Math.cos(phi2) * Math.sin(lam2)
  const z = A * Math.sin(phi1) + B * Math.sin(phi2)

  return { lat: toDeg(Math.atan2(z, Math.hypot(x, y))), lon: toDeg(Math.atan2(y, x)) }
}

/** Distance in nautical miles along a polyline of waypoints (0 for fewer than two points). */
export function pathLengthNm(path: readonly LatLon[]): number {
  let total = 0
  for (let i = 1; i < path.length; i++) total += haversineNm(path[i - 1], path[i])
  return total
}

/** Running distance to each waypoint: `[0, d₁, d₁+d₂, …]`. Same length as `path`. */
export function cumulativeNm(path: readonly LatLon[]): number[] {
  const out: number[] = []
  let total = 0
  for (let i = 0; i < path.length; i++) {
    if (i > 0) total += haversineNm(path[i - 1], path[i])
    out.push(total)
  }
  return out
}

/**
 * The point a given fraction of the way along a multi-leg path, MEASURED BY DISTANCE — so on a
 * path whose second leg is ten times the first, fraction 0.5 is well inside the second leg, not at
 * the joint. Within a leg the position is great-circle interpolated.
 *
 * `fraction` is clamped to [0, 1]: 0 is the first waypoint, 1 is the last, exactly.
 * An empty path throws (there is no point to return and a silent {0,0} is the Gulf of Guinea).
 */
export function interpolateAlongPath(path: readonly LatLon[], fraction: number): LatLon {
  if (path.length === 0) throw new Error('interpolateAlongPath: empty path')
  if (path.length === 1) return { lat: path[0].lat, lon: path[0].lon }

  const f = Math.min(1, Math.max(0, fraction))
  const cumulative = cumulativeNm(path)
  const total = cumulative[cumulative.length - 1]

  // A path of coincident points has no length to divide by; every fraction of it is the same spot.
  if (!(total > 0)) return { lat: path[0].lat, lon: path[0].lon }

  const target = f * total
  for (let i = 1; i < path.length; i++) {
    if (target <= cumulative[i] || i === path.length - 1) {
      const legLength = cumulative[i] - cumulative[i - 1]
      const within = legLength > 0 ? (target - cumulative[i - 1]) / legLength : 1
      return interpolateGreatCircle(path[i - 1], path[i], within)
    }
  }
  /* istanbul ignore next — the loop above always returns on its last iteration. */
  return { lat: path[path.length - 1].lat, lon: path[path.length - 1].lon }
}

/**
 * Break one leg into a chain of points so the drawn line follows the great circle instead of
 * cutting the chord. `maxSegmentDeg` is the largest angular step allowed (2° ≈ 120 nm, which is
 * under a pixel of error at any zoom this chart offers).
 *
 * Always returns at least [a, b]; short legs get exactly that, so a coastal hop costs two points.
 */
export function densifyGreatCircle(a: LatLon, b: LatLon, maxSegmentDeg = 2): LatLon[] {
  const spanDeg = toDeg(centralAngle(a, b))
  const steps = Math.max(1, Math.ceil(spanDeg / Math.max(0.01, maxSegmentDeg)))
  const out: LatLon[] = []
  for (let i = 0; i <= steps; i++) out.push(interpolateGreatCircle(a, b, i / steps))
  return out
}
