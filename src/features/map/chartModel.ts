// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHAT THE CHART DRAWS, THIS INSTANT — derived, never stored.
//
// Every frame the map asks this module the same question: given the fleets, the port table and the
// wall clock, what is on the paper? Nothing here is remembered between calls. That is the whole
// discipline of DESIGN §D.2 expressed as a data shape — there is no position to corrupt, because
// there is no position, only a function of `nowMs`.
//
// It is also the ONE place that decides which ports are "in use", so the loud/quiet split (§E.5:
// ports a fleet is not using are quieter) cannot be computed two different ways in two layers.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import type { LatLon } from '../../lib/geo'
import type { MapFleet, MapPort } from './mapTypes'
import { buildTrack, type TrackPaths } from './route'
import { destinationPortCode, voyagePoint, voyagePortCodes, voyageProgress, type VoyageProgress } from './voyage'

/** One fleet, resolved to ink. */
export interface FleetOnChart {
  readonly fleet: MapFleet
  /** Where to draw the glyph — the closed-form position for a fleet at sea, the quay for one at anchor. */
  readonly at: LatLon
  /** Null for a docked fleet: it is not on a passage, so it has no progress to report. */
  readonly progress: VoyageProgress | null
  /** Null for a docked fleet: no passage, no track. */
  readonly track: TrackPaths | null
  /** Where it is bound, if it is bound anywhere. */
  readonly destinationCode: string | null
  /** The port it lies in, if it lies in one. */
  readonly dockedAtCode: string | null
}

/**
 * WHY A PORT MATTERS TO YOU, RIGHT NOW. One authority for the loud/quiet split (§E.5: ports a
 * fleet is not using are quieter) AND for label priority (./labels.ts) — computed once here so the
 * glyph layer and the label engine can never disagree about which ports count.
 *
 *   anchorage    one of your fleets lies in it
 *   destination  one of your fleets is bound for it
 *   route        it is on a fleet's path but is neither of the above
 *
 * A port with no role is quiet.
 */
export type PortRole = 'anchorage' | 'destination' | 'route'

/** The whole picture at one instant. */
export interface ChartModel {
  readonly fleets: readonly FleetOnChart[]
  /** Ports any fleet is using, and why. Absent = quiet. */
  readonly portRoles: ReadonlyMap<string, PortRole>
  /** Ports some fleet is STILL bound for, with where they are — one entry per port, so two fleets
   *  converging on Cádiz do not stack two destination rings on it. */
  readonly destinationPoints: ReadonlyMap<string, LatLon>
  /**
   * EVERYTHING OF YOURS: each fleet's position, the ports they are bound for, and the ports they
   * lie in — but not the whole port table. This is what the opening view frames when the surface
   * is wide enough to hold it (see `openingBounds` in ./chartView.ts).
   */
  readonly focusPoints: readonly LatLon[]
  /**
   * WHAT IS ACTUALLY MOVING: the fleets at sea, the water still ahead of them, and where they are
   * going. A subset of `focusPoints`, and the fallback frame for a surface too narrow to hold the
   * lot without burying the action in empty ocean.
   */
  readonly motionPoints: readonly LatLon[]
}

/** Resolve a voyage's port codes to coordinates. A code with no port in the table is dropped: the
 *  chart draws what it can place and never invents a position. */
function waypointsOf(codes: readonly string[], portsByCode: ReadonlyMap<string, MapPort>): LatLon[] {
  const out: LatLon[] = []
  for (const code of codes) {
    const port = portsByCode.get(code)
    if (port) out.push({ lat: port.lat, lon: port.lon })
  }
  return out
}

