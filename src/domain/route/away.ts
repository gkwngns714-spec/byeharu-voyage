// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHILE YOU WERE AWAY — what her routes and her purse did between the last time this device saw the game and now.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// §7B (docs/NO_SPAGHETTI.md), answered before the first line (2026-11-16, the content plan's slice B):
//   CONCEPT       "the difference between two readings the client already has": the routes book's ALL-TIME counters
//                 (`earnings.total.laps` / `.net`, 0278, the same figures the route's page prints and History's lap
//                 lines add up to) and the purse (`ducats`, the ledger's balance), kept once as a MARK when she was
//                 last here and read again now. Laps closed = counter now − counter then; their net likewise.
//   LIVES HERE    src/domain/route, pure: no React, no store, no storage. The card (src/app/AwayCard.tsx) keeps the
//                 mark and draws the report.
//   WHY COUNTERS  the book serves only the last ten laps, and a game day on production is five minutes: an evening
//                 away closes more than ten. The all-time counters never reset, so the difference is exact however
//                 many closed. A route the mark does not know (made on another device) counts all its laps.
//   WRONG SHAPE   a figure made here that is not a difference of two served figures; a lap counted by its time
//                 (the device clock and the server's are not one clock).

import type { StandingRoute, StandingRouteBook } from '../../lib/rpc'

/** Away means the game was not seen on this device for at least this long (the content plan: "ten minutes or more"). */
export const AWAY_MS = 10 * 60_000

/** What this device saw when it last had the game open: when, the purse, and each route's all-time counters. */
export interface SeenMark {
  at: number
  ducats: number | null
  routes: Record<string, { laps: number; net: number }>
}

export interface AwayRoute {
  id: string
  name: string
  /** Port CODES in order (for `routeTitle`). */
  stops: string[]
  /** Laps closed since the mark. */
  laps: number
  /** The net of those laps, as the server summed them. */
  net: number
  /** The route needs her: stopped, blocked, or paused by the game (not by her). */
  stuck: boolean
  route: StandingRoute
}

export interface AwayReport {
  /** When she was last here (the mark's time, this device's clock). */
  since: number
  routes: AwayRoute[]
  /** The purse now less the purse then; null when either is unknown or it did not move. */
  money: number | null
}

/** The mark to keep now. */
export function seenMark(at: number, ducats: number | null, book: StandingRouteBook | null): SeenMark {
  const routes: SeenMark['routes'] = {}
  for (const r of book?.routes ?? []) routes[r.id] = { laps: r.earnings?.total.laps ?? 0, net: r.earnings?.total.net ?? 0 }
  return { at, ducats, routes }
}

/** A kept mark read back; null for nothing kept, or for anything that is not a mark. */
export function parseSeenMark(raw: string | null): SeenMark | null {
  if (!raw) return null
  try {
    const j = JSON.parse(raw) as Partial<SeenMark> | null
    if (!j || typeof j.at !== 'number' || !Number.isFinite(j.at) || typeof j.routes !== 'object' || j.routes === null) return null
    return { at: j.at, ducats: typeof j.ducats === 'number' ? j.ducats : null, routes: j.routes as SeenMark['routes'] }
  } catch {
    return null
  }
}

/** A route that needs her: the server's own state words, `stopped` and `blocked`, or a pause she did not make. */
export function routeStuck(route: StandingRoute): boolean {
  return route.state === 'stopped' || route.state === 'blocked' || (route.state === 'paused' && route.paused_reason !== 'player')
}

/**
 * What happened since `then`, or null when nothing did (no lap closed, no route needs her, the purse did not move) —
 * so a player with nothing to report never sees the card. Not away (`now - then.at < AWAY_MS`) is null too.
 */
export function awayReport(then: SeenMark, now: number, ducats: number | null, book: StandingRouteBook | null): AwayReport | null {
  if (now - then.at < AWAY_MS) return null
  const routes: AwayRoute[] = []
  for (const r of book?.routes ?? []) {
    const was = then.routes[r.id] ?? { laps: 0, net: 0 }
    const total = r.earnings?.total ?? { laps: 0, net: 0 }
    const laps = Math.max(0, total.laps - was.laps)
    const stuck = routeStuck(r)
    if (laps === 0 && !stuck) continue
    routes.push({ id: r.id, name: r.name, stops: r.stops.map((s) => s.port), laps, net: laps > 0 ? total.net - was.net : 0, stuck, route: r })
  }
  const money = ducats !== null && then.ducats !== null && ducats !== then.ducats ? ducats - then.ducats : null
  if (routes.length === 0 && money === null) return null
  return { since: then.at, routes, money }
}
