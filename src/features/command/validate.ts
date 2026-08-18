// STATIC CHECK — DESIGN.md F.5 layer 2, pure, no React, no clock beyond the one in the model.
//
// F.5: "Validation runs in three layers, and the first two are advisory only — THE SERVER'S IS THE
// AUTHORITY." This file is layer 2. It exists so the line under the CMD input can answer while the
// player is still typing, and it is written to MIRROR THE SERVER'S REJECT ORDER (CORE_REUSE 2.2
// rule 1): the checks below run in the sequence F.2 lists each verb's failures, so the live line
// and the eventual real refusal never disagree about WHICH thing is wrong.
//
// Every failure is "a code, a sentence, and a fix" (F.5). Never a bare code. Never a sentence
// without at least one thing the player can tap to make it right.
//
// WHAT THIS LAYER CANNOT SEE, and therefore never claims: the true stock at the moment of
// execution, another player's purchase two seconds ago, the negotiation roll (G.5). A green check
// line is a "nothing is obviously wrong", not a promise.
//
// V0 CODES NOT RAISED HERE, and why (each is real, and each arrives with the system that owns it):
//   E_PORT_CLOSED   — ice closure is a V1 season effect; no port in V0 can close.
//   E_LANGUAGE      — language levels arrive with V1's wider world.
//   E_STALE         — a version mismatch is a server fact; there is no second device yet.
//   everything from E_MIN_INVEST down to E_NO_ACADEMY — investment, shipbuilding, exploration and
//   officers are all "Not in V0" (K.1), so their verbs are refused wholesale with E_RANK_LOCKED.

import type { GoodCode, Port, PortCode } from '../../fixtures/types'
import {
  formatDucats,
  formatInt,
  formatNm,
  formatRealDuration,
  formatTuns,
  formatVoyageDays,
  voyageDaysToRealMs,
} from '../../lib/format'
import type { FleetView } from '../fleets/fleetMath'
import {
  ENDURANCE_SAFETY_MARGIN,
  FOOD_PER_CREW_DAY,
  WATER_PER_CREW_DAY,
  cargoTuns,
  voyageDaysFor,
} from '../fleets/fleetMath'
import {
  DAILY_CAP_FRACTION,
  askPrice,
  bidPrice,
  isAvailable,
  midPrice,
  rowKey,
  steppedBuyCost,
  steppedSellRevenue,
} from '../market/prices'
import type { ErrorCode, Fix } from './errors'
import { resolveRoute } from './geo'
import type { ParsedOrder, Qty } from './grammar'
import { parseOrder } from './parse'
import type { WorldModel } from './worldModel'

/** F.3 — one FIFO queue per fleet, maximum twelve orders. */
export const MAX_QUEUE = 12

/** F.2 PROVISION — FULL fills stores to the ship's store_ratio, default 45% of hold. */
export const DEFAULT_STORE_RATIO = 0.45

/** F.2 DOCK — port fee, 50 ducats per ship. */
export const PORT_FEE_PER_SHIP = 50

/** F.2 HIRE — beyond the port's pool the rate is x2.5 ("urgent recruitment"). */
export const URGENT_CREW_MULTIPLIER = 2.5

export interface CheckOk {
  ok: true
  order: ParsedOrder
  /** The headline of the check block: "parsed · Gaivota (1 ship) · 1 leg · 188 nm". */
  summary: string
  /** The lines beneath it. Each is one fact, already formatted. */
  details: readonly string[]
  /** Things that are legal but should be seen — an urgent-crew premium, a queued execution. */
  warnings: readonly string[]
}

export interface CheckErr {
  ok: false
  code: ErrorCode
  /** The SPECIFIC sentence, with this fleet's real numbers in it. */
  sentence: string
  /** F.5's insertable fixes. At least one, always. */
  fixes: readonly Fix[]
  /** Present when the line parsed but failed a precondition. */
  order?: ParsedOrder
  details?: readonly string[]
}

export type CheckResult = CheckOk | CheckErr

function err(code: ErrorCode, sentence: string, fixes: readonly Fix[], order?: ParsedOrder, details?: readonly string[]): CheckErr {
  return { ok: false, code, sentence, fixes, order, details }
}

/** Where a BUY or SELL will actually happen: the port the fleet is lying in, or — for a fleet at
 *  sea — the port it is bound for, because F.2 says the order is "queued and executed on arrival".
 *  That is the whole point of the queue: "sell the cloves when you get to Amsterdam." */
function marketPortOf(view: FleetView): PortCode | null {
  if (view.fleet.portCode) return view.fleet.portCode
  const path = view.fleet.voyage?.path
  return path ? path[path.length - 1] : null
}

function fleetLabel(view: FleetView): string {
  return `${view.fleet.name} (${view.shipCount} ship${view.shipCount === 1 ? '' : 's'})`
}

