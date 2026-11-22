import { test, expect } from '@playwright/test'
import { bestRouteAt } from '../src/domain/route'
import type { StandingRoute, StandingRouteBook } from '../src/lib/rpc'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE SECOND HULL EARNS WHILE SHE IS AWAY (2026-11-23, the roadmap's slice 6; play-test 3 finding 26). FIXED FACTS, no browser:
// the route a launched hull is offered to repeat (domain/route `bestRouteAt`). The card itself (src/app/LaunchOffer.tsx) asks
// only doors the game already has; the crew hint and the goal card's "Trading 7 ✓" are read in tests/second.ship.spec.ts.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const route = (id: string, ports: string[], net: number, laps: number): StandingRoute =>
  ({
    id,
    name: ports.join('-'),
    stops: ports.map((port, ord) => ({ ord, port, course: [], repair: false, lines: [] })),
    earnings: { total: { laps, net, sold: 0, bought: 0, supplies: 0, repairs: 0, wages: 0 } },
  }) as unknown as StandingRoute

const book = (routes: StandingRoute[], enabled = true): StandingRouteBook =>
  ({ enabled, max: 5, stop_max: 8, line_max: 8, laps_per_game_day: 1, routes }) as StandingRouteBook

test('bestRouteAt: of the routes that call here, the highest all-time net; none that lost; routes dark is none', () => {
  const near = route('a', ['LIS', 'SET'], 3_100, 4)
  const far = route('b', ['LIS', 'CAD', 'SEV'], 9_800, 2)
  const elsewhere = route('c', ['POR', 'VIG'], 50_000, 9)
  const lost = route('d', ['LIS', 'FUN'], -400, 3)
  expect(bestRouteAt(book([near, far, elsewhere, lost]), 'LIS')?.id).toBe('b')
  expect(bestRouteAt(book([near, far, elsewhere, lost]), 'SET')?.id).toBe('a')
  expect(bestRouteAt(book([lost]), 'LIS'), 'a route that lost money is not offered').toBeNull()
  expect(bestRouteAt(book([elsewhere]), 'LIS'), 'a route that does not call here cannot start here').toBeNull()
  // a route that has closed no lap yet (net 0) is offered when nothing has earned more; between two at 0, the one with more laps
  const fresh = route('e', ['LIS', 'SET'], 0, 0)
  const flat = route('f', ['LIS', 'SET'], 0, 3)
  expect(bestRouteAt(book([fresh]), 'LIS')?.id).toBe('e')
  expect(bestRouteAt(book([fresh, flat]), 'LIS')?.id).toBe('f')
  expect(bestRouteAt(book([near], false), 'LIS'), 'routes dark').toBeNull()
  expect(bestRouteAt(null, 'LIS')).toBeNull()
})
