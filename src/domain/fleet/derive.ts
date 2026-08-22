// FLEET ARITHMETIC — the little that is left after the server took the numbers back.
//
// ── WHAT THIS FILE REPLACES, AND WHY THE OLD ONE IS GONE ────────────────────────────────────────
// `fleetMath.ts` stood here and computed speed, endurance, seaworthiness, daily burn and voyage
// position from DESIGN's formulas, against fixture types. Every one of those is now SERVED:
//
//   speed_kn        world.fleets() → voyage.fleet_speed()      (migration 0009:171)
//   endurance_days  world.fleets() → voyage.endurance_days()   (migration 0009:172)
//   cargo_tuns      world.fleets() → public.ship_cargo_tuns()  (migration 0009:183, bulk applied)
//   position        world.fleets() → voyage.position()         (the closed form of DESIGN D.2)
//   hold            world.fleets() → public.ship_hold_capacity (migration 0017:156, quartermaster)
//   free_hold       world.fleets() → public.fleet_free_hold()  (migration 0017:183)
//
// A second implementation of a served number is a second authority, and the server's is the one
// the game obeys — SAIL refuses on ITS endurance figure, not on ours. So the old file was DELETED
// rather than reconciled. Nothing here re-derives a field the RPC carries.
//
// ── THE ONE THAT CAME BACK, 2026-08-22 ──────────────────────────────────────────────────────────
// `fleetHoldFree(fleet)` used to live here and folded `max(0, hold − cargo − water − food)` across
// the hulls. It was ONE of THREE spellings of that subtraction on this side of the wire — the
// others were `features/command/fleetLimits.ts:freeHoldTuns` and a private `freeHold()` in
// MarketScreen that forgot the water and the food entirely and had been over-reporting the free
// hold since it was written. Migration 0017 folded the server's four copies onto
// `public.fleet_free_hold` and serves the answer as `FleetView.free_hold`, so all three client
// copies are DELETED rather than reconciled. **The fleet's free hold is `fleet.free_hold`. There
// is no function for it here and there must not be one again.**
//
// ── WHAT IS LEFT ────────────────────────────────────────────────────────────────────────────────
// Arithmetic the server does not serve as a field, composed only from fields it does: a ratio, a
// subtraction, a fold across the hulls of one fleet. Each function names the SQL it agrees with,
// so a migration that changes the rule has one place on this side to change with it.
//
// Pure: no React, no clock (an instant is always passed in), no fixtures.

import type { FleetShip, FleetStatus, FleetView } from '../../lib/rpc'

/**
 * WHAT A STATUS MEANS — good, in hand, wanting attention, or wrong.
 *
 * This lived TWICE, byte for byte: `features/fleets/FleetsScreen.tsx` and
 * `features/command/OrderQueue.tsx` each carried a private `statusTone()` with the same five arms.
 * Two screens holding one rule is the thing docs/SECTIONS.md forbids, and the tell was that
 * neither could have changed it without the other silently disagreeing about what ADRIFT looks
 * like.
 *
 * IT RETURNS A MEANING, NOT A COLOUR, and that is why a domain section may own it. The strings are
 * the design system's semantic tone names, which `BadgeTone` is structurally identical to — so
 * `<Badge tone={fleetStatusTone(s)}>` type-checks without this pure module importing a component.
 * The section says a fleet is in trouble; `Badge.tsx` decides what trouble looks like.
 */
export function fleetStatusTone(
  status: FleetStatus,
): 'neutral' | 'accent' | 'success' | 'warning' | 'danger' {
  switch (status) {
    case 'SAILING':
      return 'accent'
    case 'DOCKED':
      return 'success'
    case 'REPAIRING':
      return 'warning'
    case 'ADRIFT':
    case 'UNABLE_TO_SAIL':
      return 'danger'
    default:
      return 'neutral'
  }
}

/**
 * WHERE HER NEXT ORDER HAPPENS — the port she is lying in, or, at sea, the port she is BOUND for.
 *
 * A fleet at sea is not nowhere. An order issued to her waits in her queue and runs the moment she
 * is alongside (F.2, "sell the cloves when you get to Amsterdam"), so the market her orders will
 * execute in is `voyage.to` — not wherever a list of ports happens to begin.
 *
 * ADDED 2026-08-22 BECAUSE THERE WERE FOUR SPELLINGS OF IT AND ONE OF THEM WAS WRONG — spaghetti,
 * in the word docs/NO_SPAGHETTI.md §1 asks for. Three read `fleet.port ?? fleet.voyage?.to` inline
 * (`features/command/CommandScreen.tsx`, `features/command/OrderComposer.tsx`,
 * `features/market/MarketScreen.tsx:portOfPlayer`); the fourth, `features/port/PortScreen.tsx`,
 * read only `fleet.port` and fell back to `snapshot.ports[0]` — so with the only fleet at sea the
 * Port tab opened on Acapulco, ~10,000 nm away, and composed orders from there that would have run
 * at the port she was actually bound for. Four answers to one question, and the fourth could not
 * agree with the other three.
 */
