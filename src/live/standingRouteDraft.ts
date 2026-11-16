// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE ROUTE DRAFT — what the player has set in the route editor, turned into what the server takes.
// Pure: no React, no store, no figures.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// §7B — the four questions (docs/NO_SPAGHETTI.md):
//   CONCEPT       "the editor's draft of a standing route, and its one translation into the
//                 `p_stops` payload of cmd.standing_route_save" (migration 0092).
//   LIVES HERE    src/live, beside RouteEditor: the editor has two doors since row 209's Repeat (COMMAND's
//                 RouteFold and the MAP's route builder), and a screen never imports another screen
//                 (tests/sections.spec.ts). Nothing here is a rule of the game (the server owns every
//                 rule: the grammar, the caps, the prices).
//   SECOND CALLER the MAP's route line (slice 3) reads the SERVED route (`world.standing_routes`),
//                 never this draft — a draft is what is being typed, the served route is what runs.
//   WRONG SHAPE   a figure computed here (a lap's profit, a price, "how many fit") — every figure is
//                 served; or a course computed any way but through `proposeCourse` between the two
//                 ROADSTEADS `sailTarget` reads, which is how a typed SAIL proposes its course too.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { proposeCourse, sailTarget } from '../domain/passage'
import { portsLine } from '../domain/route'
import type { SeaNav } from '../lib/sea'
import { str } from '../lib/json'
import type { LedgerEvent, SnapshotGood, SnapshotPort, StandingRoute, StandingRouteLine, StandingRouteStopDraft } from '../lib/rpc'

/** One stop as the editor holds it. Slice 1 SHOWS: sell everything or not, and at most one BUY. */
export interface RouteStopDraft {
  /** Port CODE. */
  port: string
  sellAll: boolean
  /** Good CODE to buy here, or null. */
  buyGood: string | null
  /** Units to buy; null = as many as fit (the server's ALL). */
  buyUnits: number | null
  /** The most to pay per unit; null = no cap. */
  buyMax: number | null
  /**
   * WHAT THE EDITOR DOES NOT SHOW, CARRIED THROUGH UNTOUCHED (0093 review, NIT 11): a route saved
   * with more than slice 1's editor can say — a named SELL, "only above cost", a second BUY, REPAIR,
   * a floor on "sell everything" — keeps it when the stop is edited, instead of losing it silently.
   */
  repair: boolean
  /** 0096: hire back to strength before sailing on — carried through untouched, as `repair` is. */
  crewUp: boolean
  sellAllFloor: { price_limit: number | null; at_profit: boolean }
  kept: StandingRouteLine[]
}

/** A fresh stop: sell everything that is on board, buy nothing. */
export function emptyStop(port: string): RouteStopDraft {
  return {
    port,
    sellAll: true,
    buyGood: null,
    buyUnits: null,
    buyMax: null,
    repair: false,
    crewUp: false,
    sellAllFloor: { price_limit: null, at_profit: false },
    kept: [],
  }
}

/** THE SEED (owner row 209, docs/ROUTE_BUILDER.md B4): the stops kept on the map's route builder, as a fresh draft —
 *  each sells what is on board and buys nothing until the player says so in the editor. */
export function seedRoute(ports: readonly string[]): RouteStopDraft[] {
  return ports.map(emptyStop)
}

/**
 * THE TRIP JUST SAILED, AS A ROUTE (2026-11-16, the content plan's slice B: "Repeat as a route" on the arrival card).
 * She came in at `here` from `there` and sold. The route is the two harbours, `here` first (a route starts only from one
 * of its own stops with her in port, cmd.standing_route_assign), each selling everything on board, and buying what she
 * herself bought at that harbour and sold at the other one: the goods in her own BOUGHT and SOLD events (the ledger,
 * which History prints), matched by the fleet's name and the ports' codes those events carry. A good is bought "as many
 * as fit" with no cap, the editor's own default. Null when the trip carried nothing she bought at `there` (a cargo from
 * somewhere else is not a trip to repeat). A good whose name is not exactly one good's is left out (the events carry
 * the served names, the route a code). Pure: it reads the facts handed in and decides nothing the server decides.
 */
export function tripRoute(
  trip: { fleet: string; here: string; there: string },
  events: readonly LedgerEvent[],
  servedGoods: readonly SnapshotGood[],
): RouteStopDraft[] | null {
  if (trip.here === trip.there) return null
  const codeOf = goodCodesByName(servedGoods)
  const goods = (kind: 'BOUGHT' | 'SOLD', port: string): Set<string> => {
    const out = new Set<string>()
    for (const e of events) {
      if (e.kind !== kind || str(e.payload, 'fleet') !== trip.fleet || str(e.payload, 'port') !== port) continue
      const name = str(e.payload, 'good')
      const code = name === null ? undefined : codeOf.get(name)
      if (code !== undefined) out.add(code)
    }
    return out
  }
  const carried = (from: string, to: string): string[] => {
    const sold = goods('SOLD', to)
    return [...goods('BOUGHT', from)].filter((c) => sold.has(c)).sort()
  }
  const out = carried(trip.there, trip.here)
  const back = carried(trip.here, trip.there)
  if (out.length === 0) return null
  return [buying(trip.here, back), buying(trip.there, out)]
}

