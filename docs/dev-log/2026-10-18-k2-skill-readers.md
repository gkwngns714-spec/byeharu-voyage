# 2026-10-18 — 0154: K2, a skill is paid where the game charges — `osn-k2-skill-readers`

`docs/SKILLS_AND_CAPTAINS.md` §3.3 ("Lifted means one authority first") / §8 row K2. **Not deployed; dark**
(`skills_bite` stays false). Migration number provisional (renumbered 0153 → 0154 after 0152 towing and 0153 hull tie-break; renumber again to head + 1 if needed).
Applies on 0153 (hull tie-break), after K1 (0151). Bodies sliced from prod head 0151 (re-hashed at head 0153: unchanged) (`pg_get_functiondef`, read-only): the 20 bodies this file
reads hash-equal on prod and on the chain.

- **The lifts, one reading per cost** (each = today's figure for every company, proven old vs new, dark and lit):
  `public.fleet_wage(fleet, short, crew)` (settle charges it, `world.crew_cost` quotes it, `cmd.do_dismiss`
  reports it; crew_wages × running_cost_mult), `public.crew_hire_cost(fleet, n)` (`cmd.do_hire`'s split and price,
  lifted; the Inn's price is `cmd.preview` of that door), `public.captain_wage(player, officer)` (`sign_officer`
  charges, `world.inn` / `world.officers` print), `public.yard_labour(player, class)` (`cmd.do_build` charges,
  `world.building_yard` prints; composes 0135's `hull_labour`), `public.standing_route_max_for(player)` (the cap
  trigger and `world.standing_routes.max`), `voyage.day_delay_for(voyage, kind, magnitude, prior)` (settle's
  STORM / CALM / FAIR_WIND arms and `voyage.arrival_at` — the predicted arrival and the settled one stay one rule),
  `voyage.storm_hull_lost(voyage, maxd, magnitude)` (the STORM arm).
- **The terms** (dark): Factorage +1 route/level, Pursership −3 % wages, Etiquette −4 % hiring, Recruiting −5 %
  captain wage, Shipwright −3 % yard labour (new effect row; the house CHECK re-made for `yard_labour`; data in
  `data/skills.json`), Weather Lore −4 % storm hull, Light-air −5 % calm delay — the last two at the voyage's
  departure. All through the one reading: `world.skill_bonuses_at(player, ship, at)` is made from the live
  `world.skill_bonuses` body with its two time reads at `p_at`; `world.skill_bonuses` / `world.skill_pct` are that
  reading at now() (proven row for row over every house and hull). Words: "+2 routes", "−15% crew wages",
  "−8% crew hiring", "−15% captain wages", "−6% yard labour", "−12% storm damage", "−10% time lost in a calm".
- **Proof** (local chain; also on a prod-like local world: treasury + influence lit, 80 merchant voyages at sea):
  every fleet's wage, quote and hire, every house × officer and × hull, every route cap, every house / hull
  reading, every voyage's predicted arrival / storm loss / day delay, 865 effect words and 356 screen reads (as
  nobody and as every human house) — old vs new, dark and lit, 0 differ. Probe houses build their own state: old
  door = new door (hire, signing, dismiss, a 48-day passage with storms and calms, found by re-departing until the
  sky holds both); lit, each term exactly its per cent, door = screen, predicted arrival = settled, two sittings =
  one. Timing (notice): K0's merchant reads lit before/after this file 645 → 577 ms (speed + cargo), 1,321 →
  1,159 ms (ship_view); merchant wages old 75, new dark 69, new lit 119 ms (K0's bound 129).
- **Said plainly**: the merchant planner's estimates (`npc_leg_lines`' crew_wages, `npc_found`'s wage budget) are
  untouched — a merchant holds no house skill (asserted), so its estimate and its charge stay equal. A level is read
  at departure through `skill_level_at`, which counts a `player_skills` row by its level: a level folded into
  `player_skills` mid-passage (by `skill_queue_set`) counts for the days settled after the fold. Brokerage and
  Patronage are K2b; Leadership and Hospitality are K6. Client: no change needed — every screen these touch already
  prints the lifted function's number; a house-bonus list on the Skills screen follows once lit.
