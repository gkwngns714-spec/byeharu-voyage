// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE COASTLINE, BUILT — one pale stroke, built from the vendored Natural Earth 110m country polygons.
//
// DESIGN §E.5: "Coastlines are a single pale stroke. No fill, no terrain, no bathymetry, no
// borders." So the 177 country features are used for ONE thing — the outline where land meets
// water — and everything the file knows about borders, names and continents is thrown away here.
// The result is TWO `d` strings from one pass (row 90, 2026-09-13): the BODY, every ring closed,
// and the LINE, the outline with the shared inland borders left out — `CoastlineData` says how.
// Before row 90 there was one `d` and it was stroked whole, which drew every border as a coast;
// "no borders" is true of the picture only since the line was split from the body.
//
// WHY THE FILE IS FETCHED RATHER THAN IMPORTED (./coastline.ts does the fetching).
// `data/world-110m.json` is 280,378 bytes. Imported, it would be parsed into the main JavaScript
// bundle and downloaded by every player on every tab, including the seven that are pure text.
// Loaded through `?url` it is an ordinary build asset — `npm run build` emits
// dist/assets/world-110m-*.json, 280.37 kB / 99.51 kB gzipped — so the browser fetches it the
// first time the Map tab is opened, caches it, and the other tabs never pay for it.
//
// WHY IT IS DECIMATED, AND WHAT IT COSTS — MEASURED by running THIS function over the real file:
//
//     rings    289 → 286                  points  10,654 → 6,111   (the body, `d`)
//     the line (`coastD`, row 90)          3,251 points in 271 runs, 116 of them closed islands,
//                                          42,772 bytes; 2,664 border segments left out
//     rendered body   78,902 bytes (77.1 KB) of `d`, in ONE <path> element
//     build time      36.6 ms, once per map open (re-measured 2026-09-13 with the border pass;
//                     it was 8.3 ms for the body alone)
//
// Undecimated, that path is ~123 KB, and the browser re-rasterises all of it on every frame of a
// pinch-zoom. This is a BACKDROP; it does not earn that. Ramer–Douglas–Peucker at 0.2° (≈12 nm,
// about 2 px at the opening view) is the trade, plus dropping rings whose whole bounding box is
// under 0.35° — islets that can never be more than a speck at any zoom the chart offers.
//
// Every one of those figures comes back in `CoastlineData`, so the size is something the app can
// print rather than a claim in a comment that nobody re-checks.
//
// Decimating at LOAD time, rather than checking in a pre-built path, keeps `data/` the single
// source of truth: there is no generated copy of the world to drift out of date with it.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { boundingSpan, project, simplifyPath, type LatLon, type Point } from '../lib/geo'
import { toClosedRingsD, toPolylineD } from './svgPath'

/** Simplification tolerance in degrees. 0.2° ≈ 12 nm. */
export const COASTLINE_TOLERANCE_DEG = 0.2

/** Rings whose entire bounding box is smaller than this are dropped. */
export const COASTLINE_MIN_SPAN_DEG = 0.35

/** What the map gets, and what it can honestly report about its own size. */
export interface CoastlineData {
  /** The whole world's land as one SVG `d`, in chart units — every ring, closed: THE BODY. */
  readonly d: string
  /**
   * THE LINE (row 90): the same outline with every segment two rings share LEFT OUT — the inland
   * borders — as open runs, plus every ring nothing shares (an island) closed. The file is
   * countries, and neighbours share their border's vertices exactly (measured: 2,664 of 10,365 raw
   * segments, none shared by more than two), so stroking `d` drew every border as a coast. This
   * is what the coast stroke, the shallows and the relief are drawn from; the body is still `d`.
   * Its vertices are the body's own — the ring is simplified run by run, split where the sharing
   * changes, so the line sits exactly on the body's edge at every zoom.
   */
  readonly coastD: string
  readonly ringCount: number
  readonly pointCount: number
  /** Points in `coastD` after decimation. */
  readonly coastPointCount: number
  /** Raw segments that two rings shared — the borders the line leaves out. */
  readonly sharedSegmentCount: number
  /** Length of `d` in bytes — the rendered path size, measured rather than estimated. */
  readonly pathBytes: number
  /**
   * THE BODY'S OWN RINGS, as points (2026-09-14, rows 91 and 92) — exactly the rings `d` is
   * written from, in the same order, so a rule that asks "is this point on DRAWN land" (the
   * landfall, ./landfall.ts) reads the geometry the eye sees and never re-parses a string or
   * re-decimates the file. `fill-rule: evenodd` is the body's rule, so it is the reader's too.
   */
  readonly rings: readonly (readonly Point[])[]
  /**
   * THE SAME RINGS, GROUPED BY THE COUNTRY THE FILE DREW THEM FOR (row 92, the regions' tint):
   * one entry per feature that kept at least one ring, `iso` = Natural Earth's `ISO_A2_EH` (the
   * one code column the file fills for every state — `ISO_A2` reads "-99" for France and Norway),
   * `d` = that country's rings closed, written by the same builder as `d`. A tint painted from
   * these is painted on the body's own edge, so it can never spill into the water or leave a
   * sliver of untinted shore. Nothing else about the country — its name, its continent — is read.
   */
  readonly countries: readonly CoastCountry[]
  /** What it was before decimation, so the trade is visible. */
  readonly rawRingCount: number
  readonly rawPointCount: number
}