function carriedTuns(view: FleetView, good: GoodCode): number {
  return view.ships.reduce(
    (sum, ship) => sum + cargoTuns(ship.cargo.filter((lot) => lot.good === good)),
    0,
  )
}

/** Turn ALL / HALF / 50% into a number of tuns, against whatever the ceiling is for this verb. */
function resolveQty(qty: Qty | undefined, ceiling: number): number {
  if (!qty) return 0
  switch (qty.kind) {
    case 'exact':
      return qty.tuns
    case 'ALL':
      return Math.max(0, Math.floor(ceiling))
    case 'HALF':
      return Math.max(0, Math.floor(ceiling / 2))
    case 'percent':
      return Math.max(0, Math.floor((ceiling * qty.pct) / 100))
  }
}

/** THE ENTRY POINT. Give it the raw line and the world; it gives back exactly what the check block
 *  under the input should say. */
export function checkCommand(raw: string, model: WorldModel, selectedFleetId?: string): CheckResult {
  const parsed = parseOrder(raw, model.parseContext)
  if (!parsed.ok) {
    return err(parsed.code, parsed.message, parseFixes(parsed.code, raw, model, parsed.candidates))
  }
  const order = parsed.order

  if (order.locked) {
    return err(
      'E_RANK_LOCKED',
      `${order.verb} is a real order, but it is not in this version of the game. V0 ships eight verbs: ` +
        'SAIL, BUY, SELL, PROVISION, HIRE, REPAIR, CANCEL, CLEAR.',
      [{ command: 'SAIL ', note: 'start an order that does exist' }],
      order,
    )
  }

  // Which fleet? The order may name one; otherwise the tab's selection stands in, which is what
  // makes `BUY sal 60` a complete order on a phone.
  const fleetId = order.fleetId ?? selectedFleetId
  const view = fleetId ? model.fleetView(fleetId) : undefined
  if (!view) {
    return err(
      'E_NO_SUCH_FLEET',
      'Name a fleet, or select one above — the order has to belong to somebody.',
      model.fleetViews.map((v) => ({ command: `${order.verb} ${v.fleet.name}`, note: v.fleet.name })),
      order,
    )
  }

  // F.3 — the queue is twelve deep for every queueing verb, so it is checked before the verb's own
  // preconditions: a full queue refuses the order whatever else is true about it.
  const queue = model.ordersFor(view.fleet.id).filter((o) => o.status === 'pending' || o.status === 'active')
  const queues = order.verb !== 'CANCEL' && order.verb !== 'CLEAR'
  if (queues && queue.length >= MAX_QUEUE) {
    return err(
      'E_QUEUE_FULL',
      `${view.fleet.name} already holds ${queue.length} orders. A fleet may carry twelve.`,
      [{ command: `CLEAR ${view.fleet.name}`, note: 'drop every pending order' }],
      order,
    )
  }

  switch (order.verb) {
    case 'SAIL':
      return checkSail(order, view, model)
    case 'BUY':
      return checkBuy(order, view, model)
    case 'SELL':
      return checkSell(order, view, model)
    case 'PROVISION':
      return checkProvision(order, view, model)
    case 'HIRE':
      return checkHire(order, view, model)
    case 'REPAIR':
      return checkRepair(order, view, model)
    case 'CANCEL':
      return checkCancel(order, view, model)
    case 'CLEAR':
      return checkClear(order, view, model)
    default:
      return err('E_PARSE', 'That order is not understood.', [{ command: 'SAIL ' }], order)
  }
}

// ── SAIL ─────────────────────────────────────────────────────────────────────────────────────
// F.2's reject order: E_NOT_DOCKED, E_NO_ROUTE, E_ENDURANCE, E_CREW_SHORT, E_DRAFT,
// E_PORT_CLOSED, E_FLAGSHIP_DISABLED, E_LANGUAGE. Structural refusals first, then the ones that
// depend on what the fleet is carrying.

