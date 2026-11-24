import { useMemo } from 'react'
import { whereabouts } from '../../../domain/fleet'
import type { Move } from '../../../domain/hq'
import { routeOfFleet } from '../../../domain/route'
import type { FleetView, HqBoardView, HqMove } from '../../../lib/rpc'
import { useLevelGate } from '../../../live/levelGate'
import { useHqBoard } from '../../../live/useHqBoard'
import { useRoleEdits } from '../../../live/useShipRoles'
import { useWorld } from '../../../live/worldStore'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE BOARD'S READ (docs/design/hq-corp-2026-11-24.md, H2): ONE READ, world.hq_board() (0480, live/useHqBoard.ts). It serves every
// move ranked and the rate (her ledger's last 24 hours over 24); the board draws them as served. Her fleets are the store's own
// (world.fleets and world.standing_routes, on the beat).
//
// NOTHING IS WORKED OUT HERE. The client's own board (v1: the desk's best sales priced and ranked here, and today's Report divided
// by the hours since midnight for a rate) is deleted: a second ranking and a second rate beside the server's. While the switch
// (hq_board_enabled, the owner's) is dark, the board says so in one line and draws no card and no rate.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

export type FleetJob = 'route' | 'trip' | 'idle' | 'stuck' | 'busy'

export interface BoardFleet {
  fleet: FleetView
  job: FleetJob
  /** Docked port code, or null. */
  port: string | null
  /** The route's last 24 hours, when she runs one. */
  day: number | null
  route: ReturnType<typeof routeOfFleet>
}

/** What a card carries to draw and press it: a move the server ranked; its press is its own `act` (servedPress.ts, 0480). */
export type MoveData = { kind: 'served'; move: HqMove; fleet: FleetView | null }

export interface Board {
  fleets: BoardFleet[]
  /** The served moves, in the server's order; none while the board is dark or unread. */
  moves: Move<MoveData>[]
  /** Net coin per hour: `hq_board.rate.per_hour` as served (her ledger's last 24 hours over 24). Null until served; never worked out here. */
  perHour: number | null
  /** `served`: world.hq_board answered for her company. `off`: the server said the board is dark. Null: unread, refused, or no company. */
  source: 'served' | 'off' | null
}

/** A fleet's job, from what is served: a route that is working, a trip under way, or nothing (idle). One reading of where she is
 *  (domain/fleet's `whereabouts`); her laid-up and wrecked states stay the server's (`fleet_state_of`), read here as `stuck`. */
function jobOf(f: FleetView, route: BoardFleet['route']): FleetJob {
  if (route && (route.state === 'sailing' || route.state === 'in_port' || route.state === 'waiting')) return 'route'
  const w = whereabouts(f)
  if (f.status === 'UNABLE_TO_SAIL' || f.status === 'ADRIFT' || f.status === 'IN_BATTLE') return 'stuck'
  if (w.kind === 'sailing') return 'trip'
  if (f.queue.length > 0) return 'busy'
  return w.kind === 'docked' ? 'idle' : 'busy'
}

export function useBoard(): Board {
  const all = useWorld((s) => s.fleets)
  const book = useWorld((s) => s.routes)
  const gate = useLevelGate()
  const company = useWorld((s) => s.player?.id ?? null)

  // THE SERVED BOARD. Her docked fleets' versions are its question (a fleet at sea moves nothing the board prices until she lies in
  // port): one of them acting asks it again; the market's edge is useHqBoard's own.
  // 0485: a hull's role set here moves no fleet's version, so its press count is part of the question (the role card leaves, the yard's
  // next role moves)
  // 2026-11-24 (owner: *"if i hire a captain by pressing a tab, that tab should then disappear"*): a hire seats her and moves no fleet's
  // version either, so the captains she keeps (the roster the hire re-reads, worldStore.hireOfficer) are part of the question too: the
  // crew card leaves at once
  const roleEdits = useRoleEdits((s) => s.edits)
  const kept = useWorld((s) => (s.officers ? s.officers.officers.filter((o) => o.hired).length : -1))
  const hq = useHqBoard(company, `${all.map((f) => (f.status === 'DOCKED' ? `${f.id}.${f.version}` : f.id)).join(',')}:${roleEdits}:${kept}`)
  const lit = litBoard(hq.view)

  const fleets = useMemo<BoardFleet[]>(
    () =>
      all.map((f) => {
        const route = routeOfFleet(book, f.id)
        const w = whereabouts(f)
        return { fleet: f, route, job: jobOf(f, route), port: w.kind === 'docked' ? w.port : null, day: route?.earnings?.day ?? null }
      }),
    [all, book],
  )

  if (!lit) return { fleets, moves: [], perHour: null, source: hq.view && !hq.view.on ? 'off' : null }

  // the server's moves in the server's order (an invest card only where the one level gate opens Invest)
  const byId = new Map(all.map((f) => [f.id, f]))
  const moves: Move<MoveData>[] = lit.moves
    .filter((m) => m.kind !== 'invest' || !gate.shut('invest'))
    .map((m) => ({
      id: m.id,
      kind: m.kind,
      gain: m.kind === 'yard' ? (m.needs.cost ?? null) : m.profit,
      perHour: m.score,
      seconds: m.seconds,
      fleet: m.fleet,
      data: { kind: 'served', move: m, fleet: m.fleet ? (byId.get(m.fleet) ?? null) : null },
    }))
  return { fleets, moves, perHour: lit.rate?.per_hour ?? null, source: 'served' }
}

/** The served board, when it is lit for her company; else null (dark, signed out, a merchant, unread). */
function litBoard(v: HqBoardView | null): Extract<HqBoardView, { company: true }> | null {
  return v && v.on && v.company ? v : null
}
