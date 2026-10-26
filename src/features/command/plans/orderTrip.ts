// THE TRIP AN ORDER BELONGS TO (owner row 217, 2026-10-26: *"when i press my order, i should be able to see the
// route, time, money, profit all on estimate below the map + map"*) — pure: no React, no store, no figure.
//
// The queue serves each order as its line of the grammar (`SAIL LIS`, `BUY coffee 60 AT <= 95`, `SELL coffee
// ALL`); Go writes a trip as SAILs, a BUY, SAILs and a SELL (planLines.ts). Read in order from where she is, the
// live orders fall into TRIPS, each closed by its SELL: the harbours its SAILs call at, in order, and — when it
// trades one good — the plan it is (the good, the buy city, the sell city, the units), so the Trade page can ask
// the SAME served board the trade card asked (world.good_board) for its figures. Nothing is priced here.
//
// A trip with no BUY and no SELL (a raw SAIL) has no plan: its route is drawn, its money is not served.

import { tradeOfTokens } from '../../../domain/order'
import type { FleetView, QueuedOrder } from '../../../lib/rpc'
import type { PlanDraft } from './planDraft'

export interface OrderTrip {
  /** The queued orders' ids, in order. */
  orders: string[]
  /** Where the trip starts: the harbour she is docked at, or null at sea. */
  start: string | null
  /** The harbours its SAILs call at, in order (port CODES). */
  stops: string[]
  /** The trade it makes, as the trade card's plan — null when it trades no one good. */
  plan: PlanDraft | null
}

const LIVE: readonly QueuedOrder['status'][] = ['pending', 'active']

/** A SAIL line's harbour: the word after TO, else the first word that is a harbour's code. */
function sailTo(order: QueuedOrder, fleetName: string, isPort: (code: string) => boolean): string | null {
  const tokens = order.text.trim().split(/\s+/).slice(1).filter((w) => w !== fleetName)
  const to = tokens.findIndex((w) => w.toUpperCase() === 'TO')
  if (to >= 0 && tokens[to + 1] && isPort(tokens[to + 1])) return tokens[to + 1]
  return tokens.find(isPort) ?? null
}

/** The fleet's live orders as trips, each closed by its SELL. */
export function orderTrips(fleet: FleetView, isPort: (code: string) => boolean, isGood: (code: string) => boolean): OrderTrip[] {
  const trips: OrderTrip[] = []
  let here: string | null = fleet.status === 'DOCKED' ? fleet.port : null
  let trip: OrderTrip | null = null
  let buy: { good: string; units: number | null; at: string | null } | null = null
  let sell: { good: string; at: string | null } | null = null
  const close = () => {
    if (!trip) return
    const good = sell?.good ?? buy?.good ?? null
    trip.plan =
      good && isGood(good) && (!buy || !sell || buy.good === sell.good)
        ? { good, buyAt: buy?.at ?? null, sellAt: sell?.at ?? null, units: buy?.units ?? null, max: null, min: null }
        : null
    trips.push(trip)
    trip = null
    buy = null
    sell = null
  }
  for (const order of fleet.queue) {
    if (!LIVE.includes(order.status)) continue
    if (!trip) trip = { orders: [], start: here, stops: [], plan: null }
    trip.orders.push(order.id)
    const verb = order.verb.toUpperCase()
    if (verb === 'SAIL') {
      const to = sailTo(order, fleet.name, isPort)
      if (to) {
        trip.stops.push(to)
        here = to
      }
    } else if (verb === 'BUY' || verb === 'SELL') {
      const tokens = order.text.trim().split(/\s+/).slice(1).filter((w) => w !== fleet.name)
      const trade = tradeOfTokens(verb, tokens)
      if (trade && verb === 'BUY' && !buy) buy = { good: trade.good, units: trade.line.qty, at: here }
      if (verb === 'SELL') {
        if (trade) sell = { good: trade.good, at: here }
        close()
      }
    }
  }
  close()
  return trips
}

/** The trip an order is part of; the voyage under way is the trip of the SAIL she is sailing. */
export function tripOf(trips: readonly OrderTrip[], fleet: FleetView, pick: { kind: 'order'; id: string } | { kind: 'voyage' }): OrderTrip | null {
  const id = pick.kind === 'order' ? pick.id : fleet.queue.find((o) => o.status === 'active' && o.verb.toUpperCase() === 'SAIL')?.id
  if (!id) return null
  return trips.find((t) => t.orders.includes(id)) ?? null
}
