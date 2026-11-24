// A MOVE ON HQ'S BOARD: the card's shape and its kinds (docs/design/hq-corp-2026-11-24.md, H2).
//
// THE ORDER IS THE SERVER'S. `world.hq_board()` (0480) ranks every move (public.hq_board_for's ORDER BY) and the board draws that
// order as it comes. The client ranking that stood here (v1: `rankMoves`, `perHourOf`, the request's quarter-hour floor) is deleted:
// nothing on the client orders a move or works out a rate.

export type MoveKind = 'trade' | 'request' | 'contract' | 'yard' | 'role' | 'land' | 'crew' | 'invest'

/** The board's filter chips, in their order. */
export const MOVE_KINDS: readonly MoveKind[] = ['trade', 'request', 'contract', 'yard', 'role', 'land', 'crew', 'invest']

export interface Move<T = unknown> {
  id: string
  kind: MoveKind
  /** The headline figure, as served: coin gained (a trade, a request), the price (the yard); null for none. */
  gain: number | null
  /** Coin per hour, the served `score`; null when the server serves none. */
  perHour: number | null
  /** The time it takes, in real seconds; null when not served. */
  seconds: number | null
  /** The fleet it is for, if any. */
  fleet: string | null
  /** What the card needs to draw and press it (the caller's; never read here). */
  data: T
}
