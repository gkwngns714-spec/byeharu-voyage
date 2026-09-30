// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE ROUTE DRAFT — what the player has set in the route editor, turned into what the server takes.
// Pure: no React, no store, no figures.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// §7B — the four questions (docs/NO_SPAGHETTI.md):
//   CONCEPT       "the editor's draft of a standing route, and its one translation into the
//                 `p_stops` payload of cmd.standing_route_save" (migration 0092).
//   LIVES HERE    features/command, beside RouteFold, because COMMAND is the one tab that changes
//                 the world (DESIGN §E.1) and the route is a standing ORDER; nothing here is a rule
//                 of the game (the server owns every rule: the grammar, the caps, the prices).
//   SECOND CALLER the MAP's route line (slice 3) reads the SERVED route (`world.standing_routes`),
//                 never this draft — a draft is what is being typed, the served route is what runs.
//   WRONG SHAPE   a figure computed here (a lap's profit, a price, "how many fit") — every figure is
//                 served; or a course computed any way but through `proposeCourse` between the two
//                 ROADSTEADS `sailTarget` reads, which is how a typed SAIL proposes its course too.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { proposeCourse, sailTarget } from '../../domain/passage'
import type { SeaNav } from '../../lib/sea'
import type { SnapshotPort, StandingRoute, StandingRouteLine, StandingRouteStopDraft } from '../../lib/rpc'

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
    sellAllFloor: { price_limit: null, at_profit: false },
    kept: [],
  }
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
      sellAllFloor: { price_limit: sellAll?.price_limit ?? null, at_profit: sellAll?.at_profit ?? false },
      kept: s.lines.filter((l) => l !== buy && l !== sellAll),
    }
  })
}

/** The route's name: its ports in order, joined by the loop mark, cut to the server's 24. */
export function routeName(stops: readonly RouteStopDraft[], portByCode: Record<string, SnapshotPort>): string {
  const name = stops.map((s) => portByCode[s.port]?.name ?? s.port).join(' ⇄ ')
  return name.length <= 24 ? name : `${name.slice(0, 23)}…`
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
    out.push({ port: here.port, course, repair: here.repair, lines })
  }
  return { ok: true, stops: out }
}