function checkSail(order: ParsedOrder, view: FleetView, model: WorldModel): CheckResult {
  const from = view.fleet.portCode
  if (!from || (view.fleet.status !== 'DOCKED' && view.fleet.status !== 'ANCHORED')) {
    const dest = view.progress?.destination
    return err(
      'E_NOT_DOCKED',
      view.fleet.status === 'SAILING'
        ? `${view.fleet.name} is already at sea, ${formatNm(view.progress?.remainingNm ?? 0)} short of ${dest ? model.portOf(dest).name : 'its destination'}. A fleet cannot be given a new course without turning back first.`
        : `${view.fleet.name} is ${view.fleet.status.toLowerCase().replace('_', ' ')} and cannot sail.`,
      view.fleet.status === 'SAILING'
        ? [
            { command: `CANCEL ${view.fleet.name} 1`, note: 'turn for the nearest port (a recall)' },
            { command: `SAIL ${view.fleet.name} TO ${dest ? model.portOf(dest).name : ''}`, note: 'queue it for after arrival' },
          ]
        : [{ command: `REPAIR ${view.fleet.name}` }],
      order,
    )
  }
  if (!order.port) {
    return err('E_NO_SUCH_PORT', 'Name a port to sail to.', portFixes(view, model), order)
  }
  if (view.flagshipDisabled) {
    return err(
      'E_FLAGSHIP_DISABLED',
      `${view.flagship?.name ?? 'The flagship'} has no hull left. C.4: a fleet whose flagship is disabled cannot sail until it is repaired.`,
      [{ command: `REPAIR ${view.fleet.name} TO 100` }],
      order,
    )
  }
  const short = view.ships.filter((s) => s.crew < model.classOf(s).crewRequired)
  if (short.length > 0) {
    const need = short.reduce((n, s) => n + (model.classOf(s).crewRequired - s.crew), 0)
    return err(
      'E_CREW_SHORT',
      `${short.map((s) => s.name).join(' and ')} cannot be worked by the hands aboard. ${formatInt(need)} more are needed before this fleet puts to sea.`,
      [{ command: `HIRE ${need} CREW FOR ${view.fleet.name}` }],
      order,
    )
  }

  const route = resolveRoute(model.graph, from, order.port, order.via ?? [])
  if (!route) {
    return err(
      'E_NO_ROUTE',
      `No sailed route joins ${model.portOf(from).name} to ${model.portOf(order.port).name}${(order.via ?? []).length > 0 ? ' by way of the calls you gave' : ''}. The router only ever composes authored legs, so it will not draw a line across land.`,
      [{ command: `SAIL ${view.fleet.name} TO ${model.portOf(order.port).name}`, note: 'without the VIA calls' }],
      order,
    )
  }

  const tooShallow = route.path
    .map((code) => model.portOf(code))
    .filter((p) => p.maxDraft < view.maxDraft)
  if (tooShallow.length > 0) {
    const p = tooShallow[0]
    const deepest = view.ships.reduce(
      (worst, s) => (model.classOf(s).draft > model.classOf(worst).draft ? s : worst),
      view.ships[0],
    )
    return err(
      'E_DRAFT',
      `${p.name} takes ${p.maxDraft} of draft; ${deepest.name} draws ${model.classOf(deepest).draft}. She would take the ground on the bar.`,
      [{ command: `SAIL ${view.fleet.name} TO ${nearestDeepEnough(view, model, p) ?? 'Lisboa'}`, note: 'a harbour that will take her' }],
      order,
    )
  }

  const days = voyageDaysFor(route.totalNm, view.speedKn)
  const needed = days * ENDURANCE_SAFETY_MARGIN
  if (view.enduranceDays < needed) {
    return err(
      'E_ENDURANCE',
      `${view.fleet.name} carries ${formatVoyageDays(view.enduranceDays)} of stores. ${model.portOf(order.port).name} is ${formatVoyageDays(days)} away by the route you gave, and a fleet may not sail without ${formatVoyageDays(needed)} aboard — the fifteen per cent that covers a calm.`,
      [
        {
          command: `PROVISION ${view.fleet.name} FULL`,
          note: `est. ${formatDucats(provisionCost(view, model, { mode: 'FULL' }).ducats)}`,
        },
        {
          command: `PROVISION ${view.fleet.name} ${Math.ceil(needed)} DAYS`,
          note: 'just enough for this passage',
        },
      ],
      order,
      [`endurance ${formatVoyageDays(view.enduranceDays)} · needs ${formatVoyageDays(needed)}`],
    )
  }

  const realMs = voyageDaysToRealMs(days)
  const wages = Math.round(view.burn.wagesDucats * days)
  return {
    ok: true,
    order,
    summary: `parsed · ${fleetLabel(view)} · ${route.legCount} leg${route.legCount === 1 ? '' : 's'} · ${formatNm(route.totalNm)}`,
    details: [
      `route ${route.path.map((c) => model.portOf(c).name).join(' → ')}`,
      `ETA ${formatRealDuration(realMs)} real · ${formatVoyageDays(days)} voyage-days · ${view.speedKn.toFixed(1)} kn`,
      `stores ${formatVoyageDays(view.enduranceDays)} endurance · needs ${formatVoyageDays(needed)}`,
      `wages ${formatDucats(wages)} over the passage · ${formatInt(view.burn.crew)} hands`,
    ],
    warnings: order.speed === 'press'
      ? ['SPEED press: +8% speed, +40% hull wear, +25% hazard.']
      : [],
  }
}

function nearestDeepEnough(view: FleetView, model: WorldModel, avoid: Port): string | null {
  const ok = model.world.ports.find((p) => p.code !== avoid.code && p.maxDraft >= view.maxDraft)
  return ok?.name ?? null
}

// ── BUY ──────────────────────────────────────────────────────────────────────────────────────
// F.2's reject order: E_NOT_DOCKED, E_NO_SUCH_GOOD, E_UNAVAILABLE, E_INSUFFICIENT_FUNDS,
// E_HOLD_FULL, E_NO_STOCK, E_DAILY_CAP, E_PRICE_LIMIT.

