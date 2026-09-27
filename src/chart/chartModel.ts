// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHAT THE CHART DRAWS — resolved from the last read, and from nothing else.
//
// The map asks this module one question: given the fleets and the port table the server just
// handed over, what is on the paper? It takes NO CLOCK. It used to: positions were a function of
// `nowMs` through a client copy of §D.2's closed form. They are not any more — `voyage.position`
// arrives already computed (./liveWorld.ts), so the only thing left that a clock could change is
// the wording of a countdown, and that belongs to the panel that prints it.
//
// AMENDED 2026-09-03, and the amendment is narrow on purpose. It takes an OPTIONAL pair of
// instants now (`Drift`), and with it a fleet at sea is drawn a fraction further along the leg the
// server put her on. That is not the mover this file deleted: `./drift.ts` cannot leave that
// segment, cannot move her backwards, measures nothing, and is thrown away whole on every read.
// Omit the argument and this module is exactly what the paragraph above describes — which is what
// every caller but the Map tab does.
//
// It is also the ONE place that decides which ports are "in use", so the loud/quiet split (§E.5:
// ports a fleet is not using are quieter) cannot be computed two different ways in two layers.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { project, type LatLon, type ViewBox } from '../lib/geo'
import type { MapFleet, MapPort, MapVoyage } from './mapTypes'
import { buildTrack, type TrackPaths } from './route'
import { driftedPoint, type Drift } from './drift'
import { headingDeg } from './glyphs'

/** One fleet, resolved to ink. */
export interface FleetOnChart {
  readonly fleet: MapFleet
  /** Where to draw the glyph — the server's closed-form position at sea, the quay when docked,
   *  the held coordinate at an open anchor. */
  readonly at: LatLon
  /** Null unless she is on a passage. */
  readonly voyage: MapVoyage | null
  /** Null unless she is on a passage: the served course, split at the served position. */
  readonly track: TrackPaths | null
  /**
   * WHICH WAY HER BOW POINTS (row 90): the heading of the served segment she is on, degrees
   * clockwise from north, for the ship glyph's turn. Null when she is not under way (docked, or
   * at an open anchor) — a ship that is going nowhere points north, and the layer says so. Read
   * off `course[segIndex] → course[segIndex + 1]`, the same two vertices `voyage.position` placed
   * her between; nothing is measured and nothing moves her.
   */
  readonly heading: number | null
  /** The PORT she is bound for, if she is bound for one (a point-bound voyage has none). */
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
 *   route        RETIRED with the leg graph (0039): a free course has no port endpoints to mark.
 *                The member stays in the type so the priority tables need no re-cut; nothing
 *                assigns it any more.
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
  /** Bare points of open water fleets are bound for (0039) — ringed exactly like a destination
   *  port, because they are one. */
  readonly destinationSeaPoints: readonly LatLon[]
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
  /**
   * PORTS THE PLAYER IS CHOOSING BETWEEN — the destination being composed on the Command tab,
   * before any order has been issued and therefore before any fleet is bound anywhere.
   *
   * It is a parameter on THIS function rather than an overlay computed by the screen that wanted it,
   * because "which ports are loud, and which of them are ringed" has exactly one author (see this
   * file's header, and `docs/NO_SPAGHETTI.md` §1: *owned but too narrow → generalise that one owner
   * and repoint every caller*). A second table of roles assembled beside the model could disagree
   * with it, and the glyph layer, the label planner and the hit test all read the model's.
   *
   * It takes the SAME role a served destination takes, because it is the same fact one moment
   * earlier: *this is where she would be going*. Nothing here implies a course — the ring means a
   * place, and no track is drawn to it (the server serves no legs for a voyage that does not exist).
   * Empty by default, which is the map tab: it draws what the world says, never what is being typed.
   */
  considering: readonly string[] = [],
  /**
   * 0075 — THE TWO INSTANTS, or null for the clock-free model this file was built to be.
   *
   * Omit it and every position is the server's, byte for byte, exactly as before: the read is the
   * only thing that moves a glyph. Pass it and a fleet at sea is drawn where `./drift.ts` places
   * her — the same point, advanced along the leg the server put her on and clamped at that leg's
   * far vertex, so the model can be finer than the read without ever being ahead of it.
   *
   * It is a parameter here, on the ONE authority for "where is she on the paper", rather than a
   * nudge applied by the layer that draws the dot. The dot, the sailed/ahead track split, her
   * label's anchor, the minimap and the framing all read `FleetOnChart.at`; a smoothing applied to
   * only one of them would be a second position, and the panel would then disagree with the glyph.
   */
  drift: Drift | null = null,
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

