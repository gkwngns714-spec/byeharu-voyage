// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE STANDING ROUTE, READ — the words a served route is printed in, for every screen that shows one.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// §7B (docs/NO_SPAGHETTI.md), answered before the first line:
//   CONCEPT       "how a served standing route (migration 0092) is said to a player": its one-word
//                 state, the sentence a pause is explained with, and one stop in a line.
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

import { formatClock, formatUnitPrice, formatUnits } from '../../lib/format'
import type {
  SnapshotGood,
  SnapshotPort,
  StandingRoute,
  StandingRouteBook,
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

/** One stop in a line: `Sell all · Buy Iron, 20 units, Max 12 🪙 each`. */
export function routeStopWords(stop: StandingRouteStop, goodByCode: Record<string, SnapshotGood>): string {
  const parts: string[] = []
  for (const l of stop.lines) {
    const good = l.good ? (goodByCode[l.good]?.name ?? l.good) : null
    if (l.kind === 'SELL') {
      parts.push(good ? `Sell ${good}` : 'Sell all')
    } else {
      parts.push(
        [`Buy ${good ?? ''}`, l.qty !== null ? formatUnits(l.qty) : null, l.price_limit !== null ? `Max ${formatUnitPrice(l.price_limit)}` : null]
          .filter(Boolean)
          .join(', '),
      )
    }
  }
  if (stop.repair) parts.push('Repair')
  return parts.length > 0 ? parts.join(' · ') : 'Trade nothing'
}
