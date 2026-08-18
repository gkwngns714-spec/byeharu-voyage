// FLEET DERIVATION — one authority for speed, endurance, hold and voyage progress. Pure: no
// React, no DOM, no clock (an instant is always passed in).
//
// Every formula below is transcribed from DESIGN.md and cited to its section. Nothing here is
// invented: if a number cannot be traced to a formula in the document it does not belong in this
// file, and a screen that wants such a number is asking the wrong question.
//
// V0 SIMPLIFICATIONS, stated once so no reader has to infer them (K.1 "Not in V0"):
//   M_wind    = 1.00  — wind ships at V1.
//   M_officer = 1.00  — no officers at V0.
//   M_control = 1.00  — no investment, so no regional control bonus.
// The terms are still written into speedOfShip() as named constants rather than deleted, because
// deleting a term is how a formula quietly forks when the feature arrives.

import type { CargoLot, Fleet, PortCode, Ship, ShipClass, Voyage } from '../../fixtures/types'
import { realMsToVoyageDays, voyageDaysToRealMs } from '../../lib/format'
import type { LegGraph } from '../command/geo'
import { pathLengthNm, positionOnRoute } from '../command/geo'

/** C.5 — per voyage-day, per crewman, in tuns. */
export const WATER_PER_CREW_DAY = 0.02
export const FOOD_PER_CREW_DAY = 0.015
/** C.5 — one ducat per crewman per voyage-day. */
export const WAGE_PER_CREW_DAY = 1

/** C.5 / F.2 — SAIL refuses to queue below this multiple of the voyage length. */
export const ENDURANCE_SAFETY_MARGIN = 1.15

export const M_WIND_V0 = 1.0
export const M_OFFICER_V0 = 1.0
export const M_CONTROL_V0 = 1.0

export function cargoTuns(cargo: readonly CargoLot[]): number {
  return cargo.reduce((sum, lot) => sum + lot.tuns, 0)
}

/** Everything aboard: trade cargo plus the water and food that compete with it for the same hold.
 *  C.3: "Every tun of water is a tun of pepper you did not carry." */
export function holdUsed(ship: Ship): number {
  return cargoTuns(ship.cargo) + ship.waterT + ship.foodT
}

export function holdFree(ship: Ship, cls: ShipClass): number {
  return Math.max(0, cls.hold - holdUsed(ship))
}

export function fillFraction(ship: Ship, cls: ShipClass): number {
  return cls.hold <= 0 ? 0 : Math.min(1, holdUsed(ship) / cls.hold)
}

/** B.3 — 0.60 + 0.40 x (durability / max_durability). */
export function mHull(ship: Ship, cls: ShipClass): number {
  return 0.6 + 0.4 * (ship.durability / cls.maxDurability)
}

/** B.3 — 1.00 - 0.25 x cargo_fill_fraction. */
export function mLoad(ship: Ship, cls: ShipClass): number {
  return 1 - 0.25 * fillFraction(ship, cls)
}

/** B.3 — 1.00 with a full complement, 0.70 short-handed. */
export function mCrew(ship: Ship, cls: ShipClass): number {
  return ship.crew >= cls.crewRequired ? 1.0 : 0.7
}

/** B.3 — 1.00 for 3 ships or fewer, 0.98 for 4-6, 0.95 for 7 or more. */
export function mFormation(shipCount: number): number {
  if (shipCount >= 7) return 0.95
  if (shipCount >= 4) return 0.98
  return 1.0
}

/** B.3 — the whole v_eff product for one hull, in knots. */
export function speedOfShip(ship: Ship, cls: ShipClass): number {
  return (
    cls.speedKn *
    M_WIND_V0 *
    mHull(ship, cls) *
    mLoad(ship, cls) *
    mCrew(ship, cls) *
    M_OFFICER_V0 *
    M_CONTROL_V0
  )
}

/** C.4 — "Fleet speed = the slowest ship", then the formation penalty. */
export function fleetSpeedKn(ships: readonly Ship[], classOf: (s: Ship) => ShipClass): number {
  if (ships.length === 0) return 0
  const slowest = Math.min(...ships.map((s) => speedOfShip(s, classOf(s))))
  return slowest * mFormation(ships.length)
}

/** C.5 — a single hull's range in voyage-days, whichever store runs out first. */
export function shipEnduranceDays(ship: Ship): number {
  if (ship.crew <= 0) return Infinity
  return Math.min(
    ship.waterT / (ship.crew * WATER_PER_CREW_DAY),
    ship.foodT / (ship.crew * FOOD_PER_CREW_DAY),
  )
}

/** C.4 — "Fleet endurance = the shortest-ranged ship." Stores are pooled but each hull carries
 *  its own, so the fleet stops when the first ship is empty. */
export function fleetEnduranceDays(ships: readonly Ship[]): number {
  if (ships.length === 0) return 0
  return Math.min(...ships.map(shipEnduranceDays))
}

/** C.3 — derived, never authored: 0.4 x (durability/1000) + 0.6 x (hold/500). */
export function seaworthiness(ship: Ship, cls: ShipClass): number {
  return 0.4 * (ship.durability / 1000) + 0.6 * (cls.hold / 500)
}

/** C.5 — what a fleet burns per voyage-day. */
export interface DailyBurn {
  waterT: number
  foodT: number
  wagesDucats: number
  crew: number
}

