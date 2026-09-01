// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHAT DOES THIS CITY KEEP? — the one answer, for every screen that asks.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner: *"buildings are market, a workstation where you can create ship related items - sail
// etc. inn where you can hire crew, find captains. etc. it is a concept."*
//
// ── WHY THIS MODULE EXISTS AT ALL ──────────────────────────────────────────────────────────────
// Before 0067 the answer was a boolean read by hand in three different files: `PortScreen` decided
// whether to show the Academy face with `f.id !== 'academy' || port.has_academy`, `FleetRail`
// decided whether REPAIR was worth offering with `port.has_yard`, and `ArgPickers` printed
// " · shipyard" from the same field. Three copies of one question, and the owner has asked for four
// more buildings — a warehouse, a workstation, a building yard and an Inn. Four more buildings
// against three hand-written copies is twelve.
//
// So the question gets ONE implementation, here, and the screens compose it. This is
// docs/NO_SPAGHETTI.md §7B answered before the second caller arrived rather than after: the second
// caller is `FleetRail`, and it already exists.
//
// ── WHY IT READS ROWS AND NOT THE BOOLEANS ─────────────────────────────────────────────────────
// `has_yard` and `has_academy` are still the AUTHORED truth — they live in `data/ports.json` and
// world-guard holds the applied world equal to that file in both directions. Migration 0067 derives
// them into `port_buildings` rows and proves the two equal in both directions, so reading the rows
// says exactly what reading the booleans said today.
//
// It will not stay that way, and that is the point: a warehouse a player builds, and a workstation
// tier a player raises, have nowhere to live in a boolean. From here the row is what the game reads.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import type { BuildingKind, PortBuilding, SnapshotPort } from '../../lib/rpc'

/** Just enough of a port to answer the question — so a caller holding a partial row can still ask. */
type Keeper = Pick<SnapshotPort, 'buildings'>

/**
 * Does this city keep one of these? A city that keeps nothing at all answers `false` rather than
 * throwing: a SEA_PLACE has no shore (0036) and legitimately keeps nothing.
 */
export function hasBuilding(port: Keeper | null | undefined, kind: BuildingKind): boolean {
  return (port?.buildings ?? []).some((b) => b.kind === kind)
}

/**
 * How good is this city at it, or 0 where it does not keep one. Callers that care about a tier
 * almost always care about "at least this good", so 0 is the honest answer for absent rather than
 * `null` — it compares the way the caller wants to compare.
 */
export function buildingTier(port: Keeper | null | undefined, kind: BuildingKind): number {
  return (port?.buildings ?? []).find((b) => b.kind === kind)?.tier ?? 0
}

/**
 * Everything this city keeps, in the server's own order. The server sorts by
 * `building_kinds.sort`, so the list reads the same on every screen without any screen owning an
 * opinion about the order.
 */
export function buildingsOf(port: Keeper | null | undefined): readonly PortBuilding[] {
  return port?.buildings ?? []
}