function checkBuy(order: ParsedOrder, view: FleetView, model: WorldModel): CheckResult {
  const portCode = marketPortOf(view)
  if (!portCode || !order.good) {
    return err('E_NO_SUCH_GOOD', 'Name something to buy.', goodFixes(model, 'BUY'), order)
  }
  const port = model.portOf(portCode)
  const good = model.goodOf(order.good)
  const queued = view.fleet.status === 'SAILING'

  if (!isAvailable(good, port.culture)) {
    return err(
      'E_UNAVAILABLE',
      `${port.name} does not trade ${good.name}. Its culture will not have it on the quay, this season or any other.`,
      goodFixes(model, 'BUY', portCode),
      order,
    )
  }
  const row = model.priceIndex.rows.get(rowKey(portCode, order.good))
  const mid = row ? midPrice(good, port, row) : null
  if (!row || mid === null) {
    return err('E_NO_STOCK', `${port.name} has no ${good.name} to sell.`, goodFixes(model, 'BUY', portCode), order)
  }
  const ask = askPrice(mid, port, model.world.player.taxRelief)
  const affordable = Math.floor(model.world.player.ducats / Math.max(ask, 1))
  const wanted = resolveQty(order.qty, Math.min(view.holdFree, affordable, row.stock))
  if (wanted <= 0) {
    return err(
      'E_PARSE',
      'How much? Give a number of tuns, or ALL, or HALF.',
      [{ command: `BUY ${good.name} ${Math.min(50, Math.floor(view.holdFree))}` }],
      order,
    )
  }

  if (row.stock < wanted) {
    return err(
      'E_NO_STOCK',
      `${port.name} holds ${formatTuns(row.stock)} of ${good.name}; you asked for ${formatTuns(wanted)}.`,
      [{ command: `BUY ${good.name} ${Math.floor(row.stock)}`, note: 'take what there is' }],
      order,
    )
  }
  const cap = Math.round(DAILY_CAP_FRACTION * row.stockTarget)
  if (wanted > cap) {
    return err(
      'E_DAILY_CAP',
      `${port.name} will not let one house move more than ${formatTuns(cap)} of ${good.name} in a game-day. You asked for ${formatTuns(wanted)}.`,
      [{ command: `BUY ${good.name} ${cap}`, note: 'the most the port allows today' }],
      order,
    )
  }
  if (wanted > view.holdFree) {
    return err(
      'E_HOLD_FULL',
      `${view.fleet.name} has ${formatTuns(view.holdFree, 1)} free; you asked for ${formatTuns(wanted)}.`,
      [
        { command: `BUY ${good.name} ${Math.floor(view.holdFree)}`, note: 'fill what is left' },
        { command: `SELL ${heaviestLot(view) ?? good.name} ALL`, note: 'make room first' },
      ],
      order,
    )
  }

  const cost = steppedBuyCost(good, port, row, wanted, model.world.player.taxRelief)
  if (cost.total > model.world.player.ducats) {
    const canAfford = Math.max(0, Math.floor((model.world.player.ducats / cost.total) * wanted))
    return err(
      'E_INSUFFICIENT_FUNDS',
      `${formatTuns(wanted)} of ${good.name} comes to ${formatDucats(cost.total)} at ${formatInt(cost.average)} d./t. You hold ${formatDucats(model.world.player.ducats)}.`,
      [{ command: `BUY ${good.name} ${canAfford}`, note: `about ${formatDucats(model.world.player.ducats)}` }],
      order,
    )
  }
  if (order.limit && order.limit.op === '<=' && cost.average > order.limit.price) {
    return err(
      'E_PRICE_LIMIT',
      `${good.name} opens at ${formatInt(ask)} d. in ${port.name} and averages ${formatInt(cost.average)} d. over ${formatTuns(wanted)}. Your limit was ${formatInt(order.limit.price)}. Nothing would be bought and the queue would stop here.`,
      [
        { command: `BUY ${good.name} ${wanted} AT <= ${Math.ceil(cost.average)}`, note: 'raise the limit to the market' },
        { command: `BUY ${good.name} ${wanted}`, note: 'take the market' },
      ],
      order,
    )
  }

  return {
    ok: true,
    order,
    summary: `parsed · BUY ${formatTuns(wanted)} ${good.name} at ${port.name} · ${formatDucats(cost.total)}`,
    details: [
      `average ${formatInt(cost.average)} d./t (opens at ${formatInt(ask)}, ${STEP_NOTE})`,
      `hold ${formatTuns(view.holdUsed, 1)} used of ${formatTuns(view.holdTotal)} · ${formatTuns(view.holdFree - wanted, 1)} would remain`,
      `balance ${formatDucats(model.world.player.ducats)} → ${formatDucats(model.world.player.ducats - cost.total)}`,
    ],
    warnings: queued
      ? [`${view.fleet.name} is at sea. This is queued and runs on arrival at ${port.name}; the price will have moved.`]
      : [],
  }
}

