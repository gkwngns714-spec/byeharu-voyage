import { useMemo } from 'react'
import { useShellState } from '../../../app/shellState'
import { fleetCargoByCode, voyageEtaMs, whereabouts } from '../../../domain/fleet'
import { perHourOf, rankMoves, REQUEST_FLOOR_S, type Move } from '../../../domain/hq'
import { routeOfFleet } from '../../../domain/route'
import { worldReport, type BestSale, type BestSales, type FleetView, type HqBoardView, type HqMove, type Report, type SnapshotPort, type TradeRequest } from '../../../lib/rpc'
import { useLevelGate } from '../../../live/levelGate'
import { useBestSales } from '../../../live/useDesk'
import { useHqBoard } from '../../../live/useHqBoard'
import { usePirateBounties } from '../../../live/usePirateBounties'
import { useRequests } from '../../../live/useRequests'
import { useSecondShipGoal } from '../../../live/useSecondShipGoal'
import { useServedRead } from '../../../live/useServedRead'
import type { ServedRead } from '../../../live/useServedRead'
import { useWorld } from '../../../live/worldStore'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE BOARD'S READS (docs/design/hq-command-2026-11-23.md) — every figure HQ's command board draws, from reads the client already
// asks elsewhere, under THEIR keys (so the board adds no read the desk, the yard or the Report face does not already make):
//   world.fleets and world.standing_routes (the store's, on the beat)  · world.best_sales for each idle fleet's port (the desk's, ≤ 3)
//   world.contracts for the city in hand (HQ's requests)               · the second-ship goal (the goal card's)
//   world.report('day') (the Report face's)                            · world.pirate_bounties (Rank's)
// The ranking is domain/hq's one rule. Nothing here decides what the server decides.
//
// 0480 (v2, hq_board_enabled): LIT, ONE READ — world.hq_board() (live/useHqBoard.ts) serves every move ranked, the rate (her last 24
// hours), what is next and the threats; the board draws them as served, and the reads above stand down: they are asked only once the
// server has said it is dark (or refused), so a lit board never also asks the desk's reads. DARK: v1, as before.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** How many idle fleets the board prices trade runs for (one world.best_sales each, the desk's own read). */
export const PRICED_FLEETS = 3
/** Trade runs a fleet offers the board, the best by coin per hour. */
const RUNS_PER_FLEET = 3
/** Coin above this, beyond the dearest trade card, is idle (decided by default; the server rates it in v2). */
export const IDLE_COIN = 20_000

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

export type MoveData =
  | { kind: 'trade'; sale: BestSale; at: string; fleet: FleetView; haunt: boolean }
  | { kind: 'request'; request: TradeRequest; units: number; at: string; fleet: FleetView }
  | { kind: 'yard'; port: string | null; hull: string; price: number }
  | { kind: 'crew'; fleet: FleetView }
  | { kind: 'invest'; idle: number }
  /** 0480: a move the server ranked; its press is its own `act` (servedPress.ts). */
  | { kind: 'served'; move: HqMove; fleet: FleetView | null }

export interface Clock {
  key: string
  atMs: number
  what: 'arrives' | 'shipReady' | 'training' | 'nextLap'
  name: string
}

