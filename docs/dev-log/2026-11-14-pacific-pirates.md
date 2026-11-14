# 2026-11-14: pirates have homes and grounds (migration 0414)

## What the owner ordered, in his words, in order

1. "pirate ships don't trade. they only do and engage combat" (later withdrawn, see 4).
2. "make 70 pirate ships that roams around south pacific ocean, make an island near at the center of pacific ocean each(south and north), a pirate hub, where destroyed in that area (pacific) is respawned."
3. "same for south atlantic ocean, 40 ships, north atlantic ocean, 40, indian ocean 30,"
4. "actually, make them trade too, but engage combat more aggressively with other npcs and players"
5. "so they should not strictly be inside the zone (each ocean), but each pirate ship should have a home city, including port royal and the hub islards that are going to be made, and will be restock, rebased, fixed when they lose and their ships destroyed (respawn). get it?"
6. "the pirate cities will fund those that have empty purse." Then "just enough to start", then "not just enough to start, just like before./"
7. "make pirate fleets some strong, some weak, with multiple fleets, multiple ships and so on"
8. Of the seven wrecked pirate ships: "find the root cause, make it so that this problem does not occur again".

## What 0414 does, and what it does NOT do

**In 0414:** the root cause of the wrecks and its fix (8, 5, 6); five hub harbours (2, 3); the roster of 180 ships in 108 fleets, varied (2, 3, 7); respawn at the home city (5); a capped figure for how much a sea's pirates raise its raids (4, the "more aggressively" half).

**NOT in 0414, and why (said plainly):** the ships of a ground do not trade yet, and a pirate ship's house is not topped up "like before" (4, 6). A pirate ship of 0339 is a house with a purse of 0 and no capital, moved by the pirates' own job; the merchants' planner moves a fleet by a standing route. Making one ship do both needs either the planner to move a pirate ship or the raid rule to name a merchant fleet, and both touch the functions migration 0410 is cutting today (the merchants' planner and lap book). Trading on today's planner would also lose money: 13 of the pirates' 24 merchant houses went broke in one to four days. So the trading half is the next file (0411), to be built on 0410, with the top-up through 0408's rule (which now pays a broke pirate merchant house her full capital from the hoard). Until then a ground ship cruises and raids as every pirate ship does, and her house holds no purse.

## The root cause of the wrecks (prod, read-only, 2026-11-14, head 0407)

All 7 pirate ships were `UNABLE_TO_SAIL` with hull 0.

**Why hull 0: the navy's hunt (0340, `public.navy_hunt_pass`).** A navy ship and a pirate ship in one sea fight, once an hour a ship. The navy sails galions (attack 250, hull 2,800, 43 of them); a pirate ship of 0339 is one xebec (attack 60, hull 530). Every one of the 12 navy fights kept in `public.navy_fight_log` ended `A_TOOK`. Ship 1 was respawned 22 times and refitted 27 times in four days (1,080,000 d. to Santiago's yard). Her "quiet voyage" Port Royal to Paramaribo that ended 06:54 UTC was fought at sea at 06:49 by Navy ship 3 and again at 07:50 in port by Navy ship 5: a navy fight is not a day of the voyage, so the voyage report says nothing. No wear, no weather, no refit that failed to mend.

**Why she stays: 0339 handed pirate wrecks to 0322's refit rule, and 0338 founded their homes with nothing.** `public.npc_refit_step` (0322) lets ONLY the wreck's home city pay (25 % of the build cost: 40,000 for a xebec) to the nearest yard. 0339 made a pirate ship's home her origin (`public.fleet_origin`, "0322's wreck and refit take her unchanged") and 0338 created Djerba, Goto and Lingga with a purse of 0. On the day: Djerba's surplus 38,177, Goto's 1,603, Lingga's 62. Five ships sat `REFIT_WAITING`, "broke", since 10 to 14 November, and nobody stood behind the home. They were the only five rows of `public.npc_refit_waits`: no merchant, cargo ship or navy ship was stuck the same way.

