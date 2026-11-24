import type { Move } from '../../../domain/hq'
import type { BestSale, FleetView, HqBoardView, HqMove, HqRate, TradeRequest } from '../../../lib/rpc'
import { useLevelGate } from '../../../live/levelGate'
import { useHqBoard } from '../../../live/useHqBoard'
import { useRoleEdits } from '../../../live/useShipRoles'
import { useWorld } from '../../../live/worldStore'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE BOARD'S READ (docs/design/hq-corp-2026-11-24.md, H2): ONE READ, world.hq_board() (0480, live/useHqBoard.ts). It serves every
// move ranked and the rate (her ledger's last 24 hours over 24); the board draws them as served. Her fleets are not the board's:
// each is a row of the one worker list (corp/workerRows.ts).
//
// NOTHING IS WORKED OUT HERE. The client's own board (v1: the desk's best sales priced and ranked here, and today's Report divided
// by the hours since midnight for a rate) is deleted: a second ranking and a second rate beside the server's. While the switch
// (hq_board_enabled, the owner's) is dark, the board says so in one line and draws no card and no rate.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** What a card carries to draw and press it. A card is built only from a served move (`served`).
 *  THE OTHER SHAPES ARE BUILT NOWHERE: they were v1's client-made cards. They stay in the type only because useMovePress.ts (H3's
 *  file) still narrows on them; H3 deletes them with its cases. */
export type MoveData =
  | { kind: 'trade'; sale: BestSale; at: string; fleet: FleetView; haunt: boolean }
  | { kind: 'request'; request: TradeRequest; units: number; at: string; fleet: FleetView }
  | { kind: 'yard'; port: string | null; hull: string; price: number }
  | { kind: 'crew'; fleet: FleetView }
  | { kind: 'invest'; idle: number }
  /** 0480: a move the server ranked; its press is its own `act` (servedPress.ts). */
  | { kind: 'served'; move: HqMove; fleet: FleetView | null }

export interface Board {
  /** The served moves, in the server's order; none while the board is dark or unread. */
  moves: Move<MoveData>[]
  /** Net coin per hour: `hq_board.rate.per_hour` as served (her ledger's last 24 hours over 24). Null until served; never worked out here. */
  perHour: number | null
  /** `served`: world.hq_board answered for her company. `off`: the server said the board is dark. Null: unread, refused, or no company. */
  source: 'served' | 'off' | null
  /** 0493: the served rate with its lines (why the figure is what it is); null before it is read. A server before 0493 serves no `lines`. */
  rate: HqRate | null
  /** The figures are the server's (`source === 'served'`), in the word RateWhy.tsx reads. */
  served: boolean
  /** The first answer is still on the wire: nothing is known yet, so a face says neither "off" nor "none" (HqBoard.tsx holds its line). */
  asking: boolean
}

export function useBoard(): Board {
  const all = useWorld((s) => s.fleets)
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

  if (!lit) return { moves: [], perHour: null, source: hq.view && !hq.view.on ? 'off' : null, rate: null, served: false, asking: hq.view === null && hq.loading }

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
  return { moves, perHour: lit.rate?.per_hour ?? null, source: 'served', rate: lit.rate, served: true, asking: false }
}

/** The served board, when it is lit for her company; else null (dark, signed out, a merchant, unread). */
function litBoard(v: HqBoardView | null): Extract<HqBoardView, { company: true }> | null {
  return v && v.on && v.company ? v : null
}
