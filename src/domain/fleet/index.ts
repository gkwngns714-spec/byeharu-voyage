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
// `lib/rpc` types, and nothing else. No React, no store, no screen, no other section.
export {
  busyUntilMs,
  fleetCargo,
  fleetCargoByCode,
  fleetCrew,
  fleetHoldTotal,
  fleetHoldUsed,
  fleetMaxDraft,
  fleetStatusTone,
  fleetStores,
  voyageEtaMs,
  hullFraction,
  shipHoldFree,
  shipHoldUsed,
  voyageFraction,
  worstHullFraction,
  type CargoLine,
  type CrewCount,
} from './derive'