/** One country's share of the body — see `CoastlineData.countries`. */
export interface CoastCountry {
  readonly iso: string
  readonly d: string
}

// The minimum of GeoJSON this module is willing to believe. Anything that does not match is
// skipped rather than crashing the tab: a malformed backdrop must never take the chart down.
interface RingSource {
  readonly type?: unknown
  readonly coordinates?: unknown
}
interface FeatureSource {
  readonly geometry?: RingSource
  readonly properties?: { readonly ISO_A2_EH?: unknown }
}

/** A raw ring and the country code of the feature it came from ('' when the file gives none). */
interface SourceRing {
  readonly points: LatLon[]
  readonly iso: string
}

const isNumberPair = (v: unknown): v is [number, number] =>
  Array.isArray(v) && v.length >= 2 && typeof v[0] === 'number' && typeof v[1] === 'number'

/** Pull every linear ring out of a FeatureCollection of Polygon / MultiPolygon, as lon/lat pairs. */
function extractRings(json: unknown): SourceRing[] {
  const features = (json as { features?: unknown })?.features
  if (!Array.isArray(features)) return []

  const rings: SourceRing[] = []
  for (const feature of features as FeatureSource[]) {
    const geometry = feature?.geometry
    if (!geometry || !Array.isArray(geometry.coordinates)) continue
    const isoRaw = feature.properties?.ISO_A2_EH
    const iso = typeof isoRaw === 'string' && /^[A-Z]{2}$/.test(isoRaw) ? isoRaw : ''
    // Polygon: [ring][point]. MultiPolygon: [polygon][ring][point]. Normalise to the latter.
    const polygons =
      geometry.type === 'Polygon' ? [geometry.coordinates] : (geometry.coordinates as unknown[])
    for (const polygon of polygons) {
      if (!Array.isArray(polygon)) continue
      for (const ring of polygon) {
        if (!Array.isArray(ring)) continue
        const points: LatLon[] = []
        for (const position of ring) {
          if (isNumberPair(position)) points.push({ lon: position[0], lat: position[1] })
        }
        if (points.length >= 3) rings.push({ points, iso })
      }
    }
  }
  return rings
}

/**
 * Turn a parsed GeoJSON FeatureCollection into the one path the chart draws. PURE — no fetch, no
 * DOM — so the decimation can be measured and pinned without a network.
 */
