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
//
// A second implementation of a served number is a second authority, and the server's is the one
// the game obeys — SAIL refuses on ITS endurance figure, not on ours. So the old file was DELETED
// rather than reconciled. Nothing here re-derives a field the RPC carries.
//
// ── WHAT IS LEFT ────────────────────────────────────────────────────────────────────────────────
// Arithmetic the server does not serve as a field, composed only from fields it does: a ratio, a
// subtraction, a fold across the hulls of one fleet. Each function names the SQL it agrees with,
// so a migration that changes the rule has one place on this side to change with it.
//
// Pure: no React, no clock (an instant is always passed in), no fixtures.

import type { FleetShip, FleetView } from '../../lib/rpc'

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

/** Room for the next parcel, per hull. Mirrors `public.fleet_free_hold` (0007:127) term for term;
 *  if the two ever disagree the server's answer is the one BUY obeys. */
export function shipHoldFree(ship: FleetShip): number {
  return Math.max(0, ship.hold - shipHoldUsed(ship))
}

export function fleetHoldTotal(fleet: FleetView): number {
  return fleet.ships.reduce((n, s) => n + s.hold, 0)
}

export function fleetHoldUsed(fleet: FleetView): number {
  return fleet.ships.reduce((n, s) => n + shipHoldUsed(s), 0)
}

export function fleetHoldFree(fleet: FleetView): number {
  return fleet.ships.reduce((n, s) => n + shipHoldFree(s), 0)
}

/** The worst hull in the fleet — what a REPAIR order is really about. 1 when there are no hulls. */
export function worstHullFraction(fleet: FleetView): number {
  if (fleet.ships.length === 0) return 1
  return Math.min(...fleet.ships.map(hullFraction))
}

export interface CrewCount {
  aboard: number
  /** The complement below which a hull sails short-handed (the server's B.3 crew penalty). */
  required: number
  /** Berths — what HIRE can fill up to. */
  max: number
}

export function fleetCrew(fleet: FleetView): CrewCount {
  return fleet.ships.reduce<CrewCount>(
    (acc, s) => ({
      aboard: acc.aboard + s.crew,
      required: acc.required + s.crew_required,
      max: acc.max + s.crew_max,
    }),
    { aboard: 0, required: 0, max: 0 },
  )
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
 * What a fleet is carrying, folded. `FleetShip.cargo` is `Record<goodCode, qty>` — a MAP, not the
 * fixture's list of lots — so there is no per-lot purchase price to fold and no average cost to
 * report. That column is not served (README §4.9); the price paid lives in the ledger's `BOUGHT`
 * events, and the Ledger tab is where it is read.
 */
export function fleetCargo(fleet: FleetView): CargoLine[] {
  const byGood = new Map<string, number>()
  for (const ship of fleet.ships) {
    for (const [code, qty] of Object.entries(ship.cargo)) {
      if (!Number.isFinite(qty) || qty <= 0) continue
      byGood.set(code, (byGood.get(code) ?? 0) + qty)
    }
  }
  return [...byGood.entries()]
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
