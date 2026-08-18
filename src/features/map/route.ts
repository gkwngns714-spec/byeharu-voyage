// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE TRACK — the dotted line a fleet at sea draws behind and ahead of itself.
//
// DESIGN §E.5: "The track is the authored leg path, dotted behind the fleet and fainter ahead of
// it." So a track is TWO polylines that meet exactly at the fleet, not one line with a dot on it —
// which is also what makes the picture readable at a glance: the bright half is the passage made.
//
// The line follows the great circle between waypoints (a straight line on an equirectangular chart
// is not the course a ship steers), and it is split at the fleet's closed-form position, so the
// join moves because the ARITHMETIC moved, never because something animated it.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { densifyGreatCircle, project, unwrapLongitudes, type LatLon, type Point } from '../../lib/geo'
import { toPolylineD } from './svgPath'
import type { VoyageProgress } from './voyage'

/** The two halves of a track, ready for two <path> elements. */
export interface TrackPaths {
  /** Origin → the fleet. The passage already made. */
  readonly sailedD: string
  /** The fleet → destination. What is left. */
  readonly aheadD: string
}

/** Densify a waypoint list into a great-circle polyline in chart units, longitudes unwrapped so a
 *  leg that crosses the antimeridian is a short hop and not a stripe across the world. */
function toChartPoints(waypoints: readonly LatLon[]): Point[] {
  if (waypoints.length < 2) return waypoints.map(project)
  const dense: LatLon[] = [waypoints[0]]
  for (let i = 1; i < waypoints.length; i++) {
    // densifyGreatCircle repeats the leg's first point; drop it, the previous leg already ended there.
    dense.push(...densifyGreatCircle(waypoints[i - 1], waypoints[i]).slice(1))
  }
  return unwrapLongitudes(dense).map(project)
}

/**
 * Build a fleet's track, split at where it actually is.
 *
 * `waypoints` are the voyage's ports in order (legs.length + 1 of them). `progress` says which leg
 * the fleet is on and how far along it — the ONE source of that, ./voyage.ts, derived from the
 * departure time and the frozen speed profile.
 */
export function buildTrack(
  waypoints: readonly LatLon[],
  progress: VoyageProgress,
  fleetAt: LatLon,
): TrackPaths {
  if (waypoints.length < 2) return { sailedD: '', aheadD: '' }

  const leg = Math.min(progress.legIndex, waypoints.length - 2)

  // Behind: every completed leg, then the part of the current one that has been sailed.
  const sailed: LatLon[] = [...waypoints.slice(0, leg + 1), fleetAt]
  // Ahead: from the fleet to the end of the current leg, then the legs it has not started.
  const ahead: LatLon[] = [fleetAt, ...waypoints.slice(leg + 1)]

  return { sailedD: toPolylineD(toChartPoints(sailed)), aheadD: toPolylineD(toChartPoints(ahead)) }
}