export function buildCoastline(json: unknown): CoastlineData {
  const sourceRings = extractRings(json)
  const rawRings = sourceRings.map((r) => r.points)
  const rawPointCount = rawRings.reduce((sum, ring) => sum + ring.length, 0)

  // ── WHICH SEGMENTS ARE BORDERS (row 90) ──────────────────────────────────────────────────────
  // A segment two rings both walk is an inland border; a vertex three or more rings meet at is a
  // triple point. Both are read off the RAW coordinates, before decimation, because that is where
  // the file makes them exact. Keyed on the coordinate text itself — no rounding, no tolerance:
  // the file either shares the vertex or it does not, and a tolerance here would be a second
  // opinion about the data.
  const vertexKey = (p: LatLon) => `${p.lon},${p.lat}`
  const segmentKey = (a: LatLon, b: LatLon) => {
    const s = vertexKey(a)
    const t = vertexKey(b)
    return s < t ? `${s}|${t}` : `${t}|${s}`
  }
  const closedPoints = (ring: LatLon[]): LatLon[] => {
    const last = ring[ring.length - 1]
    const first = ring[0]
    return ring.length > 1 && last.lon === first.lon && last.lat === first.lat ? ring.slice(0, -1) : ring
  }
  const segmentRings = new Map<string, number>()
  const vertexRings = new Map<string, number>()
  for (const ring of rawRings) {
    const pts = closedPoints(ring)
    const seen = new Set<string>()
    for (let i = 0; i < pts.length; i++) {
      const k = segmentKey(pts[i], pts[(i + 1) % pts.length])
      segmentRings.set(k, (segmentRings.get(k) ?? 0) + 1)
      const v = vertexKey(pts[i])
      if (!seen.has(v)) {
        seen.add(v)
        vertexRings.set(v, (vertexRings.get(v) ?? 0) + 1)
      }
    }
  }
  let sharedSegmentCount = 0
  for (const n of segmentRings.values()) if (n >= 2) sharedSegmentCount++

  // A border run is simplified ONCE, in a canonical direction, and both rings that walk it get the
  // same points back — so the two countries' edges coincide in the body (no sliver, no crack) and
  // the line, drawn from the same runs, sits exactly on that edge.
  const borderRuns = new Map<string, Point[]>()
  const simplifyRun = (run: LatLon[], shared: boolean): Point[] => {
    if (!shared) return simplifyPath(run.map(project), COASTLINE_TOLERANCE_DEG)
    const forward = vertexKey(run[0]) < vertexKey(run[run.length - 1])
    const canonical = forward ? run : [...run].reverse()
    const key = canonical.map(vertexKey).join(';')
    let simplified = borderRuns.get(key)
    if (!simplified) {
      simplified = simplifyPath(canonical.map(project), COASTLINE_TOLERANCE_DEG)
      borderRuns.set(key, simplified)
    }
    return forward ? simplified : [...simplified].reverse()
  }

  const kept: Point[][] = []
  const keptIso: string[] = []
  let pointCount = 0
  let coastD = ''
  let coastPointCount = 0
  for (const source of sourceRings) {
    const pts = closedPoints(source.points)
    if (pts.length < 3) continue
    const projected = pts.map(project)
    const span = boundingSpan(projected)
    if (span.width < COASTLINE_MIN_SPAN_DEG && span.height < COASTLINE_MIN_SPAN_DEG) continue

    const n = pts.length
    const shared = pts.map((p, i) => (segmentRings.get(segmentKey(p, pts[(i + 1) % n])) ?? 0) >= 2)
    // A run boundary is where the sharing changes, or a triple point (the neighbour changes).
    const boundary = (i: number) =>
      shared[i] !== shared[(i - 1 + n) % n] || (vertexRings.get(vertexKey(pts[i])) ?? 0) >= 3
    let start = -1
    for (let i = 0; i < n; i++) {
      if (boundary(i)) {
        start = i
        break
      }
    }

    if (start === -1) {
      // No boundary at all. Either NOTHING is shared — an island, or a continent's outer ring —
      // and the body ring and the line are one closed run; or EVERYTHING is (an enclave, and the
      // hole its neighbour keeps for it), which is a body ring with no coast. The enclave case is
      // simplified from a canonical start and direction, memoised on its vertices, so the enclave
      // and the hole come out as the same points and `evenodd` leaves no crack between them.
      let closed = [...pts, pts[0]]
      if (shared[0]) {
        let smallest = 0
        for (let i = 1; i < n; i++) if (vertexKey(pts[i]) < vertexKey(pts[smallest])) smallest = i
        const rotated = [...pts.slice(smallest), ...pts.slice(0, smallest)]
        const forward = vertexKey(rotated[1]) < vertexKey(rotated[n - 1])
        closed = forward ? [...rotated, rotated[0]] : [rotated[0], ...rotated.slice(1).reverse(), rotated[0]]
      }
      const simplified = shared[0]
        ? simplifyRun(closed, true)
        : simplifyPath(closed.map(project), COASTLINE_TOLERANCE_DEG)
      // A ring that collapses below a triangle is no longer a shape; drawing it is a stray tick.
      if (simplified.length < 4) continue
      kept.push(simplified)
      keptIso.push(source.iso)
      pointCount += simplified.length
      if (!shared[0]) {
        coastD += toPolylineD(simplified) + 'Z'
        coastPointCount += simplified.length
      }
      continue
    }

    // Walk the ring from the first boundary, cutting runs at every boundary after it.
    const runs: { points: LatLon[]; shared: boolean }[] = []
    let current: { points: LatLon[]; shared: boolean } | null = null
    for (let k = 0; k < n; k++) {
      const i = (start + k) % n
      if (k > 0 && boundary(i) && current) {
        runs.push(current)
        current = null
      }
      if (!current) current = { points: [pts[i]], shared: shared[i] }
      current.points.push(pts[(i + 1) % n])
    }
    if (current) runs.push(current)

    const body: Point[] = []
    for (const run of runs) {
      const simplified = simplifyRun(run.points, run.shared)
      // The joint is the previous run's last point; do not repeat it.
      for (let j = body.length === 0 ? 0 : 1; j < simplified.length; j++) body.push(simplified[j])
      if (!run.shared && simplified.length >= 2) {
        coastD += toPolylineD(simplified)
        coastPointCount += simplified.length
      }
    }
    // The last run ends where the first began; drop the repeated closing joint.
    if (body.length > 1 && body[0].x === body[body.length - 1].x && body[0].y === body[body.length - 1].y) body.pop()
    if (body.length < 3) continue
    kept.push(body)
    keptIso.push(source.iso)
    pointCount += body.length
  }

  const d = toClosedRingsD(kept)

  // THE COUNTRIES (row 92): the kept rings regrouped by the code they came in under, written by
  // the same builder. A ring the file gave no code ('') belongs to no country and is left out
  // here — it is still in `d` and `rings`; only a tint has nothing to key it by.
  const byIso = new Map<string, Point[][]>()
  kept.forEach((ring, i) => {
    const iso = keptIso[i]
    if (iso === '') return
    const list = byIso.get(iso)
    if (list) list.push(ring)
    else byIso.set(iso, [ring])
  })
  const countries: CoastCountry[] = [...byIso].map(([iso, rings]) => ({ iso, d: toClosedRingsD(rings) }))

  return {
    d,
    coastD,
    ringCount: kept.length,
    pointCount,
    coastPointCount,
    sharedSegmentCount,
    pathBytes: d.length,
    rings: kept,
    countries,
    rawRingCount: rawRings.length,
    rawPointCount,
  }
}