  const seaDestinations: LatLon[] = []
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
        voyage: null,
        track: null,
        heading: null,
        destinationCode: null,
        dockedAtCode: fleet.portCode,
      })
      continue
    }

    if (fleet.kind === 'anchored') {
      // She holds a bare point of open water (0039): drawn like a fleet at sea, with no track —
      // she is not going anywhere until ordered.
      focus.push(fleet.at)
      drawn.push({
        fleet,
        at: fleet.at,
        voyage: null,
        track: null,
        heading: null,
        destinationCode: null,
        dockedAtCode: null,
      })
      continue
    }

    const voyage = fleet.voyage

    // The ring marks where the voyage ends — a port, or a bare point of water (0039). The course
    // itself is SERVED whole now, so the track below is the real line, not an invention.
    if (voyage.destinationCode) {
      const destination = placeOf(voyage.destinationCode)
      if (destination) {
        setRole(voyage.destinationCode, 'destination')
        destinations.set(voyage.destinationCode, destination)
        focus.push(destination)
        motion.push(destination)
      }
    } else if (voyage.destPoint) {
      seaDestinations.push(voyage.destPoint)
      focus.push(voyage.destPoint)
      motion.push(voyage.destPoint)
    }

    // ONE POSITION, and everything below reads it: the glyph, the track's split, her label's
    // anchor, the framing and the minimap. With no drift given this IS `voyage.at`.
    const at = driftedPoint(voyage, drift)

    focus.push(at)
    motion.push(at)

    // The served segment she is on — the same clamp `buildTrack` splits the course at.
    const cut = Math.min(Math.max(voyage.segIndex, 0), voyage.course.length - 2)
    const segFrom = voyage.course[cut]
    const segTo = voyage.course[cut + 1]
    drawn.push({
      fleet,
      at,
      voyage,
      track: buildTrack(voyage.course, at, voyage.segIndex),
      heading: segFrom && segTo ? headingDeg(project(segFrom), project(segTo)) : null,
      destinationCode: voyage.destinationCode,
      dockedAtCode: null,
    })
  }

  // AFTER the fleets, so a port that is BOTH — she lies there and it is also the one being
  // considered — keeps the role the world gave it and simply gains the ring. `setRole` already
  // ranks destination above anchorage, and `destinations` is a map keyed by code, so a port cannot
  // collect two rings however many ways it earns one.
  for (const code of considering) {
    const at = placeOf(code)
    if (!at) continue
    setRole(code, 'destination')
    destinations.set(code, at)
    focus.push(at)
    motion.push(at)
  }

  return {
    fleets: drawn,
    portRoles: roles,
    destinationPoints: destinations,
    destinationSeaPoints: seaDestinations,
    // With no fleets at all there is no action to frame. Left EMPTY rather than filled with the
    // port table: `openingBounds` takes its own fallback and is the one place that decides what a
    // player with nothing gets to look at.
    focusPoints: focus,
    motionPoints: motion,
  }
}

/**
 * ONE HARBOUR'S MARK AT THIS ZOOM (row 94, 2026-09-14: *"i want to see all the countries, all the
 * ports in the game when i zoom out, it can be a dot, then once zoomed in i will be able to see
 * the marker"*). `full` = the triangle (or lozenge), its ring if great, its roads and its name;
 * not full = a DOT in the quiet ink and nothing else. The same harbour, the same `data-port-code`,
 * one rendering or the other — never two layers.
 */