export function fleetPortCode(fleet: FleetView): string | null {
  return fleet.port ?? fleet.voyage?.to ?? null
}

/**
 * WHERE THE HOUSE IS — the harbour a screen with no explicit choice should open on.
 *
 * A fleet ALONGSIDE wins over a fleet at sea, because a docked hull can act now. Only when nothing
 * is alongside does a fleet's destination stand in. Null when the house has no fleet at all, which
 * is the only case where a screen may reasonably fall back to the world's first port.
 */
export function housePortCode(fleets: readonly FleetView[]): string | null {
  const alongside = fleets.find((f) => f.port)
  if (alongside?.port) return alongside.port
  for (const f of fleets) {
    const bound = fleetPortCode(f)
    if (bound) return bound
  }
  return null
}

/** Hull condition, 0–1. `durability` and `max_durability` are both served; the ratio is not. */
export function hullFraction(ship: FleetShip): number {
  return ship.max_durability > 0 ? ship.durability / ship.max_durability : 0
}

/** Everything aboard, in tuns: trade cargo (bulk already applied by the server) plus the stores
 *  that compete with it for the same hold. DESIGN C.3 — "every tun of water is a tun of pepper you
 *  did not carry" — and it is exactly the term `public.fleet_free_hold` subtracts (0007:127). */
export function shipHoldUsed(ship: FleetShip): number {
  return ship.cargo_tuns + ship.water_t + ship.food_t
}

/**
 * Room for the next parcel IN ONE HULL — the per-ship term of `public.fleet_free_hold` (0017:183).
 *
 * THIS IS NOT A SECOND ANSWER TO "how much room has this fleet". That question is answered ONCE,
 * by the server, and arrives as `FleetView.free_hold`; nothing may sum this function to reproduce
 * it. It exists because the server serves the free hold per FLEET and the ships table prints a
 * per-HULL column, which no RPC carries. The rejected alternative was to serve a per-ship
 * `free_hold` too: a second served number for the same rule is the duplication in a costlier
 * place, and the row already prints both terms of the subtraction beside it.
 */
export function shipHoldFree(ship: FleetShip): number {
  return Math.max(0, ship.hold - shipHoldUsed(ship))
}

/** What the fleet can hold when empty — a fold of the served STOWED capacities (0017:156), which
 *  the server does not total anywhere. It is the denominator of the hold gauge, never a term in
 *  "how much room is left": that is `fleet.free_hold`. */
export function fleetHoldTotal(fleet: FleetView): number {
  return fleet.ships.reduce((n, s) => n + s.hold, 0)
}

export function fleetHoldUsed(fleet: FleetView): number {
  return fleet.ships.reduce((n, s) => n + shipHoldUsed(s), 0)
}

/** The worst hull in the fleet — what a REPAIR order is really about. 1 when there are no hulls. */
export function worstHullFraction(fleet: FleetView): number {
  if (fleet.ships.length === 0) return 1
  return Math.min(...fleet.ships.map(hullFraction))
}

/**
 * THE ONE READING OF A FLEET'S HANDS. Every question a screen asks about crew is answered from
 * this single fold, because they were being answered from three:
 *
 *   berths  `features/command/fleetLimits.ts` folded `Σ max(0, crew_max − crew)` while
 *           `features/port/PortScreen.tsx` spelt the same thing `max(0, max − aboard)`. They are
 *           NOT the same function once a hull is over-crewed, and only one of them matches the
 *           server: `cmd.do_hire` raises E_CREW_MAX on `sum(c.crew_max - s.crew)` with no per-hull
 *           clamp at all (migration 0007:659). That is the spelling kept here.
 *   short   the hands HIRE naturally suggests, folded per hull because a hull that is over-crewed
 *           does not lend its surplus to a hull that is under-crewed.
 */
