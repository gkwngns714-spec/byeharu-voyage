# 2026-10-18 — 0168: S4 + K10, a fight is read from the guns she carries (DARK) — `osn-s4-k10`

`docs/SHIPS_AND_GEAR.md` §4.4, §5 and §8 row S4 ("combat stats bite"); `docs/SKILLS_AND_CAPTAINS.md` §4.2,
§4.11, §5 and §8 row K10 ("combat traits, with S4 … lands in S4's own proof … S4's switch");
`docs/SHIPS_AND_SKILLS.md` §6.1 and §8 (S4 "stays where it was"). **Not deployed; dark** (`combat_bite`
false, `armour_turns_pct` 0). Migration number provisional (renumber to head + 1 at deploy). Cut against
main eb63be8 (head 0167). Every hunk checked to occur exactly once in production's live bodies (read-only
`pg_get_functiondef` through `db query --linked`, 2026-10-18: `voyage.settle`, `world.ship_stats`,
`public.crew_pct`, `world.captain_card`); the local chain's four bodies have the same md5 as production's.

## The owner's law this slice sits under

Text and tabs; no visual combat, ever; the map only shows. The game already has combat in that sense:
`voyage.settle`'s PIRATES arm (DESIGN B.6), a probability table resolved on the server and reported as
prose. S4 changes **what that table reads**. No verb, no screen, no map change and no new kind of fight
is added.

## What was built

| Concept | Its one home | Dark (today) | Lit |
|---|---|---|---|
| the switch | `world_config combat_bite` (false), read by `public.combat_bite_on()` (inlinable) | — | one UPDATE |
| the escort score | `voyage.escort_score(fleet)` — moved out of settle's PIRATES arm, as `voyage.storm_hull_lost` was out of STORM (0154) | DESIGN B.6's Σ(guns + crew × 0.02 + tier × 3), verbatim | Σ(`world.ship_stat` attack / 10 + crew × 0.02 + tier × 3): her gear, her company's attack skills, and the Boarder count |
| the armour rule | `public.armour_turns(ship, loss)`, read by settle's STORM arm and its raid | knob 0: the loss itself (same numeric) | loss × (1 − armour / 100 × `armour_turns_pct`), ≥ 0, to the hundredth |
| a ship effect of a captain | `public.crew_pct(fleet, ship, effect)` (the one reader since 0157) | refused `E_NOT_YET`, as before | the captains seated on THAT ship, capped, Command-lifted |
| the captains' share of a hull | `public.ship_crew_terms(ship, stats)`, called by `world.ship_stats` (both branches) | the stats untouched | accuracy / reach / attack × (1 + share), rounded to the stat's scale, applied last (as `ship_hold_capacity` applies the Quartermaster) |
| the card's words | `world.captain_card` | "Works when combat arrives." | not served for a combat trait |

`ship_classes.guns` is now commented as a data mirror of attack / 10 (asserted for every class).

**Why a switch S4's own row does not have.** SHIPS_AND_GEAR wrote S4 as "a proven no-op for every unfitted
hull", which it is. But 784 of the 850 fleets in the cached world carry attack gear (S2's merchant
loadouts mount broadside guns), so the escort — and so the outcome of almost every merchant's pirate day —
would move the moment it landed. SKILLS_AND_CAPTAINS §4.11 already names "S4's combat switch"; this is it.

## Proof (PGlite on the cached 0167 world; rolled back; one statement each)

- **Dark, every row**: 908 hulls — `ship_stats`, `ship_view`, a storm's loss (magnitude 0.5) and a raid's
  three outcomes as `numeric(8,2)` = the old bodies'; 850 fleets — escort = DESIGN B.6's to the digit;
  9,524 `crew_pct` outcomes (every fleet × fleet effect, every ship × ship effect) the same answer or the
  same refusal; 105 captain cards the same; `guns` = attack / 10 for every class.
