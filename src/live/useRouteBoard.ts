import { useCallback, useEffect, useState } from 'react'
import type { RouteBoard } from '../lib/rpc'
import { useWorld } from './worldStore'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// EVERY LANE THE WORLD SAILS (0106-0110, owner rows 115/117) — asked when ROUTES mounts, and again
// only when the player asks. NEVER on the world's beat.
//
// ── WHY NOT THE BEAT, WITH THE NUMBERS ──────────────────────────────────────────────────────────
// This hook rode `useServedRead` until 2026-10-11, which re-asks on every world read (~3 s) for as
// long as the screen is up. That was written when the world held 76 merchant routes. 0105 founded
// 761 more, and the board measured 218 ms a call at 838 routes — profiled on the real chain:
//
//   public.route_requirement    71.7 ms      public.route_earnings      34.5 ms
//   public.standing_route_state 52.1 ms      public.route_nm            12.8 ms
//   the stops and their regions  7.2 ms
//
// None of those is wasteful; they are the server's own one-readings and there are simply eight
// hundred routes now. Two hundred milliseconds every three seconds, to repaint a board that moves
// when a lap closes somewhere, is the CADENCE being wrong rather than the read being slow. ROUTES
// sits in the Cabin group because "none of them acts on the world" — it is consulted, not played.
//
// ── WHY THE STATE IS IN THE STORE AND NOT IN HERE ───────────────────────────────────────────────
// The first cut kept it local, on the argument that nothing else in the game needs this board. That
// argument did not survive `react-hooks/set-state-in-effect`: a read-once-on-mount that owns React
// state has to call setState from an effect, and the rule is right to refuse it. The store is where
// this codebase already puts exactly this shape — `standings` and `loadStandings` for RANK, the
// other board nobody else reads — so the board lives beside it and this hook is a reader.
//
// What the player gets instead of a beat: `refresh()`, and `readAt` to print beside it, so a board
// a minute old says so. The same bargain RANK strikes with its "settled 4m ago" line.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

export interface RouteBoardRead {
  /** The last answer, or null before the first one lands. */
  board: RouteBoard | null
  /** The first ask is on the wire and nothing has been answered yet. A refresh never sets this, so
   *  it cannot blank a board already on screen. */
  loading: boolean
  /** A refresh is on the wire over a board already shown — dim it, never unmount it. */
  refreshing: boolean
  /** The last read was refused; `board` is the answer from before it. */
  failed: boolean
  /** When the board on screen was answered, in ms. */
  readAt: number | null
  refresh: () => void
}

export function useRouteBoard(): RouteBoardRead {
  // FIELDS, NOT THE STORE (worldStore.ts rule 4).
  const phase = useWorld((s) => s.phase)
  const board = useWorld((s) => s.routeBoard)
  const readAt = useWorld((s) => s.routeBoardAt)
  const failed = useWorld((s) => s.routeBoardFailed)
  const loadRouteBoard = useWorld((s) => s.loadRouteBoard)
  const [asking, setAsking] = useState(false)

  // ONCE, as soon as there is a world to ask about — a store action, so no React state is set from
  // inside this effect. `phase` and `loadRouteBoard` are the only dependencies: a re-render must
  // not re-ask, and nothing on the beat may.
  useEffect(() => {
    if (phase === 'ready') void loadRouteBoard()
  }, [phase, loadRouteBoard])

  const refresh = useCallback(() => {
    setAsking(true)
    // THE PLAYER ASKED — the board is kept for the session (resourceCache), so this press forces.
    void loadRouteBoard(true).finally(() => setAsking(false))
  }, [loadRouteBoard])

  return {
    board,
    loading: board === null && !failed,
    refreshing: asking && board !== null,
    failed,
    readAt,
    refresh,
  }
}
