# 2026-11-14: a level gives something as it rises (0413)

**State: built, PR open (stacked on #682, the levels, 0411), not deployed.** The design is `docs/LEVELS.md` section 7.

The owner: *"with exp table, exp info, with benefits when leveling up, what activity needs done etc."* 0411 gave the seven new levels
Reputation only. This gives each a benefit of its own, and puts the tiles on the You page.

## How the benefits were chosen

Each had to be: small; a rule the game already applies; ONE figure with ONE owner function, so a quote and a charge cannot differ;
not a hot loop; not an Academy skill's figure; nothing bought, nothing taken from another company; and none for a merchant.

The Academy's effects were read first (`skill_effects.stat`, local world): endurance, speed, spread, storm damage, calm delay, crew
and captain wages, hold, reach, profit tax, yard labour, standing routes, durability, and the fight stats. That ruled out the
obvious ones (supplies that last longer, storm damage, build labour, the tax).

| Level | Built | Why this one |
|---|---|---|
| Supplies | supplies cost 1 % less a step, 5 % in all | `public.stores_cost` is "the one price of stores" (0142): the door and the planner both read it |
| Weather | gear wears 5 % less on a storm day a step, 25 % in all | `public.wear_units_for` is the one writer of wear and runs for a player's fleet only |
| Shipbuilding | repairs cost 2 % less a step, 10 % in all | `public.fleet_repair_cost` is the one price: the door, the route's quote and the forced-home gift read it |
| Requests | a request gives 10 % more Reputation a step, 50 % in all | the premium itself is paid from the city's escrow (0311), so it was left alone |
| Craft | gear wears 3 % less from miles and fights a step, 15 % in all | a recipe is read in three places with no one function to cut; wear has one writer |
| Routes | a profitable lap gives 20 % more Reputation at 4, 12, 20; one more route at 8 and 16 | `public.standing_route_max_for` is the one reading of the cap (the trigger and the page both ask it) |
| Investment | a stake wins 10 % more favour with the country a step, 50 % in all | a better dividend would come out of the other shareholders' share: left out |

Steps stand at levels 4, 8, 12, 16 and 20 (Routes: 4, 8, 12, 16, 20 between its two benefits): five of twenty.

## Decided by default

1. **One table of steps and one reader** (`public.level_perks`, `public.level_perk`). A benefit is the sum of the steps at or below
   her level. Changing a figure is changing a row; `level_perks_on` false turns every benefit off at once.
2. **No knob of the game was changed.** The figures the benefits multiply are all as they were.
3. **The count of routes is shared with the Factorage skill on purpose** (the coordinator's own example). It is the one place a
   level and a skill touch the same number; they add, in the one function.
4. **The three old levels get nothing new.** They already give fleets, titles, seas, captains' ceilings and promotion levels.
5. **The fight levels are not in this file.** 0409 and 0412 re-cut the pirates' bodies and neither is deployed; deploys are on hold.
6. **The You page keeps its three bars** (its design spec holds them to 24 px figures) and gains all ten levels as small tiles
   under them; a pressed tile opens the same detail in a tray.
7. **The player's word for regard is "favour with the country"** (KO 나라의 호감): the game shows regard only as a country's band.
8. **Honest size of it:** supplies are cheap (a starter's full resupply is about 85 d.), so 5 % there is a few ducats; the repair
   and wear benefits matter more as a company grows. The amounts are rows: the owner may raise any.

## What it costs

| Path | Added |
|---|---|
| a sale, a buy, a day at sea (`voyage.settle`) | nothing (asserted: none names the reader) |
| `public.stores_cost` for a merchant (the planner reads it) | one call of two index probes: **24.0 → 25.0 microseconds** a call on PGlite, OLD and NEW interleaved, 4,000 pairs |
| `public.fleet_repair_cost` for a merchant | the same one call |
| the other six cuts | a player's door, or after a merchant has already left |

## Checks run here (no production read: they are on hold)

- `npx tsc -b --noEmit`, eslint on the touched files, `npx vite build`.
- The migration applied on the local chain (373 restored, 1 applied); self-assert ok in 0.3 s. Wear was proved on a real storm
  piece and a real miles piece.
- `node scripts/db/proof.mjs 108_level`: 5 of 5. A merchant's prices and cap are the same with the knob on and off. At Supplies
  level 20 a company resupplied through the door for 84 d. where the knob-off price is 89 d. The route cap's own trigger refused a
  fourth route at Routes level 7 and kept it at level 8. Ten shares earned 1.00 regard at level 1 and 1.50 at level 20.
- `tests/levels.tiles.spec.ts` (tile tests at 320, 390, 1280, EN and KO: 6 of 6, now with the steps, Routes, and the You page);
  `you.design`, `goal.card`, `i18n.ko`, `i18n.keys`, `words`, `news.lint`: 24 of 24.
- The after-check was run against the LOCAL world (rewritten to drop the migrations table): 10 new hunks once each, 35 steps, the
  table with no client grant, a merchant's price unmoved.

## Reads still wanted on production (not run: held by the coordinator)

1. `scripts/ops/harness/levels/before-0413.sql` after 0411 and 0412 are deployed: the ten OLD hunk texts once each. Written from
   the local world at 0408 + 0411; none of the eight functions is cut by #678 or #681 (their diffs were read), but 0412 is not
   open and was not read.
2. `scripts/ops/harness/levels/after-0413.sql` after the deploy.
