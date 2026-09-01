// THE SHAPES A TRADE IS DRAWN BETWEEN — pure, no React, no store, no rules of the game.
//
// MOVED HERE 2026-09-01 from features/command/fleetLimits.ts, because a SECOND screen now trades:
// the owner's row 53 puts buy and sell on PORT, and `tests/sections.spec.ts` refuses to let one
// screen reach into another — "whatever is being shared is not that screen's". This is the part
// that was never COMMAND's: the shape of a stepper's ceiling, and the shape of the answer
// `world.buy_capacity()` gives. `src/lib` is the layer everything stands on, so a picker in the
// design system, a hook in the live store and two screens can all name the same type without a
// cycle.
//
// The prose below is the file's own, kept whole: it records what this used to own and where each
// of those answers went, and that history is the reason the file is this small.

//
// E.1/F.5: a quantity should never be a free-form number the server has to refuse. The stepper is
// bounded by the hold, the purse, the stock and what is aboard, so "you cannot fit that" is
// something the player SEES rather than something they are told after the fact.
//
// ── THESE ARE BOUNDS, NOT RULES ────────────────────────────────────────────────────────────────
// Nothing here decides whether an order is legal — `cmd.preview()` does, by running the real verb.
// That is why validate.ts is gone: two authorities for "is this order legal" is the duplication
// this project forbids, and the server's is the one that cannot drift.
//
// ── WHAT THIS FILE STOPPED OWNING, 2026-08-22, AND WHERE EACH ANSWER LIVES NOW ─────────────────
// It had grown into a second `domain/fleet`. Five of its seven exports were folds over the hulls
// of a fleet — which is the definition of that section, not of this tab — and four of them had a
// twin somewhere else in `src/`:
//
//   freeHoldTuns   → `fleet.free_hold`, SERVED (public.fleet_free_hold, migration 0017:183).
//                    It was one of THREE client spellings of `Σ max(0, hold − cargo − water −
//                    food)`; MarketScreen's copy forgot the water and the food entirely.
//   cargoManifest  → `fleetCargoByCode(fleet)` in domain/fleet — the same fold as `fleetCargo`,
//   cargoAboard      written twice more here, once for the whole map and once for one code.
//   crewBerths     → `fleetCrew(fleet).berths`, and it was the DRIFTED copy: it clamped per hull
//                    while the server's E_CREW_MAX does not (migration 0007:659).
//   crewShort      → `fleetCrew(fleet).short`.
//   hullPct        → `worstHullFraction(fleet)` in domain/fleet, which computed the same minimum.
//   bulkOf         → deleted outright; nothing called it, and a good's bulk is already one lookup
//                    away in the store's `goodByCode` index.
//
// WHAT IS LEFT IS THE ONLY THING THAT WAS EVER THIS TAB'S: the shape of a stepper's ceiling.

/** A stepper's ceiling, and the thing that sets it — so the screen can say WHY it stops there. */
export interface QtyBound {
  max: number
  /** "the hold" · "the stock here" · "your purse" · "what is aboard". Shown beside the slider. */
  binding: string
}

// THE BUY CEILING IS NOT HERE. It used to be — `buyBound()` divided the purse by the market's
// opening ask — and it was wrong by construction, because a BUY reprices as it walks the book
// (§G.2). It offered 91 tuns of pepper against a purse that could carry 50. The answer now comes
// from `world.buy_capacity()` through ./useBuyCapacity.ts, priced by the same stepped quote the
// trade itself walks. Selling stays here: what is aboard is aboard, and the client can count it.

export function sellBound(aboard: number): QtyBound {
  return { max: Math.max(0, Math.floor(aboard)), binding: 'what is aboard' }
}

/**
 * WHAT `world.buy_capacity()` ANSWERED, as a picker reads it. The hook that asks lives in
 * `src/live/useBuyCapacity.ts` — this is only the shape, so the design system can take it as a
 * prop without importing the store it comes from.
 */
export interface BuyCapacityState {
  /** Null until the answer for THIS good arrives; the picker waits rather than offering a guess. */
  bound: QtyBound | null
  /** What the server says that many tuns would cost, at the stepped price. */
  estTotal: number | null
  loading: boolean
}