export interface Board {
  fleets: BoardFleet[]
  moves: Move<MoveData>[]
  purse: number | null
  /** Today's net per hour (world.report('day') over the hours since 00:00 UTC); lit (0480), her last 24 hours over 24; null until read. */
  perHour: number | null
  /** 0480: the moves, the rate, what is next and the threats are the server's (world.hq_board lit). */
  served: boolean
  next: Clock | null
  /** Pirates near her: bounties in the waters she sails, or her waters' danger at 4 or more. */
  threats: number
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

/** No one in any cabin of her ships (0157 `seats`); unknown (no seats served) is not "none". */
function noCaptain(f: FleetView): boolean {
  const seats = f.ships.flatMap((s) => s.seats?.list ?? [])
  return seats.length > 0 && seats.every((s) => s.captain === null)
}

const secondsOf = (s: BestSale): number | null => s.seconds ?? (s.days !== null ? s.days * 86_400 : null)

export function useBoard(cityPort: SnapshotPort | null): Board {
  const { nowMs } = useShellState()
  const all = useWorld((s) => s.fleets)
  const book = useWorld((s) => s.routes)
  const portByCode = useWorld((s) => s.portByCode)
  const purse = useWorld((s) => s.ducats)
  const skills = useWorld((s) => s.skills)
  const gate = useLevelGate()
  const company = useWorld((s) => s.player?.id ?? null)

  // 0480: THE SERVED BOARD, asked first. Her docked fleets' versions are its question (a fleet at sea moves nothing the board prices
  // until she lies in port): one of them acting asks it again; the market's edge is useHqBoard's own.
  const hq = useHqBoard(company, all.map((f) => (f.status === 'DOCKED' ? `${f.id}.${f.version}` : f.id)).join(','))
  const lit = litBoard(hq.view)
  // v1's reads only once the server has answered dark (or refused), and while it stays dark: never beside a lit board. A re-ask keeps the
  // last answer (useServedRead), so the dark board does not blink when a fleet acts.
  const v1 = company !== null && (hq.view !== null || !hq.loading) && lit === null

  const fleets = useMemo<BoardFleet[]>(
    () =>
      all.map((f) => {
        const route = routeOfFleet(book, f.id)
        const w = whereabouts(f)
        return { fleet: f, route, job: jobOf(f, route), port: w.kind === 'docked' ? w.port : null, day: route?.earnings?.day ?? null }
      }),
    [all, book],
  )

  // THE DESK'S OWN READ, for up to three idle fleets (fixed slots: hooks are never called a varying number of times)
  const idle = fleets.filter((f) => f.job === 'idle' && f.port !== null)
  const slot = (i: number) => idle[i] ?? null
  const read = (b: BoardFleet | null) =>
    v1 ? ([b?.fleet.id ?? null, b?.fleet.version ?? null, b?.port ? (portByCode[b.port]?.id ?? null) : null] as const) : ([null, null, null] as const)
  const s0 = useBestSales(...read(slot(0)))
  const s1 = useBestSales(...read(slot(1)))
  const s2 = useBestSales(...read(slot(2)))
  const sales: (readonly [BoardFleet | null, ServedRead<BestSales>])[] = [
    [slot(0), s0],
    [slot(1), s1],
    [slot(2), s2],
  ]

  const requests = useRequests(v1 ? (cityPort?.id ?? null) : null)
  const goal = useSecondShipGoal(nowMs)
  const bounties = usePirateBounties()
  const report = useServedRead<Report>(v1 ? 'report:day' : null, () => worldReport('day'))

  // THE PIRATES SHE KNOWS OF: a named pirate's home (BountyRow.home) and the seas the bounties name
  const live = bounties?.on ? (bounties.bounties ?? []).filter((b) => !b.laid_up) : []
  const haunts = new Set(live.map((b) => b.home))
  const pirateSeas = new Set(live.flatMap((b) => (b.sea ? [b.sea] : [])))

  const moves: Move<MoveData>[] = []
  for (const [b, r] of sales) {
    if (!b || !b.port || !r.view || r.view.port !== b.port) continue
    const runs = r.view.goods
      .filter((s) => s.port !== null && s.pays && s.profit !== null && s.profit > 0 && s.near !== false)
      .map((s) => ({ s, seconds: secondsOf(s) }))
      .map((x) => ({ ...x, perHour: perHourOf(x.s.profit, x.seconds) }))
      .sort((a, z) => (z.perHour ?? -1) - (a.perHour ?? -1))
      .slice(0, RUNS_PER_FLEET)
    for (const x of runs)
      moves.push({
        id: `trade:${b.fleet.id}:${x.s.good}:${x.s.port}`,
        kind: 'trade',
        gain: x.s.profit,
        perHour: x.perHour,
        seconds: x.seconds,
        fleet: b.fleet.id,
        data: { kind: 'trade', sale: x.s, at: b.port, fleet: b.fleet, haunt: x.s.port !== null && haunts.has(x.s.port) },
      })
  }

  // REQUESTS AT THE CITY IN HAND that a fleet of hers lying there can fill from her hold
  const docked = cityPort ? fleets.filter((f) => f.port === cityPort.code) : []
  for (const rq of requests.view?.contracts ?? []) {
    for (const b of docked) {
      const units = Math.min(fleetCargoByCode(b.fleet)[rq.good] ?? 0, rq.qty)
      if (units < 1 || !cityPort) continue
      const gain = units * rq.premium_per_unit
      moves.push({
        id: `request:${rq.id}:${b.fleet.id}`,
        kind: 'request',
        gain,
        perHour: perHourOf(gain, REQUEST_FLOOR_S),
        seconds: null,
        fleet: b.fleet.id,
        data: { kind: 'request', request: rq, units, at: cityPort.code, fleet: b.fleet },
      })
      break
    }
  }

  if (goal?.saving && goal.saving.have >= goal.saving.price && goal.second.hull)
    moves.push({
      id: 'yard',
      kind: 'yard',
      gain: goal.saving.price,
      perHour: null,
      seconds: null,
      fleet: null,
      data: { kind: 'yard', port: goal.second.port, hull: goal.second.hull, price: goal.saving.price },
    })

  for (const b of fleets)
    if (b.port !== null && noCaptain(b.fleet))
      moves.push({ id: `crew:${b.fleet.id}`, kind: 'crew', gain: null, perHour: null, seconds: null, fleet: b.fleet.id, data: { kind: 'crew', fleet: b.fleet } })

  const dearest = Math.max(0, ...moves.flatMap((m) => (m.data.kind === 'trade' ? [m.data.sale.cost ?? 0] : [])))
  const idleCoin = purse !== null ? purse - dearest : 0
  if (idleCoin >= IDLE_COIN && !gate.shut('invest'))
    moves.push({ id: 'invest', kind: 'invest', gain: idleCoin, perHour: null, seconds: null, fleet: null, data: { kind: 'invest', idle: idleCoin } })

  // WHAT FINISHES NEXT: a voyage's arrival, the ordered ship, the Academy's next level, a route's next lap
  const clocks: Clock[] = []
  for (const b of fleets) {
    const eta = voyageEtaMs(b.fleet)
    if (eta !== null) clocks.push({ key: `eta:${b.fleet.id}`, atMs: eta, what: 'arrives', name: b.fleet.name })
    if (b.route?.state === 'waiting' && b.route.next_lap_at) clocks.push({ key: `lap:${b.fleet.id}`, atMs: Date.parse(b.route.next_lap_at), what: 'nextLap', name: b.fleet.name })
  }
  const order = goal?.second.order
  if (order && !order.ready) clocks.push({ key: 'ship', atMs: Date.parse(order.readyAt), what: 'shipReady', name: order.name })
  const lesson = skills?.queue[0]
  if (lesson) clocks.push({ key: 'skill', atMs: Date.parse(lesson.finishes_at), what: 'training', name: lesson.name })
  const next = clocks.filter((c) => Number.isFinite(c.atMs) && c.atMs > nowMs).sort((a, b) => a.atMs - b.atMs)[0] ?? null

  // PIRATES NEAR HER: a bounty's sea among the waters her voyages cross, or those waters at danger 4 and over
  let threats = 0
  for (const b of fleets)
    for (const w of b.fleet.voyage?.waters ?? []) if (pirateSeas.has(w.sea) || pirateSeas.has(w.name) || w.danger >= 4) threats++

  // TODAY'S RATE: the Report's own day (real UTC, 0317) over the hours since midnight
  const midnight = new Date(nowMs)
  midnight.setUTCHours(0, 0, 0, 0)
  const hours = Math.max(1, (nowMs - midnight.getTime()) / 3_600_000)
  const perHour = report.view ? report.view.total / hours : null

  if (lit) {
    // LIT: the server's moves in the server's order (an invest card only where the one level gate opens Invest), its rate, next, threats
    const byId = new Map(all.map((f) => [f.id, f]))
    const served: Move<MoveData>[] = lit.moves
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
    const n = lit.next
    const what = n ? SERVED_NEXT[n.what] : null
    const servedNext: Clock | null =
      n && what ? { key: `served:${n.what}`, atMs: Date.parse(n.at), what, name: n.what === 'training' ? (lesson?.name ?? '') : (n.name ?? '') } : null
    return { fleets, moves: served, purse, perHour: lit.rate?.per_hour ?? null, next: servedNext, threats: lit.threats, served: true }
  }
  return { fleets, moves: rankMoves(moves), purse, perHour, next, threats, served: false }
}

/** The served board, when it is lit for her company; else null (dark, signed out, a merchant, unread). */
function litBoard(v: HqBoardView | null): Extract<HqBoardView, { company: true }> | null {
  return v && v.on && v.company ? v : null
}

/** The served clock's word, as the bridge names it. */
const SERVED_NEXT: Record<'arrives' | 'ship' | 'training' | 'lap', Clock['what']> = {
  arrives: 'arrives',
  ship: 'shipReady',
  training: 'training',
  lap: 'nextLap',
}
