// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHAT THE MAP NEEDS TO BE TOLD — the chart's own read model, and deliberately its own.
//
// These types describe the SHAPE OF A VIEW, not the shape of the database. The map is handed a
// port table and a fleet list; it renders those and asks for nothing else. ./liveWorld.ts is the
// ONLY module that knows the wire format, so no layer, no glyph and no maths in this folder has
// ever heard of `snake_case`, `FleetView` or an RPC.
//
// THREE THINGS ARE ABSENT ON PURPOSE:
//   · Other players. DESIGN §E.5 forbids drawing them: rivals on a chart make it a targeting
//     surface, and this game has no PvP (§J.2). There is no field here that could carry one.
//   · Any callback that changes the world. The only events this chart raises are selections, and a
//     selection is a VIEW change. Orders are composed on the Command tab, in words.
//   · Any way to DERIVE a position. A fleet at sea arrives here already placed — `MapVoyage.at`
//     is the server's closed form (DESIGN §D.2, `voyage.position()`), copied, not recomputed. The
//     departure time and the frozen speed profile are not served and are not wanted: a second
//     implementation of the movement rule on this side of the wire is exactly the thing the live
//     store's third rule forbids. See ./liveWorld.ts.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import type { LatLon } from '../lib/geo'

/** A port as the chart needs it: a name to print, a place to print it, and how big a mark it earns. */
export interface MapPort extends LatLon {
  /** Stable short code — `LIS`, `CAD`. The id every other structure here refers to a port by. */
  readonly code: string
  readonly name: string
  /** The country as it read in 1550 (DESIGN §B.2) — this is a period chart, not an atlas. */
  readonly country: string
  /**
   * 1–5, straight from `ports.size_tier`. THE WHOLE ANSWER TO 214 PORTS ON ONE SHEET: the mark is
   * scaled by it (./glyphs.ts), the zoom decides which tiers are drawn at all (./chartView.ts), and
   * a quiet port's label priority is lifted by it (./labels.ts). One column, three consequences,
   * and none of them is a hand-picked list of "important" ports.
   */
  readonly sizeTier: number
  /**
   * 0036: `HARBOUR` is a town with a quay; `SEA_PLACE` is a named water — a bank, a strait, a
   * belt of wind — with nothing ashore. Same node of the same graph, so everything else here
   * treats them alike; the ONE consequence on the chart is the glyph (PortsLayer draws a lozenge
   * instead of a triangle, because a mark that promises a town where there is only sea is a lie
   * at exactly the scale a chart exists to be trusted at).
   */
  readonly kind: 'HARBOUR' | 'SEA_PLACE'
}

/**
 * A VOYAGE, EXACTLY AS THE SERVER SERVES IT (0039): the WHOLE course she sails, and where on it
 * she is. The course is the verified water polyline the server measured and froze — the chart
 * draws exactly this line and never invents one of its own (./route.ts's header carries the
 * geometry rule).
 *
 * `at` is the server's closed-form position, placed LINEARLY along `course[segIndex]` — copied,
 * never derived here.
 */
export interface MapVoyage {
  /** The whole served course, in sailing order. At least two points. */
  readonly course: readonly LatLon[]
  /** Which segment of the course the position lies on (`voyage.position.seg_index`). */
  readonly segIndex: number
  /** The closed-form position (§D.2). Copied from the server; never derived here. */
  readonly at: LatLon
  /** Whole-voyage progress, in nautical miles — the server's numbers, printed as given. */
  readonly sailedNm: number
  readonly totalNm: number
  /** Arrival instant, epoch ms, from `voyage.eta`. A countdown is display; arrival is the server's. */
  readonly etaMs: number
  /** The port the voyage ends at — null when she is bound for a bare point of open water. */
  readonly destinationCode: string | null
  /** The open-water destination; null when `destinationCode` names a port. Exactly one is set. */
  readonly destPoint: LatLon | null
  /**
   * THE WATERS SHE STILL HAS TO CROSS (0055), in sailing order, first row = the sea she is in.
   * Served on `world.fleets().voyage.waters`; every field is the server's, copied.
   *
   * It is a LIST OF PLACES, not a forecast. The chart has no idea what will happen on any of these
   * days and must never be given one: `voyage.hazard_roll` is pure, so predicting it is trivial and
   * refused — see migration 0055's header for both reasons, the design one and the measured one.
   */
  readonly waters: readonly MapWater[]
}

/** One sea a voyage still has to cross — `VoyageWater`, in the chart's own words. */
export interface MapWater {
  readonly code: string
  readonly name: string
  /** 1–5, straight from `seas.danger_level`. Drawn by `DangerMark`; never derived here. */
  readonly danger: number
  /** The sea's character in plain words (`seas.note`) — a name, not a sentence. */
  readonly note: string
  /** Sailed nm she must still make good to enter it; 0 for the one she is in. */
  readonly nmTo: number
  /** How much of her remaining passage lies in it. */
  readonly nmIn: number
  /** True for the water she is in now — always exactly the first entry. */
  readonly now: boolean
}

/** A fleet, in exactly one of the three states the chart can draw (0039 added the open anchor). */
export type MapFleet =
  | { readonly kind: 'docked'; readonly id: string; readonly name: string; readonly portCode: string }
  | { readonly kind: 'sailing'; readonly id: string; readonly name: string; readonly voyage: MapVoyage }
  | { readonly kind: 'anchored'; readonly id: string; readonly name: string; readonly at: LatLon }

/**
 * What the player has singled out to read about. ONE selection concept for the whole chart, so
 * there is exactly one detail panel and it can never disagree with itself.
 * `null` = nothing selected; the detail panel is not rendered at all.
 */
export type MapSelection =
  | { readonly kind: 'fleet'; readonly id: string }
  | { readonly kind: 'port'; readonly code: string }
  /** A pinpointed spot of open water (0039) — already SNAPPED to sailable sea by the screen that
   *  made it, so what the panel offers to sail to is water by construction. */
  | { readonly kind: 'sea'; readonly at: LatLon }
  | null