/** A stop that sells everything and buys these goods, as many as fit and with no cap: the first in the editor's one BUY,
 *  the rest carried as further BUY lines (which the editor shows read-only, 0093 NIT 11). */
function buying(port: string, codes: readonly string[]): RouteStopDraft {
  const [first = null, ...rest] = codes
  return {
    ...emptyStop(port),
    buyGood: first,
    kept: rest.map((good, i) => ({ ord: i + 1, kind: 'BUY', good, qty: null, price_limit: null, at_profit: false })),
  }
}

/** A good's SERVED name → its code, for the names that belong to exactly one good. The goods must be the served ones
 *  (worldStore `servedGoods`): the store's `goodByCode` carries names in the viewer's language, and a ledger event the
 *  server's. */
function goodCodesByName(servedGoods: readonly SnapshotGood[]): Map<string, string> {
  const map = new Map<string, string>()
  const twice = new Set<string>()
  for (const g of servedGoods) {
    if (map.has(g.name)) twice.add(g.name)
    map.set(g.name, g.code)
  }
  for (const n of twice) map.delete(n)
  return map
}

/** The editor's draft of a served route — for Edit. Reads the saved lines back, and keeps every
 *  line the editor has no control for. */
export function draftOfRoute(route: StandingRoute): RouteStopDraft[] {
  return route.stops.map((s) => {
    const buy = s.lines.find((l) => l.kind === 'BUY') ?? null
    const sellAll = s.lines.find((l) => l.kind === 'SELL' && l.good === null) ?? null
    return {
      port: s.port,
      sellAll: sellAll !== null,
      buyGood: buy?.good ?? null,
      buyUnits: buy?.qty ?? null,
      buyMax: buy?.price_limit ?? null,
      repair: s.repair,
      crewUp: s.crew_up ?? false,
      sellAllFloor: { price_limit: sellAll?.price_limit ?? null, at_profit: sellAll?.at_profit ?? false },
      kept: s.lines.filter((l) => l !== buy && l !== sellAll),
    }
  })
}

/** The name the SERVER keeps for the route: its ports in order, joined by the loop mark, and no more than the 24 characters the
 *  server allows (0092, `standing_routes_name_length`). It is a stored key, NOT what the player reads: a longer line of ports is
 *  kept as its first 24 characters, and every place that names a route prints the whole line through `routeTitle`
 *  (domain/route), so nothing on the glass is cut and nothing here pretends with an ellipsis. */
export function routeName(stops: readonly RouteStopDraft[], portByCode: Record<string, SnapshotPort>): string {
  const name = portsLine(stops.map((s) => s.port), portByCode)
  return name.length <= 24 ? name : name.slice(0, 24).trimEnd()
}

export type RoutePayload =
  | { ok: true; stops: StandingRouteStopDraft[] }
  /** A leg with no sailable water between its two roadsteads, by the FROM port's code. */
  | { ok: false; noCourseFrom: string }

/**
 * THE ONE TRANSLATION into `p_stops`. Each stop carries the course of the leg that LEAVES it,
 * proposed by the one course author between the two roadsteads — the server re-verifies it at
 * every departure, so a proposal makes nothing legal, only findable.
 */
export function routePayload(
  stops: readonly RouteStopDraft[],
  nav: SeaNav,
  portByCode: Record<string, SnapshotPort>,
): RoutePayload {
  const out: StandingRouteStopDraft[] = []
  for (let i = 0; i < stops.length; i += 1) {
    const here = stops[i]
    const next = stops[(i + 1) % stops.length]
    const from = sailTarget({ dest: here.port }, portByCode)
    const to = sailTarget({ dest: next.port }, portByCode)
    const course = from && to ? proposeCourse(nav, from, to) : null
    if (!course) return { ok: false, noCourseFrom: here.port }
    const carried = (kind: 'SELL' | 'BUY'): StandingRouteStopDraft['lines'] =>
      here.kept
        .filter((l) => l.kind === kind)
        .map((l) => ({ kind: l.kind, good: l.good, qty: l.qty, price_limit: l.price_limit, at_profit: l.at_profit }))
    const lines: StandingRouteStopDraft['lines'] = [...carried('SELL')]
    if (here.sellAll) {
      lines.push({ kind: 'SELL', price_limit: here.sellAllFloor.price_limit, at_profit: here.sellAllFloor.at_profit })
    }
    if (here.buyGood) {
      lines.push({ kind: 'BUY', good: here.buyGood, qty: here.buyUnits, price_limit: here.buyMax })
    }
    lines.push(...carried('BUY'))
    out.push({ port: here.port, course, repair: here.repair, crew_up: here.crewUp, lines })
  }
  return { ok: true, stops: out }
}
