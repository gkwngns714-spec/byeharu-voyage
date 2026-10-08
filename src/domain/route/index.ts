// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE STANDING ROUTE, READ — the words a served route is printed in, for every screen that shows one.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// §7B (docs/NO_SPAGHETTI.md), answered before the first line:
//   CONCEPT       "how a served standing route (migration 0092) is said to a player": its one-word
//                 state, the sentence a pause is explained with, and one stop as its sell and buy
//                 lines (owner, 2026-09-30: "sell all buy all is ... in one line and not
//                 distinguished" — each line is said by domain/order's `tradeLineWords`).
//   LIVES HERE    src/domain/route — pure, no React, no store. It READS `world.standing_routes()`'s
//                 served shape and computes no figure: the lap net, the next-lap time and every
//                 price are the server's, formatted by src/lib/format.
//   SECOND CALLER born with two: COMMAND's RouteFold (the route itself) and FLEETS' row caption
//                 (`On route` / `Stopped` / `Paused`). A screen may not import another screen
//                 (tests/sections.spec.ts), so the words live here and both compose them. The MAP's
//                 route line (slice 3) is the third.
//   WRONG SHAPE   a derived figure (a profit, a count of units that "fit"), or a state the server
//                 did not serve — `stopped` IS a failed order in her queue, and only the server says so.
// Words obey docs/WORDS.md: Route, Lap, Paused / Resume, Stopped, Blocked, Next lap 14:32.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { formatClock } from '../../lib/format'
import { tradeLineWords, type TradeLineWords } from '../order'
import type {
  SnapshotGood,
  SnapshotPort,
  StandingRoute,
  StandingRouteBook,
  StandingRouteLine,
  StandingRoutePausedReason,
  StandingRouteStop,
} from '../../lib/rpc'

/** The route this fleet runs, if any. */
export function routeOfFleet(book: StandingRouteBook | null, fleetId: string): StandingRoute | null {
  return book?.routes.find((r) => r.fleet?.id === fleetId) ?? null
}

/** The company's routes that no fleet runs (a Start that was refused, or a route taken off its
 *  fleet). Listed so that none is ever hidden: each still counts toward the served `max`. */
export function routesWithoutFleet(book: StandingRouteBook | null): StandingRoute[] {
  return book?.routes.filter((r) => r.fleet === null) ?? []
}

/** The FLEETS caption word, or null when there is nothing to say (no route, or routes are off). */
export function routeCaption(route: StandingRoute | null): string | null {
  if (!route) return null
  switch (route.state) {
    case 'sailing':
    case 'in_port':
    case 'waiting':
      return 'On route'
    case 'stopped':
      return 'Stopped'
    case 'blocked':
      return 'Blocked'
    case 'paused':
      return 'Paused'
    default:
      return null
  }
}

/** The one word under the folded route row: what it is doing now. */
export function routeStateWord(route: StandingRoute, portByCode: Record<string, SnapshotPort>): string {
  switch (route.state) {
    case 'paused':
      return 'Paused'
    case 'stopped':
      return 'Stopped'
    case 'blocked':
      return 'Blocked'
    case 'waiting':
      return route.next_lap_at ? `Next lap ${formatClock(Date.parse(route.next_lap_at))}` : 'Next lap soon'
    case 'sailing':
      return route.heading_to ? `Sailing to ${portByCode[route.heading_to]?.name ?? route.heading_to}` : 'Sailing'
    case 'in_port':
      return 'In port'
    case 'unassigned':
      return 'No fleet'
    default:
      return 'Routes are not open yet'
  }
}

/** Why a paused route is paused, as a clause. The reason is the server's; the words are here, and
 *  they carry no figure (docs/WORDS.md law 2: a bare number is never printed). */
export function routePauseReason(reason: string | null): string {
  switch (reason) {
    case 'player':
      return 'you paused it'
    case 'reserve':
      return 'your company has less than it keeps back'
    case 'losing':
      return 'the last laps lost money'
    case 'off_route':
      return 'the fleet is not at a stop of this route'
    case 'edited':
      return 'the fleet is not at a stop of the changed route'
    case 'error':
      return 'this route could not run. Change it and resume'
    case 'dark':
      return 'the merchants keep to port'
    case 'laid_up':
      return 'it is laid up'
    default:
      return 'it was paused'
  }
}

/** Why a paused route is paused, in one sentence (the fold's note). */
export function routePausedSentence(reason: StandingRoutePausedReason | null): string {
  return reason === 'player' ? 'You paused this route.' : `Paused: ${routePauseReason(reason)}.`
}

