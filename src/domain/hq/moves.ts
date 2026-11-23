// ═══════════════════════════════════════════════════════════════════════════════════════════════
// HQ'S BEST MOVES — THE ONE RANKING RULE (docs/design/hq-command-2026-11-23.md §3, the HQ command board v1)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-11-23: *"i want this game to be strategical game, where all the work(activities) are done in HQ … choosing best
// options available, finding best options."* The board lists every move open to her now as a card; this file is the ONLY client place that
// orders them. 0480 (v2) SERVES THE SAME RULE: lit (hq_board_enabled), `world.hq_board()` ranks every move on the server (its ORDER BY in
// public.hq_board_for, the bands below) and the board draws that order as it comes; this file ranks only the dark fallback (v1).
//
// THE RULE, in order:
//   1. THE YARD, when her purse covers the second ship's Order: a second hull is a second earner, so it beats any one trip.
//   2. TRADE RUNS, REQUESTS AND COURIER CONTRACTS (0483, served only), together, by coin per hour:
//        a trade run  = the served profit (world.best_sales) / the served time to the sale (`seconds`, else `days`);
//        a request    = the served premium for the units she holds / a quarter hour (she is docked there: fulfilling is one press,
//                       so the quarter hour is the floor that keeps a small premium from outranking a real trip).
//      A move with no time served stands after every move that has one.
//   3. COLLECT THE LAND PARTY'S GOODS, come home (served only: 0480).
//   4. HIRE A CAPTAIN, for a fleet with no one in her cabins.
//   5. INVEST, when coin sits idle.
// Ties: the bigger headline figure first, then the id (a stable order: a card does not jump on the beat).
// Nothing is judged here that the server judges (whether she can sail there, whether it pays): a move is built only from served
// figures, and the press is the desk's, the yard's, the inn's or the Office's own.

export type MoveKind = 'trade' | 'request' | 'contract' | 'yard' | 'land' | 'crew' | 'invest'

/** The board's filter chips, in their order. */
export const MOVE_KINDS: readonly MoveKind[] = ['trade', 'request', 'contract', 'yard', 'land', 'crew', 'invest']

export interface Move<T = unknown> {
  id: string
  kind: MoveKind
  /** The headline figure: coin gained (a trade, a request), the price (the yard), the idle coin (invest); null for none. */
  gain: number | null
  /** Coin per hour, by the rule above; null when no time is served. */
  perHour: number | null
  /** The time it takes, in real seconds; null when not served. */
  seconds: number | null
  /** The fleet it is for, if any. */
  fleet: string | null
  /** What the card needs to draw and press it (the caller's; never read here). */
  data: T
}

/** A request's floor of time: a quarter hour (rule 2). */
export const REQUEST_FLOOR_S = 15 * 60

/** Coin per hour for a gain over a time in seconds; null without a positive time. */
export function perHourOf(gain: number | null, seconds: number | null): number | null {
  if (gain === null || seconds === null || !(seconds > 0)) return null
  return (gain * 3600) / seconds
}

/** The bands, the server's own (public.hq_board_for's `band`). */
const BAND: Record<MoveKind, number> = { yard: 0, trade: 1, request: 1, contract: 1, land: 2, crew: 3, invest: 4 }

/** The board's order (the rule above). Pure: a new array, the input untouched. */
export function rankMoves<T>(moves: readonly Move<T>[]): Move<T>[] {
  return [...moves].sort((a, b) => {
    const band = BAND[a.kind] - BAND[b.kind]
    if (band !== 0) return band
    if (BAND[a.kind] === 1) {
      if (a.perHour !== null && b.perHour === null) return -1
      if (a.perHour === null && b.perHour !== null) return 1
      if (a.perHour !== null && b.perHour !== null && a.perHour !== b.perHour) return b.perHour - a.perHour
    }
    const gain = (b.gain ?? 0) - (a.gain ?? 0)
    if (gain !== 0) return gain
    return a.id < b.id ? -1 : a.id > b.id ? 1 : 0
  })
}
