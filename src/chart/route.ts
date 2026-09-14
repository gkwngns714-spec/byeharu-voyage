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
// ── THE SEA IS ROUND (0088, row 98) ────────────────────────────────────────────────────────────
// A segment whose two ends straddle the antimeridian is read THE SHORT WAY ROUND — the course
// convention of docs/NAVIGATION_PLAN.md §7, written once in src/lib/geo (`shortLonDelta`,
// `lonLerp`, `unwrapLongitudes`) and composed here, never restated. Until 0088 this file projected
// such a segment as a stripe the long way round the sheet and its header said "in practice it
// cannot be seen", because the server refused the segment; the server accepts it now, and Tokyo →
// Callao is ONE straddling segment 8,000 nm long. On a single unrolled sheet (x = lon in
// [−180, 180]) the short way is drawn as TWO pieces: the line runs off the right edge at
// (180, lat*) and comes back in at the left edge at (−180, lat*), where lat* is the latitude the
// lat/lon-linear segment crosses the seam at — the same line `voyage.position` places her on and
// `path_refusal` samples. `sheetPieces` is that split, and it is the only geometry this file adds.
// The continuous left-to-right sheet — a wrapped copy of the world beside the seam, so the two
// pieces meet — is the next slice (DEV_LOG 2026-09-14, "the sea is round", what was measured).
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { project, shortLonDelta, unwrapLongitudes, type LatLon, type Point } from '../lib/geo'
import { headingDeg } from './glyphs'
import { toPolylineD } from './svgPath'

/** The two halves of a track, ready for two <path> elements — and where the far end points. */
export interface TrackPaths {
  /** Departure → the fleet: the passage already made. */
  readonly sailedD: string
  /** The fleet → the course's end: the WHOLE remaining course — the server serves it all now,
   *  so nothing beyond the current segment has to be left undrawn any more. */
  readonly aheadD: string
  /** The course's last vertex, projected — where the arrowhead's tip goes (row 90). */
  readonly end: Point
  /** The last segment's heading, degrees clockwise from north, for the arrowhead's turn. Null
   *  when the course ends where it stands, in which case no arrowhead is drawn. */
  readonly endHeading: number | null
}

/** The half-turn: a longitude past it belongs on the other edge of the sheet. */
const SEAM = 180

/**
 * A polyline on the ONE unrolled sheet, every segment read the short way: the pieces it is cut
 * into by the antimeridian, each with its x in [−180, 180]. A run of points that never crosses the
 * seam is one piece, exactly what `project` gave before; a crossing ends a piece at the edge and
 * starts the next on the opposite edge at the same latitude — the latitude the lat/lon-linear
 * segment reaches the seam at, which is where the server puts her when she crosses.
 */
export function sheetPieces(points: readonly LatLon[]): Point[][] {
  if (points.length === 0) return []
  const pieces: Point[][] = []
  let piece: Point[] = [project(points[0])]
  for (let i = 1; i < points.length; i++) {
    const a = points[i - 1]
    const b = points[i]
    const dLon = shortLonDelta(a.lon, b.lon)
    // Where the unwrapped step lands, relative to the edge it is heading for. `from` is the
    // previous vertex's own longitude (in range), so one step can leave the sheet at most once.
    const edge = dLon > 0 ? SEAM : -SEAM
    const over = a.lon + dLon
    if (dLon !== 0 && (dLon > 0 ? over > SEAM : over < -SEAM)) {
      const f = (edge - a.lon) / dLon
      const latAtSeam = a.lat + (b.lat - a.lat) * f
      piece.push({ x: edge, y: -latAtSeam })
      pieces.push(piece)
      piece = [{ x: -edge, y: -latAtSeam }]
    }
    piece.push(project(b))
  }
  pieces.push(piece)
  return pieces
}

/** The pieces as one `d` — a subpath per piece, so one <path> still draws one half of a track. */
const piecesD = (points: readonly LatLon[]): string => sheetPieces(points).map(toPolylineD).join('')

/**
 * Split the served course at where the server says the fleet is. `segIndex` is
 * `voyage.position.seg_index` — which segment of the course the position lies on — served, never
 * derived here. The two halves meet exactly at the fleet, so the bright half is the passage made.
 */
export function buildTrack(course: readonly LatLon[], at: LatLon, segIndex: number): TrackPaths {
  // course[i]..course[i+1] is segment i: the sailed half is points 0..segIndex then the ship, and
  // the water ahead is the ship then points segIndex+1..end. A degenerate course (fewer than two
  // points) draws two empty halves rather than inventing a line.
  if (course.length < 2) return { sailedD: '', aheadD: '', end: project(at), endHeading: null }
  const cut = Math.min(Math.max(segIndex, 0), course.length - 2)
  const sailed = [...course.slice(0, cut + 1), at]
  const ahead = [at, ...course.slice(cut + 1)]
  // The arrowhead points the way the LAST segment of the water ahead runs — from the vertex
  // before the end to the end, read the short way: `unwrapLongitudes` puts the vertex before the
  // end within half a turn of it, so a last segment that straddles the seam still points across
  // the seam and not back round the world. The tip itself is the served last vertex, in range.
  const lastTwo = unwrapLongitudes(ahead.slice(-2))
  const end = project(ahead[ahead.length - 1])
  const before = project(lastTwo[0])
  const endUnwrapped = project(lastTwo[1])
  return {
    sailedD: piecesD(sailed),
    aheadD: piecesD(ahead),
    end,
    endHeading: headingDeg(before, endUnwrapped),
  }
}
