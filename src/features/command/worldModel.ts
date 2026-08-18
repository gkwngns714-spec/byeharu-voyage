// THE READ MODEL every screen shares — pure, no React, built from a V0World snapshot.
//
// One place assembles the leg graph, the price index, the fleet views and the lookup helpers, so
// no screen builds its own. Rebuilding a 12-node graph per render would be cheap; having two
// slightly different graphs would not be.
//
// Time enters HERE and only here: `nowMs` comes in, the fleet views come out with their progress
// already interpolated (D.2's closed-form position). Nothing downstream reads a clock.

import type {
  Good,
  GoodCode,
  Port,
  PortCode,
  QueuedOrder,
  Ship,
  ShipClass,
  V0World,
} from '../../fixtures/types'
import type { FleetView } from '../fleets/fleetMath'
import { buildFleetView } from '../fleets/fleetMath'
import type { PriceIndex } from '../market/prices'
import { buildPriceIndex } from '../market/prices'
import type { LegGraph } from './geo'
import { buildGraph } from './geo'
import type { ParseContext } from './parse'

export interface WorldModel {
  world: V0World
  nowMs: number
  graph: LegGraph
  priceIndex: PriceIndex
  fleetViews: readonly FleetView[]
  portOf: (code: PortCode) => Port
  goodOf: (code: GoodCode) => Good
  classOf: (ship: Ship) => ShipClass
  fleetView: (id: string) => FleetView | undefined
  ordersFor: (fleetId: string) => readonly QueuedOrder[]
  /** The port the player is standing in — the PORT and MARKET tabs' subject. */
  currentPort: Port
  /** What the parser needs to resolve a name. */
  parseContext: ParseContext
}

/** The static half: everything that does not move when the clock ticks. Built once per snapshot
 *  and reused across ticks so a 1 Hz clock does not rebuild the world sixty times a minute. */
export interface StaticWorld {
  world: V0World
  graph: LegGraph
  priceIndex: PriceIndex
  classByCode: Map<string, ShipClass>
  portByCode: Map<PortCode, Port>
  goodByCode: Map<GoodCode, Good>
}

export function buildStaticWorld(world: V0World): StaticWorld {
  return {
    world,
    graph: buildGraph(world.ports, world.legs),
    priceIndex: buildPriceIndex(world.ports, world.goods, world.portGoods),
    classByCode: new Map(world.shipClasses.map((c) => [c.code, c])),
    portByCode: new Map(world.ports.map((p) => [p.code, p])),
    goodByCode: new Map(world.goods.map((g) => [g.code, g])),
  }
}

export function deriveWorld(statics: StaticWorld, nowMs: number): WorldModel {
  const { world, graph, priceIndex, classByCode, portByCode, goodByCode } = statics

  const classOf = (ship: Ship): ShipClass => {
    const cls = classByCode.get(ship.classCode)
    // The fixture is closed data: a ship whose class is missing is a broken fixture, not a runtime
    // condition to degrade around. Failing loudly here is cheaper than a NaN reaching a price.
    if (!cls) throw new Error(`Unknown ship class: ${ship.classCode}`)
    return cls
  }
  const portOf = (code: PortCode): Port => {
    const port = portByCode.get(code)
    if (!port) throw new Error(`Unknown port: ${code}`)
    return port
  }
  const goodOf = (code: GoodCode): Good => {
    const good = goodByCode.get(code)
    if (!good) throw new Error(`Unknown good: ${code}`)
    return good
  }

  const fleetViews = world.fleets.map((fleet) =>
    buildFleetView(fleet, world.ships, classOf, graph, nowMs),
  )

  return {
    world,
    nowMs,
    graph,
    priceIndex,
    fleetViews,
    portOf,
    goodOf,
    classOf,
    fleetView: (id) => fleetViews.find((v) => v.fleet.id === id),
    ordersFor: (fleetId) =>
      world.orders.filter((o) => o.fleetId === fleetId).sort((a, b) => a.seq - b.seq),
    currentPort: portOf(world.currentPort),
    parseContext: {
      fleets: world.fleets.map((f) => ({ id: f.id, name: f.name })),
      ports: world.ports.map((p) => ({ code: p.code, name: p.name })),
      goods: world.goods.map((g) => ({ code: g.code, name: g.name, english: g.english })),
    },
  }
}
