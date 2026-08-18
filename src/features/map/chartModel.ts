// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHAT THE CHART DRAWS — resolved from the last read, and from nothing else.
//
// The map asks this module one question: given the fleets and the port table the server just
// handed over, what is on the paper? It takes NO CLOCK. It used to: positions were a function of
// `nowMs` through a client copy of §D.2's closed form. They are not any more — `voyage.position`
// arrives already computed (./liveWorld.ts), so the only thing left that a clock could change is
// the wording of a countdown, and that belongs to the panel that prints it.
//
// It is also the ONE place that decides which ports are "in use", so the loud/quiet split (§E.5:
// ports a fleet is not using are quieter) cannot be computed two different ways in two layers.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { project, type LatLon, type ViewBox } from '../../lib/geo'
import type { MapFleet, MapPort, MapVoyageLeg } from './mapTypes'
import { buildTrack, type TrackPaths } from './route'

/** One fleet, resolved to ink. */
export interface FleetOnChart {
  readonly fleet: MapFleet
  /** Where to draw the glyph — the server's closed-form position at sea, the quay at anchor. */
  readonly at: LatLon
  /** Null for a docked fleet: it is not on a passage, so there is no leg to report. */
  readonly leg: MapVoyageLeg | null
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
 *   route        it is an end of the leg a fleet is on, and is neither of the above
 *
 * A port with no role is quiet.
 */
export type PortRole = 'anchorage' | 'destination' | 'route'

/** The whole picture. */
export interface ChartModel {
  readonly fleets: readonly FleetOnChart[]
  /** Ports any fleet is using, and why. Absent = quiet. */
  readonly portRoles: ReadonlyMap<string, PortRole>
  /** Ports some fleet is STILL bound for, with where they are — one entry per port, so two fleets
   *  converging on Cádiz do not stack two destination rings on it. */
  readonly destinationPoints: ReadonlyMap<string, LatLon>
  /**
   * EVERYTHING OF YOURS: each fleet's position, the ports they are bound for, and the ports they
   * lie in — but not the whole port table. With 214 harbours on the sheet that distinction is the
   * difference between opening on your own water and opening on the globe. This is what the opening
   * view frames when the surface is wide enough to hold it (see `openingBounds` in ./chartView.ts).
   */
  readonly focusPoints: readonly LatLon[]
  /**
   * WHAT IS ACTUALLY MOVING: the fleets at sea, the water still ahead of them on the current leg,
   * and where they are going. A subset of `focusPoints`, and the fallback frame for a surface too
   * narrow to hold the lot without burying the action in empty ocean.
   */
  readonly motionPoints: readonly LatLon[]
}

export function buildChartModel(
  fleets: readonly MapFleet[],
  ports: readonly MapPort[],
): ChartModel {
  const portsByCode = new Map(ports.map((p) => [p.code, p]))
  const roles = new Map<string, PortRole>()
  const destinations = new Map<string, LatLon>()
  const drawn: FleetOnChart[] = []
  const focus: LatLon[] = []
  const motion: LatLon[] = []

  // An anchorage outranks a route port, and a destination outranks both: a port can be one end of
  // one fleet's leg AND be another's destination, and it should read as the louder of the two.
  const RANK: Record<PortRole, number> = { route: 0, anchorage: 1, destination: 2 }
  const setRole = (code: string, role: PortRole) => {
    const current = roles.get(code)
    if (!current || RANK[role] > RANK[current]) roles.set(code, role)
  }
  const placeOf = (code: string): LatLon | null => {
    const port = portsByCode.get(code)
    return port ? { lat: port.lat, lon: port.lon } : null
  }

  for (const fleet of fleets) {
    if (fleet.kind === 'docked') {
      const at = placeOf(fleet.portCode)
      // A code with no port in the table is dropped: the chart draws what it can place and never
      // invents a position.
      if (!at) continue
      setRole(fleet.portCode, 'anchorage')
      focus.push(at)
      drawn.push({
        fleet,
        at,
        leg: null,
        track: null,
        destinationCode: null,
        dockedAtCode: fleet.portCode,
      })
      continue
    }

    const leg = fleet.leg
    const from = placeOf(leg.fromCode)
    const to = placeOf(leg.toCode)
    if (!from || !to) continue

    setRole(leg.fromCode, 'route')
    setRole(leg.toCode, 'route')

    // The ring marks where the VOYAGE ends, which may be several legs further on than `toCode`.
    // The server does not serve those legs (README §4.8), so the destination is RINGED and never
    // routed: the chart says where the fleet is going without drawing water it was not given.
    const destination = placeOf(leg.destinationCode)
    if (destination) {
      setRole(leg.destinationCode, 'destination')
      destinations.set(leg.destinationCode, destination)
      focus.push(destination)
      motion.push(destination)
    }

    focus.push(leg.at, to)
    motion.push(leg.at, to)

    drawn.push({
      fleet,
      at: leg.at,
      leg,
      track: buildTrack(from, to, leg.at),
      destinationCode: leg.destinationCode,
      dockedAtCode: null,
    })
  }

  return {
    fleets: drawn,
    portRoles: roles,
    destinationPoints: destinations,
    // With no fleets at all there is no action to frame. Left EMPTY rather than filled with the
    // port table: `openingBounds` takes its own fallback and is the one place that decides what a
    // player with nothing gets to look at.
    focusPoints: focus,
    motionPoints: motion,
  }
}

/**
 * WHICH PORTS ARE ON THE PAPER AT ALL — the first half of the answer to 214 harbours.
 *
 * A port is drawn when it is on the glass AND it is either big enough for this zoom (`minTier`,
 * decided by ./chartView.ts) or one of yours (it has a role — your anchorage is drawn at every
 * zoom, whatever size it is).
 *
 * ONE list, consumed three times: the marks layer draws it, the label planner plans it, and the
 * hit test tests it. That is deliberate — a port you can tap but cannot see, or a name floating
 * over a mark that was never drawn, are both the same bug, and this is where it is made impossible.
 */
export function visiblePorts(
  ports: readonly MapPort[],
  roles: ReadonlyMap<string, PortRole>,
  view: ViewBox,
  minTier: number,
  /** A little beyond the edge, so a mark half off the glass still blocks a label that would
   *  otherwise be printed across it. */
  margin = 0.06,
): MapPort[] {
  const padX = view.width * margin
  const padY = view.height * margin
  const minX = view.x - padX
  const maxX = view.x + view.width + padX
  const minY = view.y - padY
  const maxY = view.y + view.height + padY

  const out: MapPort[] = []
  for (const port of ports) {
    if (port.sizeTier < minTier && !roles.has(port.code)) continue
    const at = project(port)
    if (at.x < minX || at.x > maxX || at.y < minY || at.y > maxY) continue
    out.push(port)
  }
  return out
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
