// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHAT THE MAP NEEDS TO BE TOLD — the chart's own read model, and deliberately its own.
//
// These types describe the SHAPE OF A VIEW, not the shape of the database. The map is handed a
// port table, a fleet list and (for a fleet at sea) the voyage row's frozen speed profile; it
// renders those and asks for nothing else. When the real fixtures and the real RPC land, the
// adapter that maps a server row onto these types is the only thing that changes — no layer, no
// glyph and no maths in this folder knows the wire format.
//
// THREE THINGS ARE ABSENT ON PURPOSE:
//   · Other players. DESIGN §E.5 forbids drawing them: rivals on a chart make it a targeting
//     surface, and this game has no PvP (§J.2). There is no field here that could carry one.
//   · Any callback that changes the world. The only events this chart raises are selections, and a
//     selection is a VIEW change. Orders are composed on the Command tab, in words.
//   · Position. A fleet at sea does not have a stored position — it has a departure time and a
//     frozen speed profile, and its position is derived from those (§D.2, ./voyage.ts).
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import type { LatLon } from '../../lib/geo'

/** A port as the chart needs it: a name to print and a place to print it. */
export interface MapPort extends LatLon {
  /** Stable short code — `LIS`, `CAD`. The id every other structure here refers to a port by. */
  readonly code: string
  readonly name: string
  /** The country as it read in 1550 (DESIGN §B.2) — this is a period chart, not an atlas. */
  readonly country: string
}

/** One leg of a voyage exactly as the server froze it at departure (§D.2: `speed_profile jsonb`).
 *  `distanceNm` is the AUTHORED leg distance, which may exceed the great-circle figure where the
 *  real route detours (§B.3); the chart draws the great circle but times the authored number. */
export interface VoyageLeg {
  readonly fromPort: string
  readonly toPort: string
  readonly distanceNm: number
  /** `v_fleet` for this leg in knots, frozen at departure. Never recomputed client-side. */
  readonly speedKn: number
}

/** A voyage row, reduced to the three things a position needs. */
export interface Voyage {
  /** Server departure instant, epoch ms. THE origin of the closed form — never a local start time. */
  readonly departedAtMs: number
  /** Ordered legs. `legs[0].fromPort` is where it sailed from; the last `toPort` is where it is bound. */
  readonly legs: readonly VoyageLeg[]
}

/** A fleet, in exactly one of the two states the chart can draw. */
export type MapFleet =
  | { readonly kind: 'docked'; readonly id: string; readonly name: string; readonly portCode: string }
  | { readonly kind: 'sailing'; readonly id: string; readonly name: string; readonly voyage: Voyage }

/**
 * What the player has singled out to read about. ONE selection concept for the whole chart, so
 * there is exactly one detail panel and it can never disagree with itself.
 * `null` = nothing selected; the detail panel is not rendered at all.
 */
export type MapSelection =
  | { readonly kind: 'fleet'; readonly id: string }
  | { readonly kind: 'port'; readonly code: string }
  | null