**Which check should have caught it.** Proof 46 (`PIR_WRECK`) proved the refit only at Port Royal, the one home with money. No after-check counted pirate ships unable to sail (0339's and 0340's harnesses read fights and counts of ships).

## The fix, at that cause

A pirate wreck is no longer 0322's. `public.pirate_ship_step` hands a fleet whose every hull is at 0 to **`public.pirate_reborn`**:

1. she is at her **home city** at once (`voyage.npc_wreck`, the respawn 0322 wrote), `wrecked_at` stamped;
2. she lies `pirate_respawn_minutes` (60);
3. the refit is paid (`public.pirate_refit_pay`), she is mended (`public.fleet_mend`), manned from her home's quay (`public.fleet_hands`), stored (`public.fleet_stores`), and may sail.

**Who pays** (the owner's order): her own house's purse; else her home city; else another city the pirates hold, the richest first; else Port Royal's hoard through `public.pirate_pay`, inside the day's room. Whole or nothing, to the yard `public.refit_yard` names, kind `REFIT`, moved. A ship homed at Port Royal is paid by Port Royal first. Nothing is minted.

**When every pirate purse is dry** she waits at home: the step answers `WAITING`, a row stands in `public.npc_refit_waits`, a `REFIT_WAITING` event is written once a day, and she is asked again every time her step runs. No hull is restored unpaid.

`public.npc_refit_step` answers `NOT_A_WRECK` for a pirate ship, so the merchants' hourly job never pays for her a second time.

The home rule is ONE rule for every pirate ship: the 13 of 0339 (Port Royal, Djerba, Goto, Lingga) and the roster's. After the deploy the seven wrecks are stamped at their next step and sail an hour later.

Not restocked: gear. The game mends hull, crew and stores for an NPC ship; guns and gear are not tracked for one.

## The guard

- **Proof 106** (`scripts/db/proofs/106_pirates_have_homes_and_grounds.sql`), through the pirates' own job: `PH_REBORN` (a wreck whose home's purse is empty is whole an hour on, another purse paid), `PH_OLD` (a lone xebec of 0339 at a home with no purse: the fault of today), `PH_LOUD` (every purse empty: WAITING with a row and an event, never silent, never mended unpaid; the purse back, she is mended), plus `PH_ORDER`, `PH_BUILT`, `PH_CAP`.
- **Health check** `scripts/ops/harness/pacific-pirates/health.sql` (read-only): pirate fleets unable to sail for more than 3 hours (should read 0), pirates waiting on a purse, and any other NPC ship waiting on a refit for more than 3 hours, by kind.
- **The same fault elsewhere:** a merchant or a navy ship can also wait on a refit only her home (or station) may pay. None was waiting on the day. The health check counts them; a rule for them is a follow-up, not built here.
- Proofs 45, 46 and 48 were moved with the rule (45: the pirates hold nine cities; 46 and 48: a pirate wreck is reborn by her own step).

## The five hubs

| Code | Name (KO) | Where | Sea zone | Ships | Cruises as far as |
|---|---|---|---|---|---|
| PTC | Pitcairn (핏케언) | 25.07 S 130.10 W, South Pacific | STH | 70 | 3,100 nm |
| MWY | Midway (미드웨이) | 28.21 N 177.37 W, North Pacific | NRT | 0 | 2,500 nm |
| TDC | Tristan (트리스탄) | 37.07 S 12.31 W, South Atlantic | SOU | 40 | 2,400 nm |
| FLO | Flores (플로르스) | 39.45 N 31.13 W, North Atlantic (western Azores) | NOR | 40 | 2,400 nm |
| DGA | Diego Garcia (디에고가르시아) | 7.31 S 72.41 E, Indian Ocean | IND | 30 | 2,400 nm |

