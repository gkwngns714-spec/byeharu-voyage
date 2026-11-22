// ═══════════════════════════════════════════════════════════════════════════════════════════════
// HER BEST ROUTE FROM A HARBOUR — the route a newly launched hull is offered to repeat (2026-11-23, the roadmap's slice 6,
// docs/design/roadmap-2026-11-23.md; play-test 3 finding 26).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// §7B (docs/NO_SPAGHETTI.md):
//   CONCEPT       "which of her saved routes a new fleet lying at `port` should run": of the routes that call at `port` (a route
//                 starts only on a fleet docked at one of its own stops, cmd.standing_route_assign), the one whose all-time net
//                 (`earnings.total.net`, 0278: the figure the route's page prints) is highest. A route that has lost money overall is
//                 not "best" and is never offered; a route with no closed lap yet (net 0) is, when nothing has earned more.
//   LIVES HERE    src/domain/route, pure: it reads the served book and computes no figure.
//   WRONG SHAPE   a profit estimated here, or a route chosen by a rule the server keeps (the cap, a closed leg): those are judged
//                 at save and assign, and come back as the server's refusal.

import type { StandingRoute, StandingRouteBook } from '../../lib/rpc'

/** Her best route that calls at `port` (a port CODE), or null: routes dark, none calls there, or every one that does has lost. */
export function bestRouteAt(book: StandingRouteBook | null, port: string): StandingRoute | null {
  if (!book?.enabled) return null
  let best: StandingRoute | null = null
  for (const r of book.routes) {
    if (!r.stops.some((s) => s.port === port)) continue
    const net = r.earnings?.total.net ?? 0
    if (net < 0) continue
    const bestNet = best?.earnings?.total.net ?? 0
    if (best === null || net > bestNet || (net === bestNet && (r.earnings?.total.laps ?? 0) > (best.earnings?.total.laps ?? 0))) best = r
  }
  return best
}