const STEP_NOTE = 'prices step every 10 t'

function heaviestLot(view: FleetView): string | null {
  let best: { good: string; tuns: number } | null = null
  for (const ship of view.ships) {
    for (const lot of ship.cargo) {
      if (!best || lot.tuns > best.tuns) best = { good: lot.good, tuns: lot.tuns }
    }
  }
  return best?.good ?? null
}

// ── SELL ─────────────────────────────────────────────────────────────────────────────────────
// F.2's reject order: E_NOT_DOCKED, E_NO_CARGO, E_UNAVAILABLE, E_DAILY_CAP, E_PRICE_LIMIT.

function checkSell(order: ParsedOrder, view: FleetView, model: WorldModel): CheckResult {
  const portCode = marketPortOf(view)
  if (!portCode || !order.good) {
    return err('E_NO_SUCH_GOOD', 'Name something to sell.', goodFixes(model, 'SELL'), order)
  }
  const port = model.portOf(portCode)
  const good = model.goodOf(order.good)
  const carried = carriedTuns(view, order.good)

  if (carried <= 0) {
    const alt = heaviestLot(view)
    return err(
      'E_NO_CARGO',
      `${view.fleet.name} is carrying no ${good.name}.`,
      alt ? [{ command: `SELL ${alt} ALL`, note: 'what she is actually carrying' }] : [{ command: `BUY ${good.name} 50` }],
      order,
    )
  }
  if (!isAvailable(good, port.culture)) {
    return err(
      'E_UNAVAILABLE',
      `${port.name} will not buy ${good.name}. You would have to carry it elsewhere.`,
      [{ command: `SAIL ${view.fleet.name} TO Lisboa`, note: 'a port that trades it' }],
      order,
    )
  }
  const row = model.priceIndex.rows.get(rowKey(portCode, order.good))
  const mid = row ? midPrice(good, port, row) : null
  if (!row || mid === null) {
    return err('E_UNAVAILABLE', `${port.name} has no market in ${good.name}.`, goodFixes(model, 'SELL', portCode), order)
  }
  const wanted = Math.min(carried, resolveQty(order.qty, carried))
  if (wanted <= 0) {
    return err('E_PARSE', 'How much? Give a number of tuns, or ALL, or HALF.', [{ command: `SELL ${good.name} ALL` }], order)
  }
  const cap = Math.round(DAILY_CAP_FRACTION * row.stockTarget)
  if (wanted > cap) {
    return err(
      'E_DAILY_CAP',
      `${port.name} will not take more than ${formatTuns(cap)} of ${good.name} from one house in a game-day.`,
      [{ command: `SELL ${good.name} ${cap}` }],
      order,
    )
  }
  const revenue = steppedSellRevenue(good, port, row, wanted, model.world.player.taxRelief)
  const bid = bidPrice(mid, port, model.world.player.taxRelief)
  if (order.limit && order.limit.op === '>=' && revenue.average < order.limit.price) {
    return err(
      'E_PRICE_LIMIT',
      `${good.name} is bid ${formatInt(bid)} d. in ${port.name} and averages ${formatInt(revenue.average)} d. over ${formatTuns(wanted)}. Your limit was ${formatInt(order.limit.price)}. Nothing would be sold and the queue would stop here.`,
      [
        { command: `SELL ${good.name} ${orderQtyText(order.qty)} AT >= ${Math.floor(revenue.average)}`, note: 'meet the market' },
        { command: `SELL ${good.name} ${orderQtyText(order.qty)}`, note: 'take the market' },
      ],
      order,
    )
  }

  const cost = view.ships
    .flatMap((s) => s.cargo)
    .filter((lot) => lot.good === order.good)
    .reduce((sum, lot) => sum + lot.avgCost * Math.min(lot.tuns, wanted), 0)

  return {
    ok: true,
    order,
    summary: `parsed · SELL ${formatTuns(wanted)} ${good.name} at ${port.name} · ${formatDucats(revenue.total)}`,
    details: [
      `average ${formatInt(revenue.average)} d./t (bid ${formatInt(bid)}, ${STEP_NOTE})`,
      `realised margin ${formatDucats(revenue.total - cost)} against ${formatDucats(cost)} of capital`,
      `hold ${formatTuns(view.holdUsed - wanted, 1)} would remain of ${formatTuns(view.holdTotal)}`,
    ],
    warnings: view.fleet.status === 'SAILING'
      ? [`${view.fleet.name} is at sea. This is queued and runs on arrival at ${port.name}.`]
      : [],
  }
}

function orderQtyText(qty: Qty | undefined): string {
  if (!qty) return 'ALL'
  switch (qty.kind) {
    case 'ALL':
      return 'ALL'
    case 'HALF':
      return 'HALF'
    case 'percent':
      return `${qty.pct}%`
    case 'exact':
      return String(qty.tuns)
  }
}

