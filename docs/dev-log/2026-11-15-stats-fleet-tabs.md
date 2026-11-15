# 2026-11-15 · stats-fleet-tabs · 0431 THE STATS OPEN EVERY FLEET (owner row 349)

The owner, 2026-11-15: *"in stats, i would like to have a separate tab for navy, pirates, and cargoships like merchants. and by clicking on navy,
i should be able to see how much damage it took, how much money = loot it took, fixing fees, and so much more. same for pirates as well. for
cargoships i want to see from what city to what city it delivered, and so much more."*

## What the player sees

Three new Stats faces after Merchants: **Navy / 해군**, **Pirates / 해적**, **Cargo / 화물선**. The strip now holds ten faces: five over five on a
phone, one row from 1,024 px. **Ships / 선박** (0419) stays, after Cargo, as the four kinds side by side (decided by default).

Each new face is the Merchants pattern (one read, MAIN | SIDE, a list, a press opens one item in a tray):

- **SIDE**: the kind's ships and fleets and where the fleets are (one bar: at sea, in port, laid up, wrecked), and one **Totals** table: every
  figure of the kind, its last 24 h and its 7 days side by side.
- **MAIN**: the list of every fleet, filtered by country (Navy, Cargo) or home (Pirates), sorted by the face's figure (a navy ship's fights, a
  pirate's loot, a cargo ship's gold delivered), damage, costs or name. Each row: flag, name, the figure (7 days), and state, home, ships,
  damage, costs.
- **A press opens her page** (a tray, read each second): **Where** (country or pirate house, state, port or from -> to with arrival, duty, home
  or station), **Gold trips** for a cargo ship (what she carries now, the load's city, her last 12 gold rows: from city -> to city, how much,
  how long after the load, how long ago), **Totals** (her 24 h and 7 days), **Ships** (each ship's hull of its max, crew), **Log** (her last 12
  moments: fights, stops, battles, raids, ransoms and gold taken, repairs).

