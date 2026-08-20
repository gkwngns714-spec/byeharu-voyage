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
// already say" — free hold, crew aboard against berths, worst hull, stores, cargo lines, the
// draught the shallowest port must clear. If a rule ever needs enforcing, it belongs in the chain,
// not here.
//
// ── WHAT IT MAY DEPEND ON ──────────────────────────────────────────────────────────────────────
// `lib/rpc` types, and nothing else. No React, no store, no screen, no other section.
export {
  busyUntilMs,
  fleetCargo,
  fleetCrew,
  fleetHoldFree,
  fleetHoldTotal,
  fleetHoldUsed,
  fleetMaxDraft,
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