export interface PortMark {
  readonly port: MapPort
  readonly full: boolean
}

/**
 * EVERY PORT ON THE PAPER, and how each is drawn — the whole answer to 224 harbours on one sheet.
 *
 * A port is on the sheet when it is on the glass. FULL when it is big enough for this zoom
 * (`minTier`, decided by ./chartView.ts) or one of yours (a role — your anchorage wears its full
 * mark at every zoom, whatever size it is); otherwise a dot. Before row 94 a port below the tier
 * floor was not drawn at all; now it is drawn small, so the globe shows every harbour there is.
 *
 * ONE list. The marks layer draws every entry (full or dot); `visiblePorts` below is its FULL
 * half — what asks for a name, shows its roads, and answers a tap at the full reach; `dotPorts`
 * is the other half — what answers a tap at half a touch, behind a name whose mark is as near. The
 * order was measured,
 * not assumed: with dots in the SAME hit test as the names, at the phone's opening frame a tap
 * on the word "Cadiz" opened Sanlúcar — a tier-2 dot 5 px north of the Cádiz mark was nearer to
 * the name than the mark it names (tests/map.sendfleet.spec.ts caught it, row 94), and dots had
 * no tap at all until row 104 (2026-09-18: *"when i click i see coordinates. it should be the
 * corresponding city"*) gave them their own, tighter reach (./hitTest.ts).
 */
export function portMarks(
  ports: readonly MapPort[],
  roles: ReadonlyMap<string, PortRole>,
  view: ViewBox,
  minTier: number,
  /** A little beyond the edge, so a mark half off the glass still blocks a label that would
   *  otherwise be printed across it. */
  margin = 0.06,
): PortMark[] {
  const padX = view.width * margin
  const padY = view.height * margin
  const minX = view.x - padX
  const maxX = view.x + view.width + padX
  const minY = view.y - padY
  const maxY = view.y + view.height + padY

  const out: PortMark[] = []
  for (const port of ports) {
    const at = project(port)
    if (at.x < minX || at.x > maxX || at.y < minY || at.y > maxY) continue
    out.push({ port, full: port.sizeTier >= minTier || roles.has(port.code) })
  }
  return out
}

/**
 * WHICH PORTS WEAR THEIR FULL MARK AT THIS ZOOM — `portMarks`' full half, as a plain list.
 *
 * This is the list the label planner plans (./labels.ts: a dot has no name), the roadstead
 * layer draws roads for (./roadsteads.ts: a dot has no roads) and the hit test tests at the
 * full reach (./hitTest.ts: a dot answers at half a touch, and never over a mark as near). It is derived from `portMarks`, never
 * computed beside it, so a name can never be asked for a port drawn as a dot and a full mark
 * can never go unnamed for want of being in the list.
 *
 * Before row 94 this was the whole drawn set; the pins in tests/map.labels.spec.ts (35 on the
 * globe, 114 on a sea, all of them on a coast) are the same numbers with the same meaning.
 */
export function visiblePorts(
  ports: readonly MapPort[],
  roles: ReadonlyMap<string, PortRole>,
  view: ViewBox,
  minTier: number,
  margin = 0.06,
): MapPort[] {
  const out: MapPort[] = []
  for (const mark of portMarks(ports, roles, view, minTier, margin)) if (mark.full) out.push(mark.port)
  return out
}

/**
 * WHICH PORTS ARE DOTS AT THIS ZOOM — `portMarks`' other half, the complement of `visiblePorts`
 * over the same call, so the two can never overlap or leave a drawn harbour out. The hit test
 * reads it at the dot's own reach (./hitTest.ts): a dot is the city it stands for (row 104), but
 * a name whose mark is within half a touch of the thumb is what the tap meant.
 */
export function dotPorts(
  ports: readonly MapPort[],
  roles: ReadonlyMap<string, PortRole>,
  view: ViewBox,
  minTier: number,
  margin = 0.06,
): MapPort[] {
  const out: MapPort[] = []
  for (const mark of portMarks(ports, roles, view, minTier, margin)) if (!mark.full) out.push(mark.port)
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