| face | figures (24 h and 7 days) |
|---|---|
| Navy | fights, won, lost, pirates sunk, stops, damage (hull lost), wrecked, fines, prizes (cargo seized, at base value), upkeep, repairs |
| Pirates | raids, won, lost, loot (ransom + gold), ransom, gold (a cargo ship's), navy fights, damage, wrecked, rebuilt, upkeep, repairs |
| Cargo | deliveries, delivered, loads, returned, looted, attacked, held off, damage, wrecked, repairs |

"Prizes" for the navy are the goods a navy ship seizes from a merchant it stops (0334's PLUNDERED: they go to her capital). The game has no other
navy prize; there is no navy loot.

## What was recorded, and what had to be added

Read on the local chain at head 0426 (the queue's 0427-0430 cut none of the bodies below):

- **Cargo ships**: everything that moves gold is already in `public.convoy_cargo` (LOADED, DELIVERED, RETURNED, LOOTED; by fleet; never
  deleted; index `(fleet_id, id)`). The page reads her last 12 rows from it directly: the "from" city is the load's city.
- **Navy and pirates**: only their LAST fight (`navy_ships.fought`, `navy_fight_log`) and the NAVY_FIGHT event (no index by fleet). Upkeep
  (NAVY_PAY), refits (REFIT), fines (FINE), ransoms (RANSOM) and loot (LOOT) are written to the CITIES' books with no fleet; NPC voyages and
  events are cut after 3 hours by the compactor. So a navy ship's damage, upkeep, repairs and fines, and a pirate's loot, were recorded nowhere.

So **0431 adds the smallest record that answers the owner**:

- `public.fleet_book`: one row a fleet an HOUR that something happened to her, `figs` a jsonb of numbers added up. Kept 8 days (the Stats count
  deletes older hours). No foreign key on purpose: a key share lock on `fleets` would wait behind the beat's `for update` on the same row.
- `public.fleet_lines`: her last 12 moments, a small jsonb each, trimmed to 12 at each write, and 8 days.
- ONE writer, `public.fleet_book_add`, that NEVER RAISES (0364's rule: any error is a warning, its sub-transaction undone, the fight or pay that
  called it stands). Five bookers call it: `fleet_book_fight` (navy against pirate), `fleet_book_stop` (a navy stops a merchant: fine, prize),
  `fleet_book_refit` (a wreck's refit), `fleet_book_take` (ransom, a cargo ship's gold), and the trigger `fleet_book_battle` on
  `public.battles` (a battle closes: 0427's raids, players' attacks; every navy, pirate and cargo ship that came in time). The trigger was
  chosen over a hunk because `battle_resolve` is cut by 0427, still in the queue: the trigger is independent of either body.
- Nine one-line hunks beside the line that already moves the money: `navy_fight`, `voyage.navy_meets`, `navy_pay`, `pirate_pay_hour`,
  `npc_refit_step`, `pirate_reborn`, `pirate_ransom`, `pirate_loot_book`, `convoy_book`; and `tick_stats` writes the three lists
  (`public.stats_fleet_list`, one row a kind) and the 8-day deletes; the registry gets the two reads.

Two-fleet bookings take the lower fleet id first (one lock order).

## Load (the database budget)

- **Writes**: every navy and pirate ship at work is paid each hour (~40 + up to ~100 upserts an hour), and gold moves, fights, stops, raids and
  refits add a few a minute. **Expected +3 to +8 rows a minute** (upserts into the hour's row, line inserts and their 12-trims).
- **Size**: realistic ~35,000 book rows (40 navy and ~108 pirates every hour, 100 cargo ships about a third of their hours) and <=2,000 lines:
  ~9 MB with indexes. The worst case measured (every fleet every hour, 370 cargo ships): 80,064 rows, 20 MB.
- **The Stats count** (4 an hour) builds the three lists from the book's 7 days: 192-214 ms at the worst case above, ~90 ms expected; it
  writes 3 rows and deletes the hours past 8 days.
- **The reads**: `world.stats_fleet_list` one row by key, 0.24 ms (the cargo list 81 kB at 370 ships, ~20 kB at 100; a list row carries only
  the keys the list shows); `world.stats_fleet` one fleet's <=192 hours, 12 lines, 12 gold rows by index, 1.43 ms.
- `public.fleet_book_add`: 0.27 ms a call.

Measured with `scripts/ops/harness/fleet-tabs/cost.sql` (local, 40 navy, 7 pirate, 370 cargo fleets, 8 full days):
`fleet_book_add 0.265 ms; the three lists x5 {214,192,192,193,192} ms; the whole count 390 ms, its fleets phase 202 ms; world.stats_fleet_list(CARGO)
0.24 ms (81 kB); world.stats_fleet 1.43 ms`.

## Checks

- Migration self-assert: eleven hunks each once and reversing; grants, volatility, definer, search path, owner unmoved; no other function moved;
  new functions server-only, the reads STABLE and granted to authenticated alone; the trigger; a rolled-back probe (a fleet's hour summed, lines
  trimmed to 12, a booking that cannot be written only warned and her hour unmoved, the three lists built and timed, a navy ship's page where the
  world has one, a merchant's fleet refused).
- Proof 132 (`scripts/db/proofs/132_the_stats_open_every_fleet.sql`), 8/8: FB_FIGHT, FB_PAY, FB_GOLD, FB_STOP, FB_REFIT, FB_BATTLE, FB_LIST,
  FB_PAGE, each driven through the game's own function.
- Harness `scripts/ops/harness/fleet-tabs/`: `before.sql` (eleven 1s, absent, sizes; generated from the migration's own hunks by `gen.mjs`),
  `after.sql`, `cost.sql`, `rollback-0431.sql` (opens with the guard; tested locally: after it every hunk occurs once again in its pre-image and
  nothing of 0431 is left).
- Client: tsc, eslint, vite build; specs `rpc.surface` (the pin), `db.budget`, `words`, `consistency` and `stats.design` (the face lists).
- Screenshots (headless, a patched local world with proof 132's scene; 1440x900 and 390x844, EN and KO; no sideways scroll):
  `C:\Users\gkwng\dev\stats-fleet-tabs-shots\`.

## Files

- `supabase/migrations/20260818000431_the_stats_open_every_fleet.sql`
- `scripts/db/proofs/132_the_stats_open_every_fleet.sql`
- `scripts/ops/harness/fleet-tabs/` (`gen.mjs`, `before.sql`, `after.sql`, `cost.sql`, `rollback-0431.sql`)
- `src/features/stats/Fleets.tsx` (new), `StatsScreen.tsx`, `statsFaces.ts`; `src/lib/rpc/{catalog,index,types,localBackend}.ts`;
  `src/lib/i18n/dict/stats.ts`; `tests/{rpc.surface,consistency,stats.design}.spec.ts`
