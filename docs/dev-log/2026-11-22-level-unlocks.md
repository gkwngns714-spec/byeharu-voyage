# 2026-11-22: Each level opens something (0468, proof 171)

The design: `docs/design/playable-2026-11-22.md` P2; `docs/design/content-plan-2026-11.md` 5.3 item 9; `docs/LEVELS.md` section 7.
Ships **dark** behind `level_unlocks_enabled` (false). Lighting it is the owner's.

## What each Trading level opens, lit

| Trading | Opens | Where the server applies it |
|---|---|---|
| 2 | Routes +1 | `public.standing_route_max_for` (the route cap's trigger) |
| 3 | +1 fleet (already live, `fleet_room_levels`) | `public.fleet_room_caps` |
| 4 | Ships a fleet +1 | `public.fleet_room_caps` (never above `fleet_ship_top` 7) |
| 5 | Yard fee −10% | `public.hull_order_price` (the yard order's fee only) |
| 6 | +1 fleet (already live) | `public.fleet_room_caps` |
| 7 | Routes +2 | |
| 8 | Yard fee −20% | |
| 9 | Ships a fleet +2 | |
| 10 | Yard fee −30% | |
| 11 | Routes +3 | |
| 12 | Yard fee −40% | |
| 13 | Ships a fleet +3 | |
| 14 | Yard fee −50% | |
| 15 | Routes +4 | |
| 16 | Yard fee −60% | |
| 17 | Ships a fleet +4 | |
| 18 | Yard fee −70% | |
| 19 | Routes +5 | |
| 20 | Yard fee −80% | |

Every Trading level from 2 to 20 opens exactly one thing (the migration and proof 171 assert it). The titles and the seas they open,
the captains' promotions and the Reputation gift are unchanged.

What a player sees, lit: the arrival card adds "Opens: Ships a fleet +1" under "Trading level 4"; the goal card says what the next
Trading level opens ("Trading 4: Ships a fleet +1"): on its first line while the company has one ship, else after the two tracks; the
You page's Trading tile lists every step, as the seven levels raised by doing already do. Dark, none of that is served, and the arrival
card still says what a level opened when the server already gives something there (a fleet at Trading 3, a step of Supplies).

## Decided by default

- **The unlocks are steps of `public.level_perks`** (0417), read by `public.level_perk` and listed by `public.level_benefits`: the one
  authority for what a level gives, extended with 17 Trading rows. No second table.
- **Only additions.** A hull by Trading level was weighed and left out: hulls are opened by the Academy's hull skills
  (`public.requirements_unmet`, 0135), so a Trading gate would be a second ladder for the same door, and it would take hulls away from
  companies today. A cheaper yard labour was left for the same reason (docs/LEVELS.md 7). The yard ORDER's fee (0465) is nobody's figure.
- **The level read is the mark paid** (`public.house_level_marks`, 0356): the level whose LEVEL_UP moment the arrival card shows. One key
  probe, so the route trigger, the caps trigger and the yard's order pay nothing heavy; `public.player_progress` is not called.
- **The fee falls to 10 % at Trading 20,** not to nothing (`yard_fee` 80 % in all; asserted under 100).

## Measured

Local world (PGlite), `node scripts/db/proof.mjs 171`: 6/6. A Barca's order at Lisbon: fee 8,807 at Trading 4, 1,761 at Trading 20;
the door took exactly the quote. Proofs 113, 156, 168, 57 still pass.

## Load

None: no table, no job, no event. Each hunked function gains one or two key probes (level_skills, house_level_marks).