export function dailyBurn(ships: readonly Ship[]): DailyBurn {
  const crew = ships.reduce((n, s) => n + s.crew, 0)
  return {
    crew,
    waterT: crew * WATER_PER_CREW_DAY,
    foodT: crew * FOOD_PER_CREW_DAY,
    wagesDucats: crew * WAGE_PER_CREW_DAY,
  }
}

/** B.3 — nautical miles at a fleet speed, in voyage-days. */
export function voyageDaysFor(totalNm: number, speedKn: number): number {
  if (speedKn <= 0) return Infinity
  return totalNm / speedKn / 24
}

/** The live state of a fleet at sea. D.2: position is a PURE FUNCTION of departure, not a
 *  simulated value — which is why this takes `nowMs` and holds nothing. */
export interface VoyageProgress {
  totalNm: number
  coveredNm: number
  remainingNm: number
  fraction: number
  totalVoyageDays: number
  etaMs: number
  remainingMs: number
  arrived: boolean
  fromPort: PortCode
  toPort: PortCode
  /** The destination — the last port on the path. */
  destination: PortCode
  /** The leg currently being sailed, for the "812/1007 nm" readout. */
  legCoveredNm: number
  legTotalNm: number
}

export function voyageProgress(
  graph: LegGraph,
  voyage: Voyage,
  nowMs: number,
): VoyageProgress {
  const totalNm = pathLengthNm(graph, voyage.path)
  const elapsedDays = realMsToVoyageDays(Math.max(0, nowMs - voyage.departedAtMs))
  const coveredNm = Math.min(totalNm, elapsedDays * 24 * voyage.speedKn)
  const totalVoyageDays = voyageDaysFor(totalNm, voyage.speedKn)
  const etaMs = voyage.departedAtMs + voyageDaysToRealMs(totalVoyageDays)
  const leg = positionOnRoute(graph, voyage.path, coveredNm)
  return {
    totalNm,
    coveredNm,
    remainingNm: Math.max(0, totalNm - coveredNm),
    fraction: totalNm <= 0 ? 1 : coveredNm / totalNm,
    totalVoyageDays,
    etaMs,
    remainingMs: Math.max(0, etaMs - nowMs),
    arrived: nowMs >= etaMs,
    fromPort: leg?.fromPort ?? voyage.path[0],
    toPort: leg?.toPort ?? voyage.path[voyage.path.length - 1],
    destination: voyage.path[voyage.path.length - 1],
    legCoveredNm: leg?.legCoveredNm ?? 0,
    legTotalNm: leg?.legTotalNm ?? 0,
  }
}

/** The roster row the FLEETS tab prints, and the object the CMD validator checks against. */
export interface FleetView {
  fleet: Fleet
  ships: readonly Ship[]
  shipCount: number
  flagship: Ship | null
  crew: number
  crewRequired: number
  crewMax: number
  speedKn: number
  enduranceDays: number
  holdTotal: number
  holdUsed: number
  holdFree: number
  /** Fleet-wide hull condition, 0-1, weighted by nothing: the worst hull is what matters. */
  worstHullFraction: number
  flagshipDisabled: boolean
  progress: VoyageProgress | null
  burn: DailyBurn
  /** Deepest draft in the fleet — what gates a port (C.3). */
  maxDraft: number
}

export function buildFleetView(
  fleet: Fleet,
  ships: readonly Ship[],
  classOf: (s: Ship) => ShipClass,
  graph: LegGraph,
  nowMs: number,
): FleetView {
  const mine = ships.filter((s) => s.fleetId === fleet.id)
  const flagship = mine.find((s) => s.isFlagship) ?? null
  return {
    fleet,
    ships: mine,
    shipCount: mine.length,
    flagship,
    crew: mine.reduce((n, s) => n + s.crew, 0),
    crewRequired: mine.reduce((n, s) => n + classOf(s).crewRequired, 0),
    crewMax: mine.reduce((n, s) => n + classOf(s).crewMax, 0),
    speedKn: fleetSpeedKn(mine, classOf),
    enduranceDays: fleetEnduranceDays(mine),
    holdTotal: mine.reduce((n, s) => n + classOf(s).hold, 0),
    holdUsed: mine.reduce((n, s) => n + holdUsed(s), 0),
    holdFree: mine.reduce((n, s) => n + holdFree(s, classOf(s)), 0),
    worstHullFraction:
      mine.length === 0 ? 1 : Math.min(...mine.map((s) => s.durability / classOf(s).maxDurability)),
    flagshipDisabled: flagship !== null && flagship.durability <= 0,
    progress: fleet.voyage ? voyageProgress(graph, fleet.voyage, nowMs) : null,
    burn: dailyBurn(mine),
    maxDraft: mine.length === 0 ? 0 : Math.max(...mine.map((s) => classOf(s).draft)),
  }
}

/** What a fleet is carrying, folded across its hulls — the Fleets tab's cargo block. */
export function fleetCargo(ships: readonly Ship[]): readonly CargoLot[] {
  const byGood = new Map<string, { good: CargoLot['good']; tuns: number; cost: number }>()
  for (const ship of ships) {
    for (const lot of ship.cargo) {
      const acc = byGood.get(lot.good) ?? { good: lot.good, tuns: 0, cost: 0 }
      acc.tuns += lot.tuns
      acc.cost += lot.tuns * lot.avgCost
      byGood.set(lot.good, acc)
    }
  }
  return [...byGood.values()].map((a) => ({
    good: a.good,
    tuns: a.tuns,
    avgCost: a.tuns > 0 ? a.cost / a.tuns : 0,
  }))
}