// ── PROVISION ────────────────────────────────────────────────────────────────────────────────

interface ProvisionPlan {
  waterT: number
  foodT: number
  ducats: number
  resultingDays: number
}

function provisionCost(view: FleetView, model: WorldModel, target: NonNullable<ParsedOrder['provision']>): ProvisionPlan {
  const portCode = view.fleet.portCode ?? model.world.currentPort
  const port = model.portOf(portCode)
  let waterT = 0
  let foodT = 0
  let resultingDays = Infinity
  for (const ship of view.ships) {
    const cls = model.classOf(ship)
    const cargo = cargoTuns(ship.cargo)
    let wantWater: number
    let wantFood: number
    if (target.mode === 'EXPLICIT') {
      wantWater = ship.waterT + target.waterT / view.shipCount
      wantFood = ship.foodT + target.foodT / view.shipCount
    } else {
      const days =
        target.mode === 'DAYS'
          ? target.days
          : // FULL: fill stores to the ship's store_ratio of its hold, then read the days back out.
            (cls.hold * DEFAULT_STORE_RATIO) / (ship.crew * (WATER_PER_CREW_DAY + FOOD_PER_CREW_DAY))
      wantWater = ship.crew * WATER_PER_CREW_DAY * days
      wantFood = ship.crew * FOOD_PER_CREW_DAY * days
    }
    // Never more than the hull will hold beside its cargo.
    const room = Math.max(0, cls.hold - cargo)
    const scale = wantWater + wantFood > room ? room / (wantWater + wantFood) : 1
    wantWater *= scale
    wantFood *= scale
    waterT += Math.max(0, wantWater - ship.waterT)
    foodT += Math.max(0, wantFood - ship.foodT)
    resultingDays = Math.min(
      resultingDays,
      Math.min(wantWater / (ship.crew * WATER_PER_CREW_DAY), wantFood / (ship.crew * FOOD_PER_CREW_DAY)),
    )
  }
  return {
    waterT,
    foodT,
    ducats: waterT * port.waterPrice + foodT * port.foodPrice,
    resultingDays,
  }
}

function checkProvision(order: ParsedOrder, view: FleetView, model: WorldModel): CheckResult {
  const notDocked = requireDocked(order, view, model, 'provision')
  if (notDocked) return notDocked
  const plan = provisionCost(view, model, order.provision ?? { mode: 'FULL' })
  if (plan.waterT + plan.foodT <= 0.01) {
    return {
      ok: true,
      order,
      summary: `parsed · ${view.fleet.name} is already stored to that mark`,
      details: [`endurance ${formatVoyageDays(view.enduranceDays)}`],
      warnings: ['Nothing would be bought.'],
    }
  }
  if (plan.ducats > model.world.player.ducats) {
    return err(
      'E_INSUFFICIENT_FUNDS',
      `Storing ${view.fleet.name} to that mark costs ${formatDucats(plan.ducats)}. You hold ${formatDucats(model.world.player.ducats)}.`,
      [{ command: `PROVISION ${view.fleet.name} 15 DAYS`, note: 'a shorter reach' }],
      order,
    )
  }
  return {
    ok: true,
    order,
    summary: `parsed · PROVISION ${view.fleet.name} · ${formatDucats(plan.ducats)}`,
    details: [
      `water ${formatTuns(plan.waterT, 1)} · food ${formatTuns(plan.foodT, 1)}`,
      `endurance ${formatVoyageDays(view.enduranceDays)} → ${formatVoyageDays(plan.resultingDays)}`,
      `every tun of water is a tun of cargo you did not carry`,
    ],
    warnings: [],
  }
}

// ── HIRE ─────────────────────────────────────────────────────────────────────────────────────
// F.2's reject order: E_CREW_POOL, E_CREW_MAX, E_INSUFFICIENT_FUNDS.
//
// THE DOCUMENT IS SILENT on when the pool is a refusal rather than a premium: F.2 says the pre is
// "port crew pool >= count OR pay the urgent premium", which never refuses. The choice made here,
// recorded in README.md: beyond TWICE the pool the port simply has not got the men, and that is
// E_CREW_POOL; between the pool and twice it, the rate is x2.5 and the check line WARNS.