export function buildChartModel(
  fleets: readonly MapFleet[],
  ports: readonly MapPort[],
  nowMs: number,
): ChartModel {
  const portsByCode = new Map(ports.map((p) => [p.code, p]))
  const roles = new Map<string, PortRole>()
  const destinations = new Map<string, LatLon>()
  const drawn: FleetOnChart[] = []
  const focus: LatLon[] = []
  const motion: LatLon[] = []

  // An anchorage outranks a route port, and a destination outranks both: a port can be on one
  // fleet's route AND be another's destination, and it should read as the louder of the two.
  const RANK: Record<PortRole, number> = { route: 0, anchorage: 1, destination: 2 }
  const setRole = (code: string, role: PortRole) => {
    const current = roles.get(code)
    if (!current || RANK[role] > RANK[current]) roles.set(code, role)
  }

  for (const fleet of fleets) {
    if (fleet.kind === 'docked') {
      const port = portsByCode.get(fleet.portCode)
      if (!port) continue
      setRole(port.code, 'anchorage')
      focus.push({ lat: port.lat, lon: port.lon })
      drawn.push({
        fleet,
        at: { lat: port.lat, lon: port.lon },
        progress: null,
        track: null,
        destinationCode: null,
        dockedAtCode: port.code,
      })
      continue
    }

    const codes = voyagePortCodes(fleet.voyage)
    const waypoints = waypointsOf(codes, portsByCode)
    if (waypoints.length < 2) continue
    for (const code of codes) if (portsByCode.has(code)) setRole(code, 'route')

    const progress = voyageProgress(fleet.voyage, nowMs)
    const at = voyagePoint(progress, waypoints)
    const destination = destinationPortCode(fleet.voyage)

    // Arrived, as far as the picture is concerned: draw it on the quay with no track. The server
    // still owns whether it HAS arrived; this only stops the map showing a dot parked at sea while
    // the arrival tick catches up.
    if (progress.arrived) {
      if (destination) setRole(destination, 'anchorage')
      focus.push(waypoints[waypoints.length - 1])
      // Arrived: it is at anchor now, so it is no longer part of what is in motion.
      drawn.push({
        fleet,
        at: waypoints[waypoints.length - 1],
        progress,
        track: null,
        destinationCode: destination,
        dockedAtCode: destination,
      })
      continue
    }

    // The ring marks where a fleet is STILL going, so it is recorded only for a fleet at sea.
    const destinationPort = destination ? portsByCode.get(destination) : undefined
    if (destination && destinationPort) {
      destinations.set(destination, { lat: destinationPort.lat, lon: destinationPort.lon })
      setRole(destination, 'destination')
      focus.push({ lat: destinationPort.lat, lon: destinationPort.lon })
      motion.push({ lat: destinationPort.lat, lon: destinationPort.lon })
    }
    // Where it is NOW is as much a part of "where the action is" as where it is going — and so is
    // the water in between, so a long leg's remaining waypoints are framed too.
    focus.push(at)
    motion.push(at, ...waypoints.slice(Math.min(progress.legIndex + 1, waypoints.length - 1)))

    drawn.push({
      fleet,
      at,
      progress,
      track: buildTrack(waypoints, progress, at),
      destinationCode: destination,
      dockedAtCode: null,
    })
  }

  return {
    fleets: drawn,
    portRoles: roles,
    destinationPoints: destinations,
    // With no fleets at all there is no action to frame, so the whole port table stands in — a map
    // that opens on empty ocean would be worse than one that opens too wide.
    focusPoints: focus.length > 0 ? focus : ports.map((p) => ({ lat: p.lat, lon: p.lon })),
    motionPoints: motion,
  }
}

/** The fleets lying in a given port, by name — what the port card answers "do I have anything
 *  here?" with. */
export function fleetsAtPort(model: ChartModel, portCode: string): readonly FleetOnChart[] {
  return model.fleets.filter((f) => f.dockedAtCode === portCode)
}

/** The fleets bound for a given port. */
export function fleetsBoundFor(model: ChartModel, portCode: string): readonly FleetOnChart[] {
  return model.fleets.filter((f) => f.dockedAtCode === null && f.destinationCode === portCode)
}
