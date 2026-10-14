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

/** The whole globe. The chart is never panned or zoomed past the poles; east–west it wraps (see
 *  the end of this file), so these are the bounds of ONE copy of the sheet. */
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

// ── THE SEA IS ROUND: longitude is modular, and a segment is read the SHORT way ─────────────────
//
// THE COURSE CONVENTION (2026-09-14, migration 0088 — docs/NAVIGATION_PLAN.md §7):
//   · every vertex of a course lies in [−180, 180];
//   · a segment MAY straddle the antimeridian — its two vertices on opposite sides of ±180 — and
//     it is ALWAYS read the short way round: the way whose |Δlon| ≤ 180. There is no long way.
//   · every reader interpolates longitude through ONE rule — `lonLerp` here, `voyage.lon_lerp`
//     on the server — and never through `a + (b − a) · f` on raw degrees, which for a straddling
//     segment sweeps the whole world instead of the 0.25° it sails.
// The three server interpolators (path_refusal, segments_from_course, position), the client's
// segment sampler (src/lib/sea/pathfind.ts), the chart's track (src/chart/route.ts `sheetPieces`,
// which cuts a straddling segment at ±180 into two pieces on the one sheet) and its drift
// (src/chart/drift.ts) all compose this rule. The continuous left-to-right sheet is the next slice.

/** The signed longitude step from `from` to `to` the SHORT way round: always in [−180, 180].
 *  179 → −179 is +2, not −358. The one modular rule every other function here composes. */
export function shortLonDelta(from: number, to: number): number {
  return to - from - 360 * Math.round((to - from) / 360)
}

/** Bring a longitude back into [−180, 180] after one step past the seam. A value already in
 *  range — 180 and −180 included — is returned untouched, so a vertex is never rewritten. */
export function wrapLon(lon: number): number {
  return lon > 180 ? lon - 360 : lon < -180 ? lon + 360 : lon
}

/** Longitude `f` of the way from `a` to `b` along the short way, wrapped back into range. THE
 *  longitude interpolation of a course segment — the client twin of `voyage.lon_lerp`. */
export function lonLerp(a: number, b: number, f: number): number {
  return wrapLon(a + shortLonDelta(a, b) * f)
}

/**
 * Make a run of longitudes continuous, so a line that crosses the antimeridian is drawn as one
 * short hop rather than a stripe sweeping the whole chart. Each point is moved by whole turns of
 * 360° to sit within half a turn of the point before it — `shortLonDelta`, accumulated.
 *
 * (Natural Earth's 110m rings are already clipped at ±180, so this matters for ROUTES, not for the
 * coastline — but it is geometry, so it lives with the projection.)
 */
export function unwrapLongitudes(points: readonly LatLon[]): LatLon[] {
  const out: LatLon[] = []
  let previousLon: number | null = null
  for (const p of points) {
    const lon: number = previousLon === null ? p.lon : previousLon + shortLonDelta(previousLon, p.lon)
    out.push({ lat: p.lat, lon })
    previousLon = lon
  }
  return out
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE SHEET REPEATS EVERY 360° — the projection is periodic in x, and that is the whole of the
// continuous east–west chart (owner, 2026-10-14: *"right now the map is not continuous from left
// to right. i want it to be continuous"*).
//
// `project` maps a longitude to x = lon, and a longitude is the same place at lon + 360k for every
// integer k. So a VIEW is any rectangle on an unbounded x axis, and the thing at lon L is drawn at
// x = L + 360k for every k whose copy of the world touches the view. These two functions are the
// only arithmetic the wrap needs, and every consumer composes them rather than restating a 360:
//   · `sheetCopies(box)`   which copies (k) touch a box — the chart renders its marks once per copy
//                          in a `translate(360k 0)` group, and the coast once per copy with a <use>;
//   · `xOnSheet(x, a, b)`  whether a point at x lands inside [a, b] on SOME copy — the box test
//                          `portMarks` and a hit test ask, so a harbour at 179°E is on a sheet whose
//                          view runs from 170° to 200°.
// `WORLD_BOUNDS` still bounds the view VERTICALLY (there is nothing past the poles); horizontally
// it is only the fit of the opening frame.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/**
 * The integer copies of the world a chart-unit x-range touches: copy k is the world drawn at
 * x ∈ [360k − 180, 360k + 180). Half-open on purpose, so a view that runs exactly from −180 to
 * 180 is ONE copy and not two with the second contributing nothing but a seam-column duplicate.
 */
export function sheetCopies(box: { readonly x: number; readonly width: number }): number[] {
  const out: number[] = []
  if (!(box.width > 0) || !Number.isFinite(box.x)) return [0]
  const first = Math.floor((box.x + CHART_WIDTH / 2) / CHART_WIDTH)
  const last = Math.ceil((box.x + box.width + CHART_WIDTH / 2) / CHART_WIDTH) - 1
  for (let k = first; k <= last; k++) {
    const left = k * CHART_WIDTH - CHART_WIDTH / 2
    const right = left + CHART_WIDTH
    if (left < box.x + box.width && right > box.x) out.push(k)
  }
  return out.length === 0 ? [0] : out
}

/** Whether a point at chart x lands inside [minX, maxX] on some copy of the sheet. A range a
 *  whole turn wide or wider holds every x. */
export function xOnSheet(x: number, minX: number, maxX: number): boolean {
  if (maxX - minX >= CHART_WIDTH) return true
  const first = minX + ((((x - minX) % CHART_WIDTH) + CHART_WIDTH) % CHART_WIDTH)
  return first <= maxX
}