export interface CrewCount {
  aboard: number
  /** The complement below which a hull sails short-handed (the server's B.3 crew penalty). */
  required: number
  /** Berths in total — what the hulls were built to carry. */
  max: number
  /** Berths still empty — HIRE's ceiling, `sum(crew_max - crew)` exactly as E_CREW_MAX counts it. */
  berths: number
  /** Hands still needed to sail her at all — `Σ max(0, crew_required − crew)`. */
  short: number
}

export function fleetCrew(fleet: FleetView): CrewCount {
  const totals = fleet.ships.reduce(
    (acc, s) => ({
      aboard: acc.aboard + s.crew,
      required: acc.required + s.crew_required,
      max: acc.max + s.crew_max,
      short: acc.short + Math.max(0, s.crew_required - s.crew),
    }),
    { aboard: 0, required: 0, max: 0, short: 0 },
  )
  return { ...totals, berths: totals.max - totals.aboard }
}

export function fleetStores(fleet: FleetView): { waterT: number; foodT: number } {
  return {
    waterT: fleet.ships.reduce((n, s) => n + s.water_t, 0),
    foodT: fleet.ships.reduce((n, s) => n + s.food_t, 0),
  }
}

/** One good, folded across the hulls that carry it. */
export interface CargoLine {
  /** goods CODE — the key of `FleetShip.cargo`. */
  code: string
  /** UNITS aboard, as the cargo map counts them (NOT tuns: bulk is applied in `cargo_tuns`). */
  qty: number
}

/**
 * WHAT IS ABOARD, FOLDED ACROSS THE HULLS — the ONE fold, keyed by goods CODE.
 *
 * There were three. This one, `fleetLimits.cargoManifest` (the same fold, without the guard below,
 * so a hull carrying a zero-quantity key offered "SELL 0") and `fleetLimits.cargoAboard` (the same
 * fold again, for one code). A manifest is a property of a FLEET, not of the tab that offers a
 * SELL, so the two copies in the Command screen are deleted and everything reads this.
 *
 * `FleetShip.cargo` is `Record<goodCode, qty>` — a MAP, not the fixture's list of lots — so there
 * is no per-lot purchase price to fold and no average cost to report. That column is not served
 * (README §4.9); the price paid lives in the ledger's `BOUGHT` events, and the Ledger tab reads it.
 */
export function fleetCargoByCode(fleet: FleetView): Record<string, number> {
  const byGood: Record<string, number> = {}
  for (const ship of fleet.ships) {
    for (const [code, qty] of Object.entries(ship.cargo)) {
      // A key with nothing behind it is not a parcel. Dropping it here is what stops a SELL picker
      // listing a good the fleet does not carry.
      if (!Number.isFinite(qty) || qty <= 0) continue
      byGood[code] = (byGood[code] ?? 0) + qty
    }
  }
  return byGood
}

/** The same manifest as a stable, code-sorted list — what a cargo table prints. */
export function fleetCargo(fleet: FleetView): CargoLine[] {
  return Object.entries(fleetCargoByCode(fleet))
    .map(([code, qty]) => ({ code, qty }))
    .sort((a, b) => a.code.localeCompare(b.code))
}

/** The voyage's completion, 0–1, from the two served distances. Null when not at sea. */
export function voyageFraction(fleet: FleetView): number | null {
  const v = fleet.voyage
  if (!v) return null
  if (v.total_nm <= 0) return 1
  return Math.max(0, Math.min(1, v.nm_done / v.total_nm))
}

/** The arrival instant, in ms. `eta` is an ISO STRING (not ms) — Date.parse is the whole of it. */
export function voyageEtaMs(fleet: FleetView): number | null {
  const v = fleet.voyage
  if (!v) return null
  const ms = Date.parse(v.eta)
  return Number.isFinite(ms) ? ms : null
}

/** When a REPAIRING (or otherwise occupied) fleet comes free. Also an ISO string. */
export function busyUntilMs(fleet: FleetView): number | null {
  if (!fleet.busy_until) return null
  const ms = Date.parse(fleet.busy_until)
  return Number.isFinite(ms) ? ms : null
}

/**
 * The deepest hull in the fleet — what a port's `max_draft` gates (DESIGN C.3).
 *
 * Draft is a SHIP-CLASS fact and `FleetShip` does not carry it, so the caller supplies the lookup.
 * `FleetShip.class` is the class NAME (`Barca`), not its code — README §4.9.
 */
export function fleetMaxDraft(fleet: FleetView, draftOfClass: (className: string) => number | undefined): number {
  let deepest = 0
  for (const ship of fleet.ships) deepest = Math.max(deepest, draftOfClass(ship.class) ?? 0)
  return deepest
}
