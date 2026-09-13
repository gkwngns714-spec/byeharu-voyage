// WHAT EACH SHIP FIGURE DECIDES — one sentence per stat, written once, composed everywhere.
//
// ── WHY THIS TABLE EXISTS (2026-08-23) ──────────────────────────────────────────────────────────
// The owner saw `DRAFT 5` on PORT — no unit, no consequence — and asked the right question about
// every other figure too: HOLD, CREW, SPEED, HULL, GUNS, DRAFT, BUILD, COST were all printed as
// bare numbers under one-word headings, and nothing on any screen said what any of them decides.
// Three screens print these columns (COMPENDIUM's ships face, FLEETS' ships table, PORT's
// Alongside table and its draft badge), so the sentence for each stat is written HERE, once, and
// every surface composes it — two screens each explaining draft in their own words would be two
// authorities for one sentence, which is docs/NO_SPAGHETTI.md §1's disease.
//
// ── EVERY LINE BELOW CITES THE RULE THAT MAKES IT TRUE ──────────────────────────────────────────
// Verified against the chain on 2026-08-23, each stat traced to the function that reads it:
//
//   hold    public.fleet_free_hold (0007:127), ship_hold_effective (0017:168) — what a BUY is
//           checked against; and the LOAD term of voyage.ship_speed (0006:351): a full hold slows.
//   crew    E_CREW_SHORT refuses SAIL below complement (0007:371, re-cut 0019:424); crew lost at
//           sea puts M_crew = crew_short_speed_mult on the speed (0006:355); crew_max bounds HIRE
//           (cmd.do_hire, 0007:659); crew is also a term of the escort score (0007:979).
//   speed   the base of voyage.ship_speed (0006:359); voyage.fleet_speed takes the fleet at the
//           SLOWEST hull with a formation penalty (0006:363+).
//   hull    durability: the hull factor of speed (0006:353), what storms and pirates subtract
//           (0007:961, 0027:317), what REPAIR restores (0007:724-742), and the flagship-at-zero
//           E_FLAGSHIP_DISABLED gate on SAIL (0007:375-377).
//   guns    escort_score = Σ(guns + crew×0.02 + tier×3) — the game's whole combat number
//           (0007:979, re-cut 0027:334-335; DESIGN B.6).
//   draft   the deepest hull's draft against public.ports.max_draft — the E_DRAFT gate on SAIL
//           (voyage.sail_refusal, re-cut 0050). The refusal now SERVES the two numbers as figures
//           (port depth over hull draft), so nothing quotes its sentence here: a number in a
//           comment is a liability the day the sentence changes, which is today.
//   tier    the third term of the escort score (0007:979), and the catalogue's ladder (0009:97).
//   build   ship_classes.build_hours — NO RULE READS IT. Table 0002:161 and the seed only;
//           0021:50 states it: "There is no verb that adds a hull today."
//   cost    ship_classes.build_cost — NO RULE READS IT. Table 0002:162 and the seed only.
//   rig     a check constraint (0002:153) and nothing else — DESIGN B.5 means it to pick the wind
//           multiplier, but wind is pinned at wc 'wind_mult_v0' = 1.00 (0006:357-359).
//   family  a column (0002:152) read by no rule; the catalogue groups by it, which is
//           presentation, not a rule.
//
// ── THE HONESTY RULE, AND ITS LIMIT ─────────────────────────────────────────────────────────────
// A stat no rule reads is SAID to be read by nothing — in its own sentence, the same reading the
// compendium's captains face gives an officer whose `takes_effect` is false and PORT's city face
// gives the garrison figure. BUILD, COST and RIG/FAMILY are those stats today. But note the limit:
// officers and skills carry a SERVED flag (world.officers().specialties_read, 0015:304), and ship
// stats have no such flag, so these three sentences are a hand-checked claim about the chain as of
// 2026-08-23, not the server saying so. The proper fix is served — a `ship_stats_read` list on the
// snapshot beside `ship_classes`, asserted by the migration whose rules read them — and this file
// is the ONLY place the claim lives so that one served field can replace it in one edit. Do NOT
// grow this into a live/dead boolean the UI branches on: that would be a client-side authority for
// a fact the server owns.
//
// Pure data — no React, no store. `StatLegend` (design system) is the one chrome that renders a
// list of these; screens pass `shipStatItems([...])` to it.

/** One stat's reading: the word a column prints, the unit it is counted in, what it decides. */
export interface ShipStatGloss {
  /** The column's own one-word name (labels are names, not sentences). */
  term: string
  /** What the figure is counted in — null for a plain count or rating. */
  unit: string | null
  /** ONE line: the rule that reads this figure, or the honest fact that none does. */
  line: string
}

export const SHIP_STATS = {
  tier: {
    term: 'tier',
    unit: null,
    line: 'The ship’s class rating — also counts toward the fleet’s defence when pirates attack.',
  },
  hold: {
    term: 'cargo',
    unit: 'tons',
    line: 'How much it can carry. Cargo, water and food share this space, and a fuller ship sails slower.',
  },
  crew: {
    term: 'crew',
    unit: 'needed / max',
    line: 'Below the first number the ship cannot sail, and crew lost at sea slow it down; the second is the most it can carry.',
  },
  speed: {
    term: 'speed',
    unit: 'knots',
    line: 'Speed in good condition — damage, a full cargo and missing crew all lower it, and a fleet sails at its slowest ship’s speed.',
  },
  guns: {
    term: 'guns',
    unit: 'broadside pieces',
    line: 'Guns and crew decide how a pirate attack goes: together they make the fleet’s defence, weighed against the pirates of that sea.',
  },
  hull: {
    term: 'hull',
    unit: 'points',
    line: 'How much damage it can take from storms and pirates. A damaged ship slows down, and a flagship at zero keeps its whole fleet in port until repaired.',
  },
  draft: {
    term: 'draft',
    unit: null,
    line: 'How deep the water must be. Each port has a depth limit — a fleet with a ship deeper than that cannot enter.',
  },
  build: {
    term: 'build',
    unit: 'hours',
    line: 'How long the shipyard takes to build it. Nothing uses this number yet.',
  },
  cost: {
    term: 'cost',
    unit: 'ducats',
    line: 'What the shipyard charges to build it. Nothing uses this number yet.',
  },
  lineage: {
    term: 'family · rig',
    unit: null,
    line: 'Ship type and sail plan. The rig is meant to affect how it uses the wind, but wind is not in the game yet — nothing uses either.',
  },
  /** FLEETS' and PORT's per-hull columns — derived here on the client (shipHoldUsed/shipHoldFree),
   *  so their sentences live beside the hull stats they are made of. */
  load: {
    term: 'load',
    unit: 'tons',
    line: 'What this ship carries right now — trade goods plus the water and food that share the space.',
  },
  free: {
    term: 'free',
    unit: 'tons',
    line: 'Space left in this ship. A purchase is checked against the whole fleet’s free space, which the server works out.',
  },
} as const satisfies Record<string, ShipStatGloss>

export type ShipStatKey = keyof typeof SHIP_STATS

/** The glosses for one surface's columns, in that surface's own column order. */
export function shipStatItems(keys: readonly ShipStatKey[]): ShipStatGloss[] {
  return keys.map((k) => SHIP_STATS[k])
}
