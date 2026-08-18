// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE PROJECTION — one authority for turning the round world into a flat chart, and back.
//
// WHICH PROJECTION, AND WHY EQUIRECTANGULAR.
// `docs/WORLD_DATA.md` is the file that gets to make this call. It did not exist when this module
// was written (docs/ held CORE_REUSE, DESIGN, DESIGN_RESEARCH and DEV_LOG and nothing else), so the
// decision is made here, in the open, and it is the honest default for a game chart:
//
//   x = lon              y = −lat            (degrees in, "chart units" out; y grows downward
//                                             because SVG's y axis does)
//
//   · The inverse is one negation. A read-only chart that must place a glyph, hit-test a tap and
//     un-project a pan gesture on every animation frame wants an inverse that costs nothing.
//   · Parallels and meridians stay straight and evenly spaced, so one chart unit is one degree
//     everywhere. Pan and zoom are then pure arithmetic on a viewBox — no re-projection per frame.
//   · It exaggerates east–west distance towards the poles (a Mercator-family chart exaggerates
//     north–south area instead; every flat map lies somewhere). This game's world is the Atlantic
//     and Mediterranean between roughly 28°N and 45°N, where the lie is small — and, crucially,
//     NOTHING IS MEASURED OFF THE PICTURE. Distance is haversine nautical miles (./greatCircle.ts,
//     §B.3), computed on the sphere and never read off the chart. The projection only decides where
//     ink lands.
//   · No polar exaggeration to explain away in a tooltip: this is a chart the player reads, and the
//     shape they learn is the shape the data has.
//
// If WORLD_DATA.md later recommends something else, it changes HERE and only here: the coastline,
// the ports, the routes, the pan/zoom maths and the hit-testing all go through `project` /
// `unproject`, so a different projection is a two-function edit, not a hunt.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** A point on the globe, decimal degrees, WGS84 (DESIGN §B.2's coordinate convention). */
export interface LatLon {
  readonly lat: number
  readonly lon: number
}

/** A point in chart units. One unit = one degree. `y` grows downward, as SVG's does. */
export interface Point {
  readonly x: number
  readonly y: number
}

/** An SVG viewBox in chart units. */
export interface ViewBox {
  readonly x: number
  readonly y: number
  readonly width: number
  readonly height: number
}

/** A lat/lon rectangle. */
export interface GeoBounds {
  readonly minLat: number
  readonly maxLat: number
  readonly minLon: number
  readonly maxLon: number
}

/** The whole globe. The chart can never be panned or zoomed outside this. */
export const WORLD_BOUNDS: GeoBounds = { minLat: -90, maxLat: 90, minLon: -180, maxLon: 180 }

/** The full chart in chart units: 360 wide, 180 tall. */
export const CHART_WIDTH = 360
export const CHART_HEIGHT = 180

/** Below this the "fit" arithmetic divides by ~zero; a degenerate box is widened to it. */
const MIN_SPAN_DEG = 0.05

/** Globe → chart. */
export function project(ll: LatLon): Point {
  return { x: ll.lon, y: -ll.lat }
}

/** Chart → globe. The exact inverse of `project` (assert this, do not assume it: tests/map.geo.spec.ts). */
export function unproject(p: Point): LatLon {
  return { lat: -p.y, lon: p.x }
}

/** The chart-unit box that exactly contains a lat/lon rectangle. */
export function boundsToViewBox(b: GeoBounds): ViewBox {
  const topLeft = project({ lat: b.maxLat, lon: b.minLon })
  return {
    x: topLeft.x,
    y: topLeft.y,
    width: Math.max(b.maxLon - b.minLon, MIN_SPAN_DEG),
    height: Math.max(b.maxLat - b.minLat, MIN_SPAN_DEG),
  }
}

/** The lat/lon rectangle a chart-unit box covers. */
export function viewBoxToBounds(vb: ViewBox): GeoBounds {
  const topLeft = unproject({ x: vb.x, y: vb.y })
  const bottomRight = unproject({ x: vb.x + vb.width, y: vb.y + vb.height })
  return {
    minLat: bottomRight.lat,
    maxLat: topLeft.lat,
    minLon: topLeft.lon,
    maxLon: bottomRight.lon,
  }
}

/** The tightest lat/lon rectangle around some points. Returns null for an empty input — a caller
 *  with nothing to frame must decide what to show, rather than be handed a silent world view. */
export function boundsOf(points: Iterable<LatLon>): GeoBounds | null {
  let minLat = Infinity
  let maxLat = -Infinity
  let minLon = Infinity
  let maxLon = -Infinity
  let seen = false
  for (const p of points) {
    seen = true
    if (p.lat < minLat) minLat = p.lat
    if (p.lat > maxLat) maxLat = p.lat
    if (p.lon < minLon) minLon = p.lon
    if (p.lon > maxLon) maxLon = p.lon
  }
  return seen ? { minLat, maxLat, minLon, maxLon } : null
}

/**
 * Frame a lat/lon rectangle inside a render surface of a given pixel aspect ratio, WITHOUT
 * distortion — the returned box has exactly `aspect` and CONTAINS the requested bounds.
 *
 * `aspect` is pixelWidth / pixelHeight of the surface. `padding` is a fraction of the fitted
 * extent added on every side (0.08 = an 8% margin), so a port on the edge of the set is never
 * drawn on the frame.
 *
 * This is the ONLY place "what should the chart show" becomes numbers, so the initial view, the
 * fit-again button and any future "frame this voyage" all agree by construction.
 */
export function fitToViewBox(bounds: GeoBounds, aspect: number, padding = 0.08): ViewBox {
  const safeAspect = Number.isFinite(aspect) && aspect > 0 ? aspect : 1
  const base = boundsToViewBox(bounds)

  const padded = {
    x: base.x - base.width * padding,
    y: base.y - base.height * padding,
    width: base.width * (1 + 2 * padding),
    height: base.height * (1 + 2 * padding),
  }

  const cx = padded.x + padded.width / 2
  const cy = padded.y + padded.height / 2

  // Grow the short side. Never shrink, or the bounds would be cropped.
  let width = padded.width
  let height = padded.height
  if (width / height < safeAspect) width = height * safeAspect
  else height = width / safeAspect

  return { x: cx - width / 2, y: cy - height / 2, width, height }
}

/**
 * Make a run of longitudes continuous, so a line that crosses the antimeridian is drawn as one
 * short hop rather than a stripe sweeping the whole chart. Each point is moved by whole turns of
 * 360° to sit within half a turn of the point before it.
 *
 * (Natural Earth's 110m rings are already clipped at ±180, so this matters for ROUTES, not for the
 * coastline — but it is geometry, so it lives with the projection.)
 */
export function unwrapLongitudes(points: readonly LatLon[]): LatLon[] {
  const out: LatLon[] = []
  let previousLon: number | null = null
  for (const p of points) {
    let lon = p.lon
    if (previousLon !== null) lon -= 360 * Math.round((lon - previousLon) / 360)
    out.push({ lat: p.lat, lon })
    previousLon = lon
  }
  return out
}