function checkHire(order: ParsedOrder, view: FleetView, model: WorldModel): CheckResult {
  const notDocked = requireDocked(order, view, model, 'take on hands')
  if (notDocked) return notDocked
  const port = model.portOf(view.fleet.portCode ?? model.world.currentPort)
  const count = order.crewCount ?? 0
  if (count <= 0) {
    return err('E_PARSE', 'How many hands?', [{ command: `HIRE 8 CREW FOR ${view.fleet.name}` }], order)
  }
  if (count > port.crewPool * 2) {
    return err(
      'E_CREW_POOL',
      `${port.name} has ${formatInt(port.crewPool)} men seeking a berth. ${formatInt(count)} is more than the town can raise, at any price.`,
      [{ command: `HIRE ${port.crewPool} CREW FOR ${view.fleet.name}` }],
      order,
    )
  }
  if (view.crew + count > view.crewMax) {
    return err(
      'E_CREW_MAX',
      `${view.fleet.name} can berth ${formatInt(view.crewMax)} and already carries ${formatInt(view.crew)}. There is room for ${formatInt(view.crewMax - view.crew)} more.`,
      [{ command: `HIRE ${Math.max(0, view.crewMax - view.crew)} CREW FOR ${view.fleet.name}` }],
      order,
    )
  }
  const ordinary = Math.min(count, port.crewPool)
  const urgent = count - ordinary
  const ducats = ordinary * port.crewRate + urgent * port.crewRate * URGENT_CREW_MULTIPLIER
  if (ducats > model.world.player.ducats) {
    return err(
      'E_INSUFFICIENT_FUNDS',
      `${formatInt(count)} hands come to ${formatDucats(ducats)}. You hold ${formatDucats(model.world.player.ducats)}.`,
      [{ command: `HIRE ${Math.floor(model.world.player.ducats / port.crewRate)} CREW FOR ${view.fleet.name}` }],
      order,
    )
  }
  return {
    ok: true,
    order,
    summary: `parsed · HIRE ${formatInt(count)} hands at ${port.name} · ${formatDucats(ducats)}`,
    details: [
      `crew ${formatInt(view.crew)} → ${formatInt(view.crew + count)} of ${formatInt(view.crewMax)}`,
      `daily burn ${formatDucats(view.burn.wagesDucats + count)} in wages, ${formatTuns((view.crew + count) * (WATER_PER_CREW_DAY + FOOD_PER_CREW_DAY), 1)} of stores`,
    ],
    warnings: urgent > 0
      ? [`${formatInt(urgent)} of them are urgent recruitment at ${URGENT_CREW_MULTIPLIER}x the rate.`]
      : [],
  }
}

// ── REPAIR ───────────────────────────────────────────────────────────────────────────────────

function checkRepair(order: ParsedOrder, view: FleetView, model: WorldModel): CheckResult {
  const notDocked = requireDocked(order, view, model, 'go into the yard')
  if (notDocked) return notDocked
  const port = model.portOf(view.fleet.portCode ?? model.world.currentPort)
  if (!port.hasYard) {
    const yard = model.world.ports.find((p) => p.hasYard && p.code !== port.code)
    return err(
      'E_NO_YARD',
      `${port.name} has no repair yard. Hulls are mended where there are shipwrights.`,
      yard ? [{ command: `SAIL ${view.fleet.name} TO ${yard.name}`, note: `tier ${yard.yardTier} yard` }] : [],
      order,
    )
  }
  const targetPct = (order.repairToPct ?? 100) / 100
  let points = 0
  for (const ship of view.ships) {
    const cls = model.classOf(ship)
    points += Math.max(0, cls.maxDurability * targetPct - ship.durability)
  }
  if (points <= 0) {
    return {
      ok: true,
      order,
      summary: `parsed · ${view.fleet.name} is already sound to that mark`,
      details: [`worst hull ${Math.round(view.worstHullFraction * 100)}%`],
      warnings: ['Nothing would be paid.'],
    }
  }
  const ducats = points * port.repairRate * (1 - port.devIndustry * 0.01)
  if (ducats > model.world.player.ducats) {
    return err(
      'E_INSUFFICIENT_FUNDS',
      `That work comes to ${formatDucats(ducats)}. You hold ${formatDucats(model.world.player.ducats)}.`,
      [{ command: `REPAIR ${view.fleet.name} TO 80`, note: 'enough to sail on' }],
      order,
    )
  }
  // F.2 — repair takes voyage-time: hours = damage_pct x 0.4 sim-hours.
  const damagePct = (1 - view.worstHullFraction) * 100
  const simHours = damagePct * 0.4
  return {
    ok: true,
    order,
    summary: `parsed · REPAIR ${view.fleet.name} to ${Math.round(targetPct * 100)}% · ${formatDucats(ducats)}`,
    details: [
      `${formatInt(points)} points at ${port.repairRate.toFixed(1)} d., less ${port.devIndustry}% for ${port.name}'s yards`,
      `in the yard ${formatVoyageDays(simHours / 24)} · ${formatRealDuration(voyageDaysToRealMs(simHours / 24))} real`,
    ],
    warnings: [],
  }
}

// ── CANCEL / CLEAR ───────────────────────────────────────────────────────────────────────────
// F.3's cancellation table, including the rule that CANCEL on an active voyage IS a RECALL and
// the parser must say which one it did.

