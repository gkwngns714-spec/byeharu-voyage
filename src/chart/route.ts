// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE TRACK — the served course, split at the served position. The chart draws what she sails.
//
// ── THE ONE GEOMETRY RULE: THE COURSE IS A POLYLINE, STRAIGHT IN LAT/LON PER SEGMENT ───────────
// This header used to argue the opposite ("a leg is a straight segment between two PORTS") because
// the server served only a leg's endpoints and interpolated straight between them. 0039 replaced
// that model: `world.fleets()` now serves THE WHOLE COURSE — the verified water polyline the
// voyage actually sails — and `voyage.position()` places the ship LINEARLY along the segment its
// progress falls in. That linear placement is the same interpolation `voyage.path_refusal`
// samples for the never-touch-land law, so the line judged, the line sailed and the line drawn
// here are ONE line. On this equirectangular chart a lat/lon-linear segment is a straight stroke,
// which puts the glyph exactly ON its own track — a great-circle arc would bow away from the very
// point the server put the ship at.
//
// Distance is never read off this picture. The nautical miles are the server's own measure of the
// course (`voyage.path_nm` and the segment sums it freezes); they arrive as numbers.
//
// ── WHAT DIED WITH THE LEG GRAPH (0039) ────────────────────────────────────────────────────────
// `legWebPath` — the 782-leg sea-lane layer — is DELETED, not kept quiet. Its lanes were drawn
// straight between ports while their distances were measured round capes, so the layer showed
// water nothing sailed (532 of the legs were drawn over land). Under the free sea there are no
// fixed lanes to draw: the water itself is the way, and the only lines on the sheet are TRACKS —
// courses fleets are actually sailing, every segment of which the server verified as open water.
//
// A segment whose two ends straddle the antimeridian is drawn the long way round the sheet — the
// server refuses such a segment in a course (E_BAD_PATH), and the pathfinder never emits one, so
// in practice it cannot be seen.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { project, type LatLon } from '../lib/geo'
import { toPolylineD } from './svgPath'

/** The two halves of a track, ready for two <path> elements. */
export interface TrackPaths {
  /** Departure → the fleet: the passage already made. */
  readonly sailedD: string
  /** The fleet → the course's end: the WHOLE remaining course — the server serves it all now,
   *  so nothing beyond the current segment has to be left undrawn any more. */
  readonly aheadD: string
}

/**
 * Split the served course at where the server says the fleet is. `segIndex` is
 * `voyage.position.seg_index` — which segment of the course the position lies on — served, never
 * derived here. The two halves meet exactly at the fleet, so the bright half is the passage made.
 */
export function buildTrack(course: readonly LatLon[], at: LatLon, segIndex: number): TrackPaths {
  // course[i]..course[i+1] is segment i: the sailed half is points 0..segIndex then the ship, and
  // the water ahead is the ship then points segIndex+1..end. A degenerate course (fewer than two
  // points) draws two empty halves rather than inventing a line.
  if (course.length < 2) return { sailedD: '', aheadD: '' }
  const cut = Math.min(Math.max(segIndex, 0), course.length - 2)
  const sailed = [...course.slice(0, cut + 1), at].map(project)
  const ahead = [at, ...course.slice(cut + 1)].map(project)
  return { sailedD: toPolylineD(sailed), aheadD: toPolylineD(ahead) }
}
