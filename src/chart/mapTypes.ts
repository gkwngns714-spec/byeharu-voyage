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
//   · Any way to DERIVE a position. A fleet at sea arrives here already placed — `MapVoyageLeg.at`
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
 * THE CURRENT LEG OF A VOYAGE, EXACTLY AS THE SERVER SERVES IT — and nothing beyond it.
 *
 * `world.fleets()` carries `voyage.position`: the leg the fleet is on, how far along it, and the
 * lat/lon that follows (README §4.8). It does NOT carry the planned route, so the chart draws the
 * CURRENT LEG and only that. A line to a port the server never mentioned would be an invention.
 *
 * `at` is the server's own display geometry: `voyage.position()` interpolates LINEARLY in lat/lon
 * between the two ports. The track is therefore drawn as a straight segment in chart units
 * (./route.ts) — on an equirectangular chart that is the same line, so the glyph sits exactly on
 * its own track instead of beside a great circle it is not following.
 */
export interface MapVoyageLeg {
  readonly fromCode: string
  readonly toCode: string
  /** The closed-form position (§D.2). Copied from the server; never derived here. */
  readonly at: LatLon
  /** 0–1 along THIS leg. */
  readonly legFrac: number
  /** Whole-voyage progress, in nautical miles — the server's numbers, printed as given. */
  readonly sailedNm: number
  readonly totalNm: number
  /** Arrival instant, epoch ms, from `voyage.eta`. A countdown is display; arrival is the server's. */
  readonly etaMs: number
  /** Where the voyage ENDS (`voyage.to`), which may lie beyond `toCode`. It is ringed, not routed. */
  readonly destinationCode: string
}

/** A fleet, in exactly one of the two states the chart can draw. */
export type MapFleet =
  | { readonly kind: 'docked'; readonly id: string; readonly name: string; readonly portCode: string }
  | { readonly kind: 'sailing'; readonly id: string; readonly name: string; readonly leg: MapVoyageLeg }

/**
 * What the player has singled out to read about. ONE selection concept for the whole chart, so
 * there is exactly one detail panel and it can never disagree with itself.
 * `null` = nothing selected; the detail panel is not rendered at all.
 */
export type MapSelection =
  | { readonly kind: 'fleet'; readonly id: string }
  | { readonly kind: 'port'; readonly code: string }
  | null