function checkCancel(order: ParsedOrder, view: FleetView, model: WorldModel): CheckResult {
  const queue = model.ordersFor(view.fleet.id).filter((o) => o.status === 'pending' || o.status === 'active')
  if (queue.length === 0) {
    return err(
      'E_PARSE',
      `${view.fleet.name} has no orders to cancel.`,
      [{ command: `SAIL ${view.fleet.name} TO `, note: 'give it something to do' }],
      order,
    )
  }
  const index = order.orderIndex ?? queue[0].seq
  const target = queue.find((o) => o.seq === index)
  if (!target) {
    return err(
      'E_PARSE',
      `${view.fleet.name} has no order ${index}. Its queue runs 1 to ${queue[queue.length - 1].seq}.`,
      queue.map((o) => ({ command: `CANCEL ${view.fleet.name} ${o.seq}`, note: o.raw })),
      order,
    )
  }
  const isActiveSail = target.status === 'active' && target.raw.trim().toUpperCase().startsWith('SAIL')
  return {
    ok: true,
    order,
    summary: `parsed · CANCEL ${view.fleet.name} order ${index} — "${target.raw}"`,
    details: isActiveSail
      ? [
          'This voyage is under way, so CANCEL is a RECALL: she turns for the nearest reachable port from where she is now.',
          'Nothing is refunded. Provisions already burned stay burned.',
        ]
      : ['Removed from the queue. Later orders shift up. Free.'],
    warnings: isActiveSail ? ['A recall is not a rewind.'] : [],
  }
}

function checkClear(order: ParsedOrder, view: FleetView, model: WorldModel): CheckResult {
  const queue = model.ordersFor(view.fleet.id)
  const pending = queue.filter((o) => o.status === 'pending')
  const active = queue.find((o) => o.status === 'active')
  if (order.includeActive && view.fleet.status !== 'SAILING') {
    return err(
      'E_NOT_SAILING',
      `CLEAR ALL also recalls a voyage, and ${view.fleet.name} is not at sea.`,
      [{ command: `CLEAR ${view.fleet.name}`, note: 'drop the pending orders only' }],
      order,
    )
  }
  return {
    ok: true,
    order,
    summary: `parsed · CLEAR ${view.fleet.name} · ${pending.length} pending order${pending.length === 1 ? '' : 's'}`,
    details: order.includeActive
      ? ['Every pending order is dropped AND the active voyage is recalled.']
      : [
          'Every pending order is dropped.',
          active ? `The active order — "${active.raw}" — keeps running.` : 'Nothing is running.',
        ],
    warnings: order.includeActive ? ['This needs a confirm on the server (F.3).'] : [],
  }
}

// ── SHARED ───────────────────────────────────────────────────────────────────────────────────

function requireDocked(order: ParsedOrder, view: FleetView, model: WorldModel, doing: string): CheckErr | null {
  if (view.fleet.status === 'DOCKED') return null
  const dest = view.progress?.destination
  return err(
    'E_NOT_DOCKED',
    view.fleet.status === 'SAILING'
      ? `${view.fleet.name} is at sea and cannot ${doing}. She is due at ${dest ? model.portOf(dest).name : 'her destination'} in ${formatRealDuration(view.progress?.remainingMs ?? 0)}.`
      : `${view.fleet.name} is ${view.fleet.status.toLowerCase().replace('_', ' ')} and cannot ${doing} until she is alongside.`,
    [
      { command: `${order.verb} ${dockedFleetName(model) ?? view.fleet.name}`, note: 'a fleet that is alongside' },
    ],
    order,
  )
}

function dockedFleetName(model: WorldModel): string | null {
  return model.fleetViews.find((v) => v.fleet.status === 'DOCKED')?.fleet.name ?? null
}

function portFixes(view: FleetView, model: WorldModel): readonly Fix[] {
  const from = view.fleet.portCode
  if (!from) return []
  return [...(model.graph.edges.get(from)?.keys() ?? [])]
    .slice(0, 3)
    .map((code) => ({ command: `SAIL ${view.fleet.name} TO ${model.portOf(code).name}`, note: 'one leg away' }))
}

function goodFixes(model: WorldModel, verb: string, port?: PortCode): readonly Fix[] {
  const code = port ?? model.world.currentPort
  const p = model.portOf(code)
  return model.world.goods
    .filter((g) => isAvailable(g, p.culture))
    .slice(0, 3)
    .map((g) => ({ command: `${verb} ${g.name} 50`, note: `traded in ${p.name}` }))
}

function parseFixes(code: ErrorCode, raw: string, model: WorldModel, candidates?: readonly string[]): readonly Fix[] {
  if (code === 'E_AMBIGUOUS' && candidates && candidates.length > 0) {
    const tokens = raw.trim().split(/\s+/)
    const head = tokens.slice(0, Math.max(1, tokens.length - 1)).join(' ')
    return candidates.slice(0, 4).map((name) => ({ command: `${head} ${name}`, note: 'this one' }))
  }
  const docked = dockedFleetName(model)
  return [
    { command: `SAIL ${docked ?? ''} TO `.trimEnd(), note: 'send a fleet somewhere' },
    { command: 'BUY sal 50', note: 'take cargo aboard' },
  ]
}
