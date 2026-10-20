// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE FLEET — what a hull, a crew and a hold add up to
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A SECTION, NOT A SCREEN. This was `features/fleets/fleetDerive.ts`, which made the Fleets tab the
// owner of arithmetic the Port tab and the order composer also need — "how much hold is free" is a
// property of a fleet, not of a screen that happens to draw one.
//
// EVERY FUNCTION HERE IS PURE AND DERIVES FROM A SERVED PAYLOAD. Nothing in this section decides
// anything: the server owns whether an order is legal, and these answer "what does this FleetView
// already say" — crew aboard against berths, worst hull, stores, cargo lines, the draught the
// shallowest port must clear. If a rule ever needs enforcing, it belongs in the chain, not here.
//
// ── THE ONE THING THIS SECTION DELIBERATELY DOES NOT EXPORT ────────────────────────────────────
// "How much room is left in this fleet." That is `FleetView.free_hold`, served by
// `public.fleet_free_hold` (migration 0017:183) — READ THE FIELD. The three client functions that
// answered it (one of them wrongly, for its whole life) are deleted; derive.ts's header records
// which they were and why none of them comes back.
//
// ── WHAT IT MAY DEPEND ON ──────────────────────────────────────────────────────────────────────
// `lib` (rpc types, format, geo), and nothing else. `domain/passage` composes THIS section (its
// `sailOrigin` reads `whereabouts`), so this one must never import it back. No
// React, no store, no screen.
export {
  busyUntilMs,
  fleetCargo,
  fleetCargoByCode,
  fleetCrew,
  fleetHoldTotal,
  fleetHoldUsed,
  // WHERE HER NEXT ORDER HAPPENS — the one answer, for the four places that spelt it out inline.
  fleetPortCode,
  // THE REFUSED ORDER IN HER QUEUE, and the one-word signal (sailing · waiting · stuck) a picker's
  // dot draws — the queue's halt note and the dot read the same row.
  fleetRefusedOrder,
  fleetSignal,
  fleetStatusTone,
  fleetStores,
  housePortCode,
  // WHAT SHE PAID PER TUN for a good aboard — the one reading of the served `cargo_basis` (0081).
  paidPerTun,
  voyageEtaMs,
  hullFraction,
  shipHoldFree,
  shipHoldUsed,
  voyageFraction,
  worstHullFraction,
  type CargoLine,
  type CrewCount,
  type FleetSignal,
} from './derive'

// WHERE SHE IS — the one classification (at sea / in port / at anchor) and the one line about it,
// for the nine places that spelt it out themselves (where.ts's header lists them).
export {
  alongsideAt,
  boundForLabel,
  isDockedAt,
  joinPieces,
  whereabouts,
  whereLine,
  whereParts,
  type WhereFacts,
  type Whereabouts,
  type WherePiece,
} from './where'

// WHAT EACH SHIP FIGURE DECIDES — the one sentence per stat that COMPENDIUM, FLEETS and PORT all
// compose. It lives in this section because what a stat decides is a fact about the fleet rules,
// not about any screen that prints one (statGloss.ts's header carries the citations).
export { SHIP_STATS, shipStatItems, type ShipStatGloss, type ShipStatKey } from './statGloss'
