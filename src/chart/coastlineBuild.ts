// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE COASTLINE, BUILT — one pale stroke, built from the vendored Natural Earth 110m country polygons.
//
// DESIGN §E.5: "Coastlines are a single pale stroke. No fill, no terrain, no bathymetry, no
// borders." So the 177 country features are used for ONE thing — the outline where land meets
// water — and everything the file knows about borders, names and continents is thrown away here.
// The result is a single `d` string that goes into a single <path>.
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
//     rings    289 → 286                  points  10,654 → 6,183
//     rendered path   79,780 bytes (77.9 KB) of `d`, in ONE <path> element
//     build time      8.3 ms, once per map open
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
import { toClosedRingsD } from './svgPath'

/** Simplification tolerance in degrees. 0.2° ≈ 12 nm. */
export const COASTLINE_TOLERANCE_DEG = 0.2

/** Rings whose entire bounding box is smaller than this are dropped. */
export const COASTLINE_MIN_SPAN_DEG = 0.35

/** What the map gets, and what it can honestly report about its own size. */
export interface CoastlineData {
  /** The whole world's land as one SVG `d`, in chart units. */
  readonly d: string
  readonly ringCount: number
  readonly pointCount: number
  /** Length of `d` in bytes — the rendered path size, measured rather than estimated. */
  readonly pathBytes: number
  /** What it was before decimation, so the trade is visible. */
  readonly rawRingCount: number
  readonly rawPointCount: number
}

// The minimum of GeoJSON this module is willing to believe. Anything that does not match is
// skipped rather than crashing the tab: a malformed backdrop must never take the chart down.
interface RingSource {
  readonly type?: unknown
  readonly coordinates?: unknown
}
interface FeatureSource {
  readonly geometry?: RingSource
}

const isNumberPair = (v: unknown): v is [number, number] =>
  Array.isArray(v) && v.length >= 2 && typeof v[0] === 'number' && typeof v[1] === 'number'

/** Pull every linear ring out of a FeatureCollection of Polygon / MultiPolygon, as lon/lat pairs. */
function extractRings(json: unknown): LatLon[][] {
  const features = (json as { features?: unknown })?.features
  if (!Array.isArray(features)) return []

  const rings: LatLon[][] = []
  for (const feature of features as FeatureSource[]) {
    const geometry = feature?.geometry
    if (!geometry || !Array.isArray(geometry.coordinates)) continue
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
        if (points.length >= 3) rings.push(points)
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
  const rawRings = extractRings(json)
  const rawPointCount = rawRings.reduce((sum, ring) => sum + ring.length, 0)

  const kept: Point[][] = []
  let pointCount = 0
  for (const ring of rawRings) {
    const projected = ring.map(project)
    const span = boundingSpan(projected)
    if (span.width < COASTLINE_MIN_SPAN_DEG && span.height < COASTLINE_MIN_SPAN_DEG) continue
    const simplified = simplifyPath(projected, COASTLINE_TOLERANCE_DEG)
    // A ring that collapses below a triangle is no longer a shape; drawing it is a stray tick.
    if (simplified.length < 4) continue
    kept.push(simplified)
    pointCount += simplified.length
  }

  const d = toClosedRingsD(kept)
  return {
    d,
    ringCount: kept.length,
    pointCount,
    pathBytes: d.length,
    rawRingCount: rawRings.length,
    rawPointCount,
  }
}
