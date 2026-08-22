// ═══════════════════════════════════════════════════════════════════════════════════════════════
// LINES ON THE WATER — the two kinds this chart draws, built by ONE geometry rule.
//
//   1. THE TRACK. DESIGN §E.5: "the authored leg path, dotted behind the fleet and fainter ahead of
//      it." Two polylines that meet exactly at the fleet, so the bright half is the passage made.
//   2. THE SEA LANES. `snapshot.legs` — where a ship can actually sail. A hairline, close in only,
//      so a player can read the graph without the chart becoming a spiderweb.
//
// ── THE ONE GEOMETRY RULE: A LEG IS A STRAIGHT SEGMENT IN LAT/LON ──────────────────────────────
// Not a great circle. This is not a simplification, it is AGREEMENT WITH THE SERVER: `voyage.
// position()` places the ship at `a.lat + (b.lat − a.lat) × frac`, linearly, and says so in its own
// comment ("the MAP is an output device: this is display geometry, linear along the leg"). On an
// equirectangular chart that is a straight line — so drawing the straight line puts the glyph
// exactly ON its own track. A great-circle arc would bow away from the very point the server put
// the ship at, and the player would see a dot floating off its route.
//
// Distance is never read off this picture. The nautical miles are the SAILED distances in the legs
// table — Lisboa→Cádiz is 248 nm because the route rounds Cape St Vincent — and they arrive from
// the server as numbers. Geometry places ink; the numbers come from the water.
//
// A leg whose two ports straddle the antimeridian is drawn the long way round the sheet, because
// that is where the server's own interpolation puts the ship. It cannot be seen: `legWebPath` only
// draws legs with BOTH ends on the glass, and no view holds both ends of such a leg.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { project, type LatLon, type ViewBox } from '../lib/geo'
import { toPolylineD } from './svgPath'
import type { MapPort } from './mapTypes'

/** The two halves of a track, ready for two <path> elements. */
export interface TrackPaths {
  /** The leg's departure port → the fleet. The passage already made. */
  readonly sailedD: string
  /** The fleet → the leg's arrival port. What is left of THIS leg — not of the whole voyage,
   *  which the server does not serve (README §4.8). */
  readonly aheadD: string
}

/** Build the current leg's track, split at where the server says the fleet is. */
export function buildTrack(from: LatLon, to: LatLon, at: LatLon): TrackPaths {
  return {
    sailedD: toPolylineD([project(from), project(at)]),
    aheadD: toPolylineD([project(at), project(to)]),
  }
}

/** One leg of the sea-lane graph, as the chart needs it: two port codes. */
export interface MapLeg {
  readonly from: string
  readonly to: string
}

/**
 * THE SEA LANES, as one `d` string for one <path>.
 *
 * 782 legs is a spiderweb at world zoom and a useful diagram at coast zoom, so this draws only the
 * legs with BOTH ends inside the (slightly padded) view. The caller decides whether to draw it at
 * all — see LEG_SPAN_LIMIT in ./chartView.ts, which drops the layer entirely when pulled back.
 *
 * `portsByCode` IS THE DRAWN SET (chartModel.visiblePorts), not the whole table. That is the rule
 * that stops a lane running off to a port with no mark on it: at any zoom where some harbours are
 * too small to draw, a lane to one of them would be a line ending in blank water, which reads as a
 * route to nowhere. A lane is drawn between two marks or it is not drawn.
 *
 * One element for every lane, not one per lane: 782 <path> nodes would be 782 React children to
 * reconcile on every pan.
 */
export function legWebPath(
  legs: readonly MapLeg[],
  portsByCode: ReadonlyMap<string, MapPort>,
  view: ViewBox,
  margin = 0.05,
): string {
  const padX = view.width * margin
  const padY = view.height * margin
  const minX = view.x - padX
  const maxX = view.x + view.width + padX
  const minY = view.y - padY
  const maxY = view.y + view.height + padY

  let d = ''
  for (const leg of legs) {
    const a = portsByCode.get(leg.from)
    const b = portsByCode.get(leg.to)
    if (!a || !b) continue
    const pa = project(a)
    const pb = project(b)
    if (pa.x < minX || pa.x > maxX || pa.y < minY || pa.y > maxY) continue
    if (pb.x < minX || pb.x > maxX || pb.y < minY || pb.y > maxY) continue
    d += toPolylineD([pa, pb])
  }
  return d
}
