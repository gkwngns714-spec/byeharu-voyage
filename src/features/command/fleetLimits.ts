// WHAT IS ACTUALLY POSSIBLE — the bounds a picker is drawn between. Pure; no React.
//
// E.1/F.5: a quantity should never be a free-form number the server has to refuse. The stepper is
// bounded by the hold, the purse, the stock and what is aboard, so "you cannot fit that" is
// something the player SEES rather than something they are told after the fact.
//
// ── THESE ARE BOUNDS, NOT RULES ────────────────────────────────────────────────────────────────
// Every number below is arithmetic over figures the SERVER computed and served (FleetShip.hold,
// .cargo_tuns, .water_t, .food_t, MarketGood.buy/.stock, the purse from world.ledger()). Nothing
// here decides whether an order is legal — `cmd.preview()` does, by running the real verb. That is
// why validate.ts is gone: two authorities for "is this order legal" is the duplication this
// project forbids, and the server's is the one that cannot drift.
//
// The formulae mirror migration 0007 so the slider's end and the server's refusal agree:
//   free hold   = Σ max(0, hold − cargo_tuns − water_t − food_t)   (public.fleet_free_hold)
//   BUY ceiling = floor(free hold ÷ bulk)                          (cmd.do_buy)
//   berths      = Σ (crew_max − crew)                              (cmd.do_hire's E_CREW_MAX)

import type { FleetView, SnapshotGood } from '../../lib/rpc'

/** A good's bulk — the hold space one tun of it takes (B.2). `cmd.do_buy` divides by it. */
export function bulkOf(goods: readonly SnapshotGood[], code: string | undefined): number {
  if (!code) return 1
  return goods.find((g) => g.code === code)?.bulk ?? 1
}

/** Tuns of space the fleet can still take cargo into. Stores occupy the hold too (B.2). */
export function freeHoldTuns(fleet: FleetView | undefined): number {
  if (!fleet) return 0
  return fleet.ships.reduce(
    (sum, s) => sum + Math.max(0, s.hold - s.cargo_tuns - s.water_t - s.food_t),
    0,
  )
}

/** How many tuns of one good are aboard, across every ship in the fleet. */
export function cargoAboard(fleet: FleetView | undefined, goodCode: string): number {
  if (!fleet) return 0
  return fleet.ships.reduce((sum, s) => sum + (s.cargo[goodCode] ?? 0), 0)
}

/** Everything aboard, good code → tuns, so SELL can offer only what there is to sell. */
export function cargoManifest(fleet: FleetView | undefined): Record<string, number> {
  const out: Record<string, number> = {}
  if (!fleet) return out
  for (const ship of fleet.ships) {
    for (const [code, tuns] of Object.entries(ship.cargo)) out[code] = (out[code] ?? 0) + tuns
  }
  return out
}

/** Berths still empty — HIRE's ceiling (E_CREW_MAX). */
export function crewBerths(fleet: FleetView | undefined): number {
  if (!fleet) return 0
  return fleet.ships.reduce((sum, s) => sum + Math.max(0, s.crew_max - s.crew), 0)
}

/** Hands still needed to sail her at all (E_CREW_SHORT) — HIRE's natural suggestion. */
export function crewShort(fleet: FleetView | undefined): number {
  if (!fleet) return 0
  return fleet.ships.reduce((sum, s) => sum + Math.max(0, s.crew_required - s.crew), 0)
}

/** Hull condition as a percentage, worst ship first — REPAIR's starting point. */
export function hullPct(fleet: FleetView | undefined): number {
  if (!fleet || fleet.ships.length === 0) return 100
  const worst = fleet.ships.reduce(
    (low, s) => Math.min(low, s.max_durability > 0 ? s.durability / s.max_durability : 1),
    1,
  )
  return Math.round(worst * 100)
}

/** A stepper's ceiling, and the thing that sets it — so the screen can say WHY it stops there. */
export interface QtyBound {
  max: number
  /** "the hold" · "the stock here" · "your purse" · "what is aboard". Shown beside the slider. */
  binding: string
}

/**
 * How much of a good this fleet could take aboard here. The purse term uses the market's opening
 * ask, and a real BUY reprices as it walks the book (G.1), so the true ceiling is a little lower —
 * `cmd.preview()` reports the exact cost before anything is issued.
 */
export function buyBound(args: {
  freeHold: number
  bulk: number
  stock: number
  ducats: number | null
  unitPrice: number
}): QtyBound {
  const byHold = Math.floor(args.freeHold / Math.max(args.bulk, 0.0001))
  const byStock = Math.floor(args.stock)
  const byPurse =
    args.ducats === null || args.unitPrice <= 0 ? Infinity : Math.floor(args.ducats / args.unitPrice)

  let max = byHold
  let binding = 'the hold'
  if (byStock < max) {
    max = byStock
    binding = 'the stock here'
  }
  if (byPurse < max) {
    max = byPurse
    binding = 'your purse'
  }
  return { max: Math.max(0, max), binding }
}

export function sellBound(aboard: number): QtyBound {
  return { max: Math.max(0, Math.floor(aboard)), binding: 'what is aboard' }
}