Real islands, none a harbour before (Bermuda is: St. George's; Flores is 188 nm from Angra, which is no pirate harbour). Each stands on sailable water of the game's raster; the chart has no land for any of them, so each wears an islet (`src/chart/landfall.ts`, 30 to 35 islets).

A data slice as 0338's three: tier 3, four existing goods each, purse 0, no seed, **no money moved by the file**. Generated, not typed: `scripts/ops/harness/pacific-pirates/gen-sea.mjs` (roadsteads, sailed distances to all 267 places, 80 courses to and from the nearest harbours, by the game's grid and pathfinder), `gen-legs.mjs` (the seas of the 2,510 plotted pairs, into `data/sea-legs.json`), `gen-0414.mjs` (the file).

**Decided by default (the owner may reverse any):**
- They are HELD by the pirates, not homes. A great power has four homes (`docs/INFLUENCE.md` D1; the world guard holds it). So a hub taxes (3 %), its market regenerates, and it can be contested by influence like any city. The Countries board now reads The Brethren 9 held, 4 home, 5 won.
- Hub purses start at 0. They fill by the game's own rules: pay for a ship lying at her hub is paid into the hub, and ransom and loot land at the raider's home. Behind an empty hub stand the other pirate cities and Port Royal.
- ALL 70 of the Pacific are homed at Pitcairn, so that they roam the SOUTH Pacific as the owner said (a first cut homed 20 at Midway; from there they cruised Honolulu, Tokyo and Japan's seas, which is the North Pacific). Pitcairn's eight haunts are Auckland, Concepcion, Paita, Valparaiso and Callao (South Pacific), Wellington (Tasman Sea), Navidad and Acapulco (North Pacific coast): no fence. Midway is the North Pacific haven: a pirate city on the map that pays in its turn behind an empty purse, with no fleet homed there. A fleet is homed there by adding a roster row.
- No fence: an ocean is where a hub's ships mostly roam because their haunts are the harbours nearest the hub. Nothing turns a course back.
- Goods: Midway tapa-cloth, pandanus-mats, sea-cucumber, shark; Pitcairn barkcloth, kumara, harakeke, abalone; Tristan yams, millet, ochre, plantains; Flores canary-sack, archil-lichen, and as a named entrepot salt-cod and virginia-leaf (its region has only two native goods with a free place; `data/goods.json`); Diego Garcia toddy, zebu-cattle, sea-cucumber, shark. All existing goods that already have a roster maker, none in a fourth city. No good is given its first maker (a first cut gave Flores grapes and sugar-cane, which would have made two made-not-sold goods into traded ones everywhere).
- Midway and Pitcairn speak English (a named exception in `data/captains.json`): by their region's culture they would be Malay, and two more Malay harbours changed the second language of three captains players may hold.
- Each hub's quay is seeded with the hands its own fleets need once (Pitcairn about 2,500). After that it is the game's.

**What the harbours change in live play** (local head world): 3,145 new market rows, the hubs' own. **No existing market row's stock, max stock, production or affinity is touched** (0338 and 0217 re-derived the rows near a new maker and reset their stock: 572 rows for 0338's three harbours; a first cut of this file would have reset 1,311; that part is left out). What does move is the HAUL figure (the distance premium in a price) of 2,441 rows of the 18 goods, where a hub is now the nearest maker: the world guard holds every row's haul to `world.haul_rows()`, so it cannot be left stale. It lowers the distance premium of those goods at harbours nearer a hub than any other maker; it moves no stock. `lock_timeout` 5 s: deploy at a quiet minute.

## The roster: 180 ships in 108 fleets

`public.pirate_hubs` (one row a hub), `public.pirate_roster` (one row a fleet: ord, hub, house, names in English and Korean), `public.pirate_roster_hulls` (class, count). Change a count by changing rows; no function reads a number.

One block of ten ships is six fleets: two lone brigantins and a lone fusta (attack 20, hull 300: a beginner can beat or outrun them), a lone xebec (60), a pair of xebecs, and a squadron of four behind a lead ship (a galeoncete, attack 230, hull 2,120; at Flores a korsan, attack 70, because beginners start in the North Atlantic). Half the fleets are one weak ship, a third a xebec or a pair, a sixth a squadron. The pair and the squadron of a hub's first block sail for one house (two fleets); Pitcairn has two such houses. 108 fleets (Pitcairn 42, Tristan 24, Flores 24, Diego Garcia 18), 103 houses.

Weak and strong cannot be placed in different waters of one ocean: a pirate's position is her sea, and a sea is the whole ocean. What the code does give: the raider named for a raid is the lowest ord cruising that sea, and the weak fleets have the lowest ords of each block.

A roster fleet is built by `public.pirate_commission_fleet`: the hoard pays the nearest yard every hull's build cost in one payment. `public.pirate_add` adds one fleet every `pirate_add_minutes`, 0339's ships first, then the roster a hub at a time in turn.

`public.pirate_ships.player_id` is no longer unique (a house may own several fleets). The fight engine, `voyage.pirate_strength`, the navy's fight and the fight log already read a fleet's hulls.

## Knobs

| Knob | Before | After |
|---|---|---|
| `pirate_respawn_minutes` | none | 60 |
| `pirate_add_minutes` | `navy_build_hours` 24 h was used | 10 |
| `pirate_pressure_max` | no cap | 1.0 |
| `pirate_spend_day_pct` | 0.005 on the old clock; 0.001 since 0413 | x 2.4 of what stands: 0.0024 on the one-hour day (0.012 on the old clock) |

`pirate_max` 30, `pirate_min` 4, `pirate_hoard_unit` 100 M are unchanged: `public.pirate_size()` (13 today) still counts only 0339's lone ships. The roster stands beside it.

## The money

Hoard 980 M (Port Royal).

- **Building:** 36.2 M once, to foreign yards (a block costs 2,132,000; a Flores block 1,596,000).
- **Pay:** `navy_upkeep_day` 60,000 a FLEET a day (0339's rule pays a row of `pirate_ships`, so a squadron of four is paid as one: decided by default, not changed). 121 fleets: 7.26 M a day. Pay for a ship lying at a pirate city stays inside the hoard; pay at a foreign haunt leaves it.
- **Refits:** 25 % of the build cost a wreck: 20,000 a brigantin, 40,000 a xebec, 354,000 a squadron.
- **0408's gifts:** 250,000 a broke pirate merchant house, at most 18 M a week for 24 houses; 16 were on the roster on the day (4 M).
- **The day's room** caps everything Port Royal pays: 0.5 % was 4.9 M, under the pay alone. 1.2 % is 11.8 M: pay 7.26 M, gifts about 2.6 M a day at the worst, the rest for building and refits. The roster fills in about a week, as the room allows.
- **How long the hoard lasts if raids bring nothing:** it cannot fall faster than 1.2 % a day. At the full draw it is about 680 M after 30 days and half after 58; near day 40 the room falls under the pay and the last fleets go unpaid, sail home and are laid up (0339's rule). It does not reach zero; the pirates shrink.
- If the navy keeps taking every pirate it meets, refits are the larger bill. Ship 1 alone cost 280,000 a day. The room is the brake: when it is spent, wrecks wait until the next UTC day.

## The money on the one-hour day (0413 landed first; restated 2026-11-14)

The section above was written on the old clock (a voyage-day 90 s). 0413 made a voyage-day 450 s and divided the economy's rates per real day by 5 through its one door, `public.clock_set`: `navy_upkeep_day` 60,000 -> 12,000 and `pirate_spend_day_pct` 0.005 -> 0.001. So this file no longer types 0.012: it **multiplies what stands by 2.4** (0.001 -> 0.0024) and writes the value it replaced into the knob's description for the rollback. Both knobs are already on the door's list, so a later clock move scales them again. This file adds no new rate per real time: `pirate_respawn_minutes` (60) and `pirate_add_minutes` (10) are real-time pacing and stay; `pirate_pressure_max` is not a rate.

| A real day, hoard 980 M | old clock (as designed) | one-hour day |
|---|---:|---:|
| the day's room | 11.8 M | 2.35 M |
| pay of 121 fleets | 7.26 M | 1.45 M |
| left after pay | 4.5 M | 0.90 M |

Per voyage-day every line is what it was. What does NOT scale is a price paid once: a hull's build cost, a refit, a gift.

**Decided by default (the coordinator, 2026-11-14; the owner may reverse it): THE ROSTER'S BUILD IS COUNTED APART FROM THE DAY'S ROOM.** The owner ordered the 180 ships; their 36.2 M is a one-time founding of his order, not running spend. Inside the room it would have taken about 40 real days (0.90 M a day left), and a squadron (1,416,000 in one payment) would have taken the pay's room on each of 14 days and left paid fleets unpaid. So:

- `public.pirate_commission_fleet` pays a roster fleet's hulls from the hoard **outside** `public.pirate_spend_room`; nothing is written to `public.pirate_spend_day`.
- **Bounded by the roster itself:** only a row of `public.pirate_roster`, only her own hulls' cost, and only ONCE (her row in `public.pirate_ships` stands for ever; a wreck is reborn, never rebuilt). 36.2 M in all.
- **Paced by `pirate_add_minutes` alone** (10 real minutes, real-time pacing, kept): 108 fleets in about 18 real hours.
- **A floor:** the hoard is never taken below `pirate_min` x `pirate_hoard_unit` (4 x 100 M = **400 M**) by a roster build: the hoard that keeps the pirates' own minimum. A fault cannot drain it. From 980 M the whole roster leaves 944 M.
- **Its own kind, `BUILD_ROSTER`** (moved, capital to yard; Stats word "Pirate fleets" / "해적 함대"), so it is told apart from running spend (`BUILD_NAVY`, `NAVY_PAY`, `REFIT`) in every flow.
- **Nothing else uses that door:** the payment is lines of that one function. The pirates' own slow growth (`public.pirate_size()`, `public.pirate_commission`, `BUILD_NAVY`) stays inside the room as before.

**The day's room then covers the pay, the refits and the gifts, as designed:** room 2.35 M, pay 1.45 M, **0.90 M a real day for refits and gifts**.

- **A normal day.** A refit is 20,000 (a brigantin or fusta), 40,000 (a xebec), 80,000 (a pair), 220,000 or 354,000 (a squadron). 0.90 M is 45 weak ships' refits, or 22 xebecs', or two squadrons' and nine xebecs'. On 2026-11-14 the navy wrecked one lone xebec about five times a day (the 13 old ships; the navy fights once a real hour a ship, real-time pacing). If a tenth of 121 fleets were taken once a day in the mix of the roster that is about 0.5 M: it fits, with room over for gifts.
- **A bad day** (the navy takes most fleets it meets, or several squadrons): the room is spent before the day ends. Wrecks then wait at home, loudly (WAITING, a row in `npc_refit_waits`, one `REFIT_WAITING` a day), each asked again at her every step, and are mended from 00:00 UTC when the room is new. They are not queued by price: each wreck asks when her own step runs, and a payment is whole or nothing, so a 20,000 refit still fits a room a 354,000 one no longer does: in effect the cheap ones go first. A house with a purse pays her own refit and takes none of the room. Pay is hourly and is not kept back from refits: on a very bad day late pay slices can fail and those fleets are laid up until the next day (0339's rule; PR #685 keeps the pay's room back from gifts only).
- **How long the hoard lasts if raids bring nothing:** the roster's 36.2 M once, then never faster than 0.24 % a real day: from 944 M about 878 M after 30 real days, half after about 290.
- 0408's gifts (250,000, at most 18 M a real week for 24 houses) are more than a week's room left after pay (6.3 M): they wait their turn inside it.

Proof 106 `PH_FOUNDING` holds all of it: the day's room spent to nothing, two roster fleets are still built (1,736,000 under BUILD_ROSTER, nothing written to the day); a second build of one fleet, an ord off the roster and the pirates' own build are refused; one ducat short of the floor the build is refused, at the floor exactly it is paid.

## Raids: what players and merchants will meet

No raid odds, damage, flight or loot rule is changed. One thing is: how much pirates in a sea raise that sea's danger.

- **Before 0414:** 0.5 a ship, no cap (`voyage.sea_danger` = authored figure x (1 + pressure), at most 1). Forty fleets in the North Atlantic (authored 0.12) would have made its danger 1: every sailed day a pirate day.
- **After:** at most `pirate_pressure_max` 1.0: a sea with two or more pirate fleets cruising it has twice its authored danger, never more. The most ever seen before was 1.5 times.
- **Measured today** (24 h of `voyage_events`): 300 raids, 12.5 an hour in the whole world: merchants 254, cargo ships 33, navy ships 13, players 0 (no player sailed a day in those 24 hours). 0.16 % of sailed days.
- **Expected after**, if every sea the pirates cruise is at the cap: at most twice, 25 an hour (merchants about 21). The local scene put 40 fleets over 13 seas, 10 of them at the cap.
- **A player in the North Atlantic:** about 0.16 % a sailed day today, at most 0.32 %; a five-day passage about 0.8 % before, 1.6 % after.
- **How strong the raider is:** an anonymous raid there has strength 2.4 to 7.2. A named raider fights with her own hulls: a brigantin 5.3, a xebec 12.7, a pair 25.4, the Flores squadron 51.8, a galeoncete squadron 71.5. A beginner who meets a squadron loses; the existing choices (pay, flee, fight, a standing raid order) are unchanged.
- **Beginner protection:** none exists in the game (no knob, nothing in `voyage.settle`). The sea rule keeps low titles out of far seas, not out of the North Atlantic. None was invented here.
- **The merchants' economy:** raid losses at most double in the seas the pirates cruise. Not measured in ducats.

## Load

- The pirates' job is its own cron job, not the beat, at most 40 steps a run. On prod today: 198 ms a run for 7 ships (all wrecks). The navy's job costs 1,550 ms for 43 ships (36 ms a ship a minute), the cargo ships' 42 ms. 121 fleets at that price: about 4 s a minute at the worst, about 1 s when most are at sea.
- On the beat (`tick_arrivals`): a sailing fleet is one day settled every nine minutes or so. 121 more sailing fleets on about 1,300: about 9 % more settles.
- At each departure the freeze asks which pirate cruises each sea of the course: one indexed read a segment.
- The navy fights at most 5 a minute, as before.
- **Not measured on prod.** `after.sql` reads the three jobs' times. If the beat slows, delete roster rows: the fleets sail home and are laid up.

## Client

The five show on the map with the pirates' flag and an islet, in the Codex and harbour lists as any harbour, with Korean names (`src/lib/i18n/names/ports.ts`) and in the island list. A roster fleet's sheet shows her Korean name (`world.pirate_ship_card` serves `name_ko`, `house`, `house_ko`). No new UI word.

Pictures (build machine): `C:\Users\gkwng\dev\pacific-pirates-shots\`: desktop, all five; phone, Pitcairn (the port tray). The other four phone shots were not taken (the capture script lost the mark behind the open tray).

## Checks run

`tsc -b`, eslint on touched files, `vite build`; the file applied on the cached head world with 0408 (1.9 s) and its probe; proofs 106, 45, 46, 47, 48, 49, 66, 103 after it; a lit scene (`scene-sail.sql`: 28 roster fleets built in 40 ticks, all sailed, pressure capped, a wreck brought home and reborn); `news.lint`, `cityKind.law`, the two unit tests of `map.landfall`. `before.sql` read on prod at head 0408: every hunk present once.

**Not run:** the browser tests of `map.marks` and `map.landfall` (their counts are moved by reasoning: 254 harbours, 257 marks, Midway the third at the seam); the world guard; the full proof suite. CI is the proof. `scripts/check-ports.mjs` (not in CI) is red for three countries with no bounding box (PN, SH, IO).

## Deploy

0414 = 0413 + 1 (it was written as 0410, renumbered 0409, and renumbered again to 0414 after "the world fits the harbour it has" took 0409 and deployed). Before: `before.sql` (head 0413, hunks true). After: `after.sql` at once and hourly for a day; `health.sql` should read 0 from two hours on. Rollback: `rollback-0414.sql` (a draft); the fast lever is `pirates_bite` false or deleting roster rows.
