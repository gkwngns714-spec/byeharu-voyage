# 2026-10-18 — 0157: K5, a captain sits in a cabin — `osn-k5-cabins` (stacked on K4)

`docs/SKILLS_AND_CAPTAINS.md` §4.3, §4.4, §6.2 / §8 row K5 (D9 decided by default; the owner may reverse it —
it is data). **Not deployed; dark** (`crew_bite` false). Migration 0157 (coordinator numbering; K2 0154 and K3 0155
deploy first, then K4 0156). Written and proven on 0156-over-0153.

- **Data**: `data/captains.json` gains each effect's `cap_pct` (the four live ones 25 — the retired knob's value)
  and `cabins` (the four kinds and the typed rotation by hull role: trade → Trade, Exploration, Combat; explorer
  and support → Exploration, Trade, Combat; combat → Combat, Trade, Exploration). `scripts/build-captains.mjs
  --sql cabins` prints 0157's VALUES; the world guard holds caps, kinds and rotation to the file.
- **0157**: `cabin_kinds`, `cabin_rotation`, `captain_seats`, `captain_active`, `captain_state`; knobs `crew_bite`
  (false) and `cabin_off_focus_pct` (50); `officer_bonus_cap_pct` retired onto `crew_effects.cap_pct` (asserted
  equal first); an index `ships (fleet_id)` (the one reader walks fleet → ships → seats; without it crew_pct over
  every fleet × 4 effects took 383 ms, with it ~115 ms, against the old function's ~65 ms on player_officers' own
  fleet index). One picker (`captain_seat_pick`), one writer (`captain_seat_put`, which keeps
  `player_officers.fleet_id` equal to the seat's fleet until K9 drops it), the core `seat_captain_for` and the door
  `cmd.seat_captain` (+1 entry point). `public.crew_terms` / `public.crew_pct` (dark = the old arithmetic over the
  seats; lit = active traits × mult × level × cabin rate, the grade floor only above the birth grade) and
  `world.crew_bonuses`, `world.ship_seats`. Re-cut (20 hunks, each reversing): fleet_speed, ship_hold_capacity,
  raid_crew_lost, spread_effective, settle (surgeon_pct; the experience credit reads the seats), world.fleets
  (+ `crew`), world.officers (cap from crew_effects; `ship` / `seat` from the seat), npc_fleet_card (captains by
  seat), ship_view (+ `seats`), post_officer_to and sign_officer (seated by the picker; only in port), the entry
  point registry. `public.fleet_officer_bonus` dropped; no body names it.
- **Proof**: the 511 postings of the cached world seated, every one at 100 % for her job (prod checked read-only
  the same day: every posted fleet's focus mix fits its hulls' cabins — at most 2 exploration + 1 trade on a nau
  or two carlats); every fleet × 4 effects = the pre-image (skills dark and lit), 3,008 reader answers unmoved;
  lit, every merchant fleet unmoved; the probe (rolled back): an S navigator hired into a docked barca sits in
  the Exploration cabin with her five first traits, lit speed 9 % → 4.5 % in the Trade cabin → 9 % in the
  Captain's; anchored, she cannot be moved or put ashore (E_NOT_IN_PORT); seat 99 refused; ashore she adds
  nothing and `fleet_id` follows; a merchant probe's captain uses her job alone, with no state row.
- **Proofs edited**: `scripts/db/proofs/06_haggle.sql` seats its at-the-cap purser through the seat core and
  reads `crew_pct` and `crew_effects.cap_pct` (its old knob is gone). Run locally on the 0157 world: 06, 03, 08,
  10, 11 pass; the others need `proof.mjs`'s fixtures (CI's pglite legs run them).
- **Client**: the ship panel's **Cabins** (seat word, captain, 100 % / 50 %, the server's note; on your docked
  ship **Seat** / **Ashore**); the fleet tray's **Crew bonuses**; the Inn seats a hire in the fleet docked there
  (**Joins … on hiring**), or ashore — `PortInn` no longer takes the acting fleet.
- **Deferred, said plainly**: `cmd.captain_traits_set` lands with K6's Captains roster (a verb without the screen
  that shows traits is half a slice); ship-scope (combat) effects raise in `crew_pct` until S4 (K10).
- **CI**: `scripts/db/proofs/**` is no longer chain machinery in the growth rule (in no snapshot key; a changed
  proof still selects its own pglite leg) — new positive control c4f364a.