/**
 * The History line of a ROUTE_PAUSED event (0092, worded by 0093's review). For `error` the
 * server's own sentence says what broke — the refusal it caught; every other reason is worded here
 * from the reason alone, so no port code and no bare figure from the payload's prose reaches the
 * player (docs/WORDS.md law 2).
 */
export function routePausedEventWords(route: string, reason: string | null, sentence: string | null): string {
  if (reason === 'error' && sentence) return `${route} paused. ${sentence}`
  return `${route} paused: ${routePauseReason(reason)}.`
}

/** The ports of a route in order, joined by the loop mark: `Lisbon ⇄ Funchal`. */
export function routePorts(route: StandingRoute, portByCode: Record<string, SnapshotPort>): string {
  return route.stops.map((s) => portByCode[s.port]?.name ?? s.port).join(' ⇄ ')
}

/** One trade line of a stop, ready to draw: the good (null for everything on board) and its words. */
export type StopLine = {
  key: string
  /** Good CODE, or null for "everything on board". */
  code: string | null
  /** The good's category (its fallback mark), or null. */
  category: string | null
  name: string
} & TradeLineWords

/** One served (or drafted) trade line as a StopLine. The route editor draws the lines it carries
 *  but has no control for through this too, so nothing a route does is hidden (0093 NIT 11). */
export function stopLine(
  l: Pick<StandingRouteLine, 'ord' | 'kind' | 'good' | 'qty' | 'price_limit' | 'at_profit'>,
  goodByCode: Record<string, SnapshotGood>,
): StopLine {
  const good = l.good ? goodByCode[l.good] : undefined
  return {
    key: `${l.kind}-${l.ord}`,
    code: l.good,
    category: good?.category ?? null,
    name: l.good ? (good?.name ?? l.good) : 'Everything on board',
    ...tradeLineWords(l),
  }
}

/**
 * One stop as the player reads it: what it SELLS, what it BUYS, and the quiet line under both. The
 * server runs a stop in this order — sell, resupply, repair, buy (0092 `cmd.standing_route_lines`)
 * — and the face draws sell above buy for the same reason. Resupply is fleet-wide and runs at every
 * stop when the fleet is below its keep level (a route cannot start without one, E_NO_KEEP), so the
 * quiet line says so at every stop; Repair only where the stop asks for it.
 */
export function routeStopLines(
  stop: StandingRouteStop,
  goodByCode: Record<string, SnapshotGood>,
): { sell: StopLine[]; buy: StopLine[]; quiet: string } {
  const line = (l: StandingRouteLine) => stopLine(l, goodByCode)
  return {
    sell: stop.lines.filter((l) => l.kind === 'SELL').map(line),
    buy: stop.lines.filter((l) => l.kind === 'BUY').map(line),
    quiet: routeStopQuiet(stop.repair),
  }
}

/** The quiet line under a stop's trade: resupply (every stop, when below the keep level) and repair
 *  (where the stop asks for it). One author, so the running face and the editor say it alike. */
export function routeStopQuiet(repair: boolean): string {
  return repair ? 'Resupply if low · Repair' : 'Resupply if low'
}

/**
 * A STEPPED-OVER LINE OF A MERCHANT'S LAST LAP, in words (0099, docs/NPC_TRADERS.md §8.3: *"quicksilver
 * too dear at Lisbon"*). The served skip carries the line's text, its verb and its refusal code;
 * the good is the line's second word. Names are the caller's (goods and ports by code).
 */
export function skippedWords(
  skip: { port?: string; line: string; verb?: string; code: string },
  goodName: (code: string) => string,
  portName: (code: string) => string,
): string {
  const verb = (skip.verb ?? skip.line.split(/\s+/)[0] ?? '').toUpperCase()
  const word = skip.line.split(/\s+/)[1] ?? ''
  const good = word && word.toUpperCase() !== 'ALL' ? goodName(word) : 'the cargo'
  const at = skip.port ? ` at ${portName(skip.port)}` : ''
  switch (skip.code) {
    case 'E_PRICE_LIMIT':
      return verb === 'BUY' ? `${good} too dear${at}` : `${good} would not sell above cost${at}`
    case 'E_DAILY_CAP':
      return `no more ${good} today${at}`
    case 'E_QUEUE_FULL':
      return `${good} kept on board${at}`
    case 'E_NOT_ENOUGH_STOCK':
    case 'E_OUT_OF_STOCK':
      return `no ${good} to be had${at}`
    default:
      return `${verb === 'BUY' ? 'a purchase' : 'a sale'} of ${good} passed over${at}`
  }
}