- **Lit, own company** (Casa das Armas, Lisbon, the barca it was founded with + a nau): unfitted escort
  25.36 lit = dark to 4 places; broadside guns on the nau through `cmd.do_fit` — dark 25.36, lit 31.36
  (+ 60 / 10); Turgut Reis (Boarder) in the nau's Captain's cabin: with `crew_bite` off nothing (a combat
  job is no live effect), with it on attack 180.00 → 196.20 (share 9 %), the barca untouched, escort 32.98,
  her card's note gone, and back when combat is off (stats = old body, `crew_pct` refused again); Tartaglia
  (Gunner) in the nau's Captain's cabin, the Boarder ashore: accuracy 55 → 57, reach 85.00 → 88.83, attack
  unmoved; armour at 0.5: a loss of 100 → 85.00 on the nau (armour 30), 97.50 on the barca (armour 5).
- **Readers**: settle reads no `guns`; `escort_score` and `armour_turns` are read by settle alone,
  `ship_crew_terms` by `ship_stats` alone (a planted reader is seen); 4 bodies reverse to their
  pre-images with ACL / volatility / definer / config unmoved; 9 neighbours untouched; no entry point.
- **Timings (notice only)**: escort over 837 merchant fleets 10 → 20 ms (the function call),
  merchant ship_stats 129 → 94 ms, speed + hold 448 → 427 ms (noise both ways).

**Read-only on production (2026-10-18, the comparison selection, inside `begin transaction read only` with
the result raised):** 912 hulls answered ship_stats + ship_view with no refusal (15.0 s — so the
migration does not time ship_view a second time); 854 fleets' escort; 6,832 fleet-effect `crew_pct`
answers and 2,736 ship-effect refusals, all `P0001 E_NOT_YET` (912 × accuracy / reach / attack);
105 captain cards, no refusal; `guns` = attack / 10 for every class; the two knobs absent (they land);
LIS, Turgut Reis and Tartaglia present; the probe's company id unused.

## Not in this slice — and what combat itself would still need (NOT the owner's — confirm)

- **Accuracy, reach and sighting feed no roll.** §4.4: the roll has no "shot tells" or range step. So the
  Gunner's accuracy and reach show on the ship and change no outcome. A roll that reads them is a rule
  the owner has not asked for.
- **Gear actives** (SHIPS_AND_SKILLS §6.1: a module works on its trigger day, spends its consumable —
  shot and powder a fight — and works at half without it; `gear_actives_bite`). The plan ties them to "S4
  and the hazard re-cut", and the hazard re-cut has no row. `item_use` (0158) records triggers and
  consumables; nothing spends them.
- **Trait actives with trigger = PIRATES** (SKILLS_AND_CAPTAINS §4.11, "Origin's combat actives"). No such
  trait or value is authored; Origin's are hex-board battle moves, which this game forbids. None invented.
- **SHOAL_WATER** keeps its loss un-armoured (S4 names storm and raid).
- **The raider side** is unchanged: `piracy_index × 40 × (0.5 + magnitude)`. Lit, every fleet with gear is
  harder to take than today; whether the raiders should grow to match is a balance call (measure it on
  the canary world before lighting — SHIPS_AND_GEAR §8 asked for "a week of S3's numbers").
- **Client**: nothing to change. The ship panel already prints the six combat figures; the trait card
  prints the server's note; `statGloss.ts` has no attack / armour line (the plan's "stop saying unused"
  has nothing to stop) and its guns / hull lines stay true either way.
- No generator or world-guard change: S4 and K10 add no catalogue row (two knobs, functions and hunks).
  `data/captains.json`'s `_effects` note says how a ship effect is now read.

## Lighting it (the owner's call)

`update public.world_config set value = 'true' where key = 'combat_bite';` — the escort reads what she
carries; the Gunner and Boarder count where `crew_bite` is on. `… value = '0.5' where key =
'armour_turns_pct'` turns half of armour's share. Off again is the same UPDATE back.
