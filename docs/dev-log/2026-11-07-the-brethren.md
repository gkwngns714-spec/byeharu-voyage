# The Brethren (W16, migration 0338, owner row 284): the pirates, the 11th great power

Owner, 2026-11-05: *"pirate headquarters with pirate cities, npcs that attack these ships as well as merchants"*; *"pirates are like countries - power, where they can also invest. pirate merchants too. they will have pirate port that has no tax, cheaper products etc"*. His answers the same day: a player MAY join the pirates (*"yes they can"*); a pirate player attacking other players' merchants is *"not for now"* (the no-PvP law stands). 2026-11-06 (row 306): *"use your recommended defaults for the rest"*. He asked about pirates again on 2026-11-07 because the slice had been parked as "waiting on the owner". It is not parked: this is W16, step 1 of 4 (W16 to W19) of `docs/WORLD_POWERS.md` Part 5.

**State: built, PR open, NOT deployed.** Prod head 0337 when written (read 2026-11-07 09:09 UTC and again about 10:30 UTC). W16 and nothing else: no pirate ship (W17), no pirate merchant and no investing (W18), no navy hunting (W19), no `pirates_bite`, and nothing about a raid changes. Live play changes at four ports (the free ports), which have a one-write lever; the joining knob ships false.

## What a player sees after the deploy

- Four cities fly a skull flag: **Port Royal** (the capital), **Lingga** (the Lingga islands, South China Sea side of the Strait of Malacca), **Goto** (off Kyushu) and **Djerba** (the Barbary coast). The last three are new harbours.
- At those four, docking costs nothing and a sale is not taxed, whoever you sail for. The city page says **Tax 0x (war) / Dock fee 0** and Relationship **war** with every great power. A mayor could not set a tax there (`E_FREE_PORT`); none can be a mayor today.
- Their markets hold half the depth (`depth_mult` 0.5). Port Royal already does (prod today: 0.5000, because nobody has invested there and the formula's floor is 0.5); what changes is that it STAYS there however much is invested, because `depth_day` now leaves a pirate port alone. The three new harbours open at 0.5. "Cheaper products" (the owner's words) is not something W16 can show: in the design it is plunder filling a half-deep market (W17), through the market's existing price curve with no new price term (`docs/WORLD_POWERS.md` 7.3). With W16 alone the half depth is the only change.
- Codex > Nations lists **The Brethren** (skull, capital Port Royal) among the great powers: 11. Rank > Countries lists it with 4 cities (4 home, 0 won). In Korean the name is 해적단.
- The country picker still offers the **ten**; the pirates are not on it. Founding or changing country to them answers "The Brethren takes no companies: a company sails for one of the great powers it may join" (`E_MINOR_POWER`).
- Expect traffic: merchants and players will route to four untaxed ports. That is the order. The first day is the measurement window (30-minute after-check, below).

## What lands

- **The nation PIR** `The Brethren`, flag the skull, the 24th nation and the 11th great power. `great_powers.pirate` (new column, a unique index allows one true row) says which great power has **no crown**; `public.pirate_power(nation)` is its one reader.
- **Four homes**, authored in `data/home-ports.json` (the world guard holds the database equal to it): POR, LGA, GOT, DJE. The file claims them with `port_allegiance_home_never_changes` disabled BY NAME inside the one atomic block and enabled again (asserted, and asserted to bite).
- **War with all ten** (`data/relations.json`, ten rows, each with a line of history; the guard holds the table equal to it).
- **The free port**, one reader `public.port_is_free(port)`: a pirate home, and nothing else, while the lever `pirate_ports_free` is true. `world.tax_rate` answers 0 through it; `public.port_fee` 0; `public.port_dues` serves factor 0; `cmd.set_tax` refuses; `public.depth_day` leaves the depth alone; `port_treasury.depth_mult` is 0.5 on the four. The stored `ports.tax_rate` is NOT touched (see "Decided by default"), so the lever restores the tax.
- **The joining knob** `pirates_joinable` (false), one reader `public.nation_joinable(nation)`: `cmd.found_house`, `cmd.change_country` and the country picker (`joinable` in `world.snapshot`) read it and nothing else. The owner said a player MAY join; he has not said when. He allows it in its own window with one knob write.
- **No crown**: `public.city_capital` answers null for a pirate city; `convoy_ships_wanted`, `tick_cargo_ships`, `navy_read` and `navy_plan_step` skip the pirates; `world.levels` leaves them out of the regard list.
- **Three new harbours** (a data slice, as 0217 was): Lingga (LGA, Daik on Lingga island, Indonesia, South China Sea), Goto (GOT, Fukue, Japan, Korea Strait) and Djerba (DJE, Houmt Souk, Tunisia, Mediterranean). Tier 3, size 2, four existing goods each and no new good; a purse of 0 and no seed; a roadstead and sailed distances to and from every other place; 18 merchant courses; a market row for every good; leg asks, hauls, buildings, tongue, works, population and a flag row with no holder. The pirate part of the file then claims them. The section below says what else moves.
- **Client**: the picker lists `joinable`, `PIR.svg`, `KO_NATIONS.PIR`, `E_MINOR_POWER` and `E_FREE_PORT` words, Korean names of the three harbours, the island list.

## The change from the design: Sale is not the HQ (measured on prod, read-only, 2026-11-07)

`docs/WORLD_POWERS.md` 7.1 names Sale (SAL) the HQ and says it has no holder, 99 M d. Prod now:

| | held by | home | since | influence | mayor |
|---|---|---|---|---|---|
| Sale | **ESP** | no | 2026-11-06 00:47:00 UTC | 7 rows, 640,305 points (ESP 381,248; NLD 258,275; FRA 782), all NPC merchants | 1, an NPC of ESP |
| Port Royal | nobody | no | 2026-10-17 | 0 rows | none |

Spain won Sale at the daily count of 2026-11-06. `docs/INFLUENCE.md` D1 says a home is topped up from FREE cities "so nobody loses a city". Taking Sale would hand a won city to the pirates, strand 640 k points as foreign influence inside a pirate home (the population signal reads that as war), remove an NPC mayor and move Spain's realm purse. So **Sale is not taken** (decided by default). The homes are Port Royal, which is free on prod (no holder, no influence, no mayor; the file REFUSES, loudly and applying nothing, if it is held when it runs), and three new harbours. The capital is Port Royal. The free cities on prod today are AUK, DAR, FRE, HNL, MEZ, POR, PTL, PUS, WLG; none but Port Royal is a pirate place. Sale can become a pirate home later, in a slice of its own, if the owner wants Spain to lose it.

The design's proof line "influence rows are re-keyed with their sum constant" has nothing to re-key here: the four homes hold no influence row (Port Royal 0 on prod; the new three cannot). The file writes no influence row (counted by the transaction's own table counters) and the harness proves the book equal to the ducat: `SCENE: INFLUENCE` before and after.

## Decided by default (the owner may reverse any)

- **Joining.** The design's default was "PIR is not on the picker". The owner has since said YES, a player may join, and NO to a pirate player attacking players. So the refusal is ONE place, a new knob `pirates_joinable`, shipped false. Flipping it changes nothing else: a company that founds under the pirates starts at Port Royal and is paid its starting money by Port Royal (moved, from the hoard; proved).
- **Port Royal's purse.** Its 993.6 M d. (prod, 2026-11-07) makes the pirates the 5th richest of the 11 powers the day this lands: richer than six realms (MNG 660 M, OTT 352 M, JPN 305 M, MUG 110 M, ENG 16 M, JOS 14 M), behind PRT 4.48 B, FRA 3.36 B, ESP 2.46 B and NLD 1.62 B. It is a city's own money; no gold is made. `pirate_spend_day_pct` 0.5 % a day (W17/W18) is what will cap what the power may spend. Removing the pirates later is a ONE-WAY DOOR (a flag is a city's fact).
- **Only the four homes are free.** A contested city the pirates win later keeps its own rate (proved: a city the pirates win is not free, and the war stance doubles its tax).
- **The free ports have a lever**, `pirate_ports_free` (true as shipped). The design says `ports.tax_rate` 0 on the homes. I made the tax a function of `port_is_free` instead and left the stored rate alone, so one knob write puts the four back among the cities (tax, fee, dues, depth walk back) with no migration. This is the nearest safe version of "tax 0" for a change that alters live play at four ports the day it lands; same result for a player.
- **The flag clock does not move.** The four homes' `since` is held at the newest flag change that existed before the file (`least(since, max(since))`), because `tick_cargo_ships` and `navy_plan_step` rebuild EVERY realm's circuit and stations when `max(port_allegiance.since)` moves. No realm's cities changed, so nothing is rebuilt for nothing.
- **The regard list leaves the pirates out**, and the dues line says factor 0 at a free port (not "x2 war" beside a tax of 0).
- **Wording**: `E_MINOR_POWER` is reused for the pirates (the design's one hunk) and its words carry no count ("Pick a power that takes companies."). The server sentence says "<name> takes no companies: a company sails for one of the great powers it may join."
- **Capital**: Port Royal (it has the hoard and is in the era's Caribbean). The fourth home, Djerba, is the Barbary corsairs' base (Turgut Reis; the battle of 1560), taken instead of Sale.

## The consumer audit (every reader of a nation list, and what it does with an 11th power)

SQL (read from the live bodies of the cached head world; function by function):

| Consumer | With PIR | Action |
|---|---|---|
| `public.great_powers` loops: `convoy_ships_wanted` | would give PIR a fleet number (about 41 ships at its purse) and, through `convoy_fleet_settle`, a row | **re-cut: skips the pirates** |
| `tick_cargo_ships` (circuit + commission) | would build a circuit and commission up to 20 crown cargo ships for PIR every minute, convoys being lit on prod | **re-cut: skips the pirates** |
| `navy_read`, `navy_plan_step` | would give PIR a navy size, stations and later a built, paid navy | **re-cut: skip the pirates** |
| `world.levels` regard list | a constant "Wary" line for every company | **re-cut: skips the pirates** |
| `world.nation_standings` (Countries board) | The Brethren, 4 held, 4 home, 0 won | keeps them (a country) |
| `public.city_capital` (the crown of a harbour) | aid from, tax share to, fine paid at POR for LGA, GOT, DJE | **re-cut: null for a pirate city** (reaches `crown_aid`, `crown_donors`, `city_day`, `fine_for`, `regard_line`) |
| `realm_capital`, `realm_purse`, `cargo_*`, `navy_*`, `capital_draw` | reached only through the loops above | the pirates are never in them |
| `power_stance`, `country_factor`, `regard_of`, `regard_factor`, `world.tax_rate`, `port_fee`, `port_dues` | read the ten war rows at a pirate port | tax/fee/dues re-cut for the free port; regard unchanged |
| `tick_influence` | steps 2-3 skip homes; step 4 mayors need a pirate citizen | none |
| `population_signals` WAR | foreign influence at a pirate home reads as war (signal 1) | intended (proved) |
| `world.snapshot` | `great` 11; new `joinable` 10 | **re-cut** |
| `cmd.found_house`, `cmd.change_country`, the `fixes` list | would let PIR in | **re-cut** to `nation_joinable` |
| `port_countries`, `port_ruler`, `yard_wrong_country`, `skill_taught_at`, `world.inn_chance` | a pirate city has no ruler; no pirate home has a yard or academy (tier 3) | none |
| `capital_gift_roster`, `founding_credit` | a company of PIR is paid by Port Royal | only when the knob allows a PIR company |
| cards, stats, inn (`stats_*`, `world.player`, `world.officers`, `world.npc_fleet_card`, ...) | join nations by code per row | show The Brethren |

Client, scripts, data and tests (from a read-only audit of `src/`, `tests/`, `scripts/`, `data/`):

- **Changed**: `NationPicker` filters `joinable` (it kept `<HullCountry`); `SnapshotNation.joinable`; `public/flags/PIR.svg` (white skull on black, 699 bytes; `tests/flags.spec.ts` needs the file, a `SOURCES.md` row and a pixel variance at 21 x 14 px: PIR 151 and 164 against the floor of 35); `KO_NATIONS.PIR`; `E_MINOR_POWER` words without a count and `E_FREE_PORT` (EN and KO); the Codex comment; `world-derive.mjs` (`NATIONS`, `CAPITALS`, `GREAT_POWERS`, `PIRATE_POWER`, three port pins) and its `.d.mts`; `data/home-ports.json`, `data/relations.json`; the world guard (the pirate flag, both directions, with a positive control); `scripts/build-home-ports.mjs` (the pirates' homes are authored, carried over, never offered to anyone else); `tests/greatPowers.spec.ts` (eleven; the picker ten, not the pirates); `tests/cityKind.law.spec.ts` (the pirates' capital is one of their homes); proofs 18, 19, 33, 36, 37 (count the crowns, not the pirates).
- **Fine as they are**: the Codex Nations face (`great`: PIR is the 11th), Rank Countries board (prints every served row), Stats country filters (nations present on the rows), Levels page, the map (a city's flag is its holder's code; the only per-nation colour is eight ink families for merchant hulls, which the pirates do not use), `Flag`, `HullCountry`, `CityFlag`, ledger headlines.
- **Not changed, named**: the Korean sweep (`tests/i18n.ko.spec.ts`) does not cover the Nations face, so a missing Korean name would pass CI: the name is added by hand and checked by `tests/i18n.keys.spec.ts`'s catalogue.

## The 14 re-cuts (hunks sliced from the live bodies; each once, each reversing, attributes unmoved)

| Function | Hunk | Why |
|---|---|---|
| `public.city_capital` | `and not public.pirate_power(n.id)` | the pirates keep no crown |
| `public.port_fee` | `or public.port_is_free(p_port)` in the early return | a pirate home charges no dock fee |
| `public.port_dues` | `factor` is 0 at a free port | no "x2 (war)" beside tax 0 |
| `world.tax_rate` | first act: `if port_is_free then return 0` | a pirate home asks no tax of anyone |
| `cmd.set_tax` | `E_FREE_PORT` before the mayor test | no tax to set there |
| `public.depth_day` | `and not port_is_free(...)` | a pirate home keeps 0.5 |
| `public.convoy_ships_wanted` | `where not g.pirate` | no cargo ships |
| `public.tick_cargo_ships` | `where not g.pirate and ...` | no circuit, no crown cargo ship |
| `public.navy_read` | `where not g.pirate` | no navy |
| `public.navy_plan_step` | `where not g.pirate and ...` | no stations |
| `world.levels` | `where not g.pirate` in the regard list | no meaningless line |
| `world.snapshot` | `'joinable', nation_joinable(n.id)` | the picker's list |
| `cmd.found_house` | `nation_joinable` for the fixes and the gate | the one place |
| `cmd.change_country` | `nation_joinable` | the one place |

Three new readers: `pirate_power`, `port_is_free`, `nation_joinable` (stable, definer, `search_path` pinned, server-only). Two knobs: `pirates_joinable` false, `pirate_ports_free` true. One column, one unique index. Nothing else.

## The three new harbours

The same kind of change as 0217's eight harbours, three more: small ones, tier 3, size 2, four existing goods each, no new good. Their block runs FIRST in the file, before anything of the pirate power exists (so its own assert sees a world with no pirate); the pirate part then claims them. It was generated, not typed: the columns, offers, tongues and populations from `data/*.json` through `scripts/lib/world-derive.mjs`, the sea numbers from a places-only run of `scripts/build-sea-migration.mjs`'s own roadstead rule and pathfinder. The two scratch generators are not committed (the file is the authority, and the world guard holds the database equal to the data, both ways, on every apply).

| | Place | Sea | Region | Founded by | Tongue | People | Offers |
|---|---|---|---|---|---|---|---|
| Lingga (LGA) | Daik, Lingga island, Indonesia | South China Sea | Southeast Asia | nobody | Malay | 2,000 | songket, star-anise, tamarind, zedoary |
| Goto (GOT) | Fukue, Goto islands, Japan | Korea Strait | Japan | Japan (JPN) | Japanese | 3,000 | sea-cucumber, abalone, shark, squid |
| Djerba (DJE) | Houmt Souk, Tunisia | Mediterranean | Maghreb | Ottoman (OTT) | Turkish | 3,000 | sumac, maghreb-brass, saffian-leather, morocco-leather |

**What it writes** (every table a harbour has a row in, found by foreign key and by coverage of the 246 harbours, then by every function that writes one): `ports`; `port_specialties` (12 offers); `port_goods` (1,887 new rows, 3 x 629, each opening at stock = target = the standard depth for its size and priced with the head's own arithmetic: affinity over the nearest maker, 0303's stock cut, demand, the sailed haul); `city_production` (5 outputs by 0280's rule; no function writes this table); `port_buildings`; `port_treasury` (the purse row at 0 and its reserve); `city_works` (level 0); `port_allegiance` (the flag row, no holder); `port_language`; `port_population`; `sea_reaches` (3 new rows of 262 keys, and every existing row gains 3 keys and keeps every key it had: no existing roadstead or distance moves); `npc_courses` (18: each harbour to and from its three nearest by sea); `sea_leg_asks` (1,485, checked in full against the whole-world derivation: 0 differences). Nothing else needs a row: `city_wants`, `stats_*`, `port_mayor`, `port_influence`, `price_history*`, `navy_stations` and the rest are written on demand by the jobs that read every harbour.

**The sea is the raster's, not a guess.** All three roadsteads stand on sailable water (their own quay, snap 0.00 nm). Daik's cell is the South China Sea, not the Strait of Malacca (the Strait ends near 1.3 N 104 E), and Goto's is the Korea Strait, not the East China Sea, so the file says so although `docs/PIRATES_AND_HAVENS.md` calls Lingga the Malacca zone.

**No gold is made.** The three purses are 0 and no seed is posted (`city_seed_amount` is not called; the switch is not touched); the assert reads the transaction's own table counters to prove no row was written to `players`, `treasury_flows`, `treasury_daybook` or `ledger`. `port_treasury.seeded_at` is `now()` where the world's cities were seeded (prod) and NULL in a never-seeded world, as 0217 read it; nothing at head reads it to decide a seed. From the first UTC day the game's own population tax (0304) pays every harbour, these three too: about 25,000 d. a day in all (6,727 + 9,118 + 9,118). That is the game's faucet, not this file's.

**Which goods, and why.** The 0065 law (no good in a fourth city) leaves little room. Southeast Asia has exactly four goods with a free place, and they are Lingga's. Japan has none: its 45 rostered goods all sit in three cities, so Goto's four are sea products among the 41 Japan-native goods no roster holds (0280's goods, made but not sold); each gains its FIRST roster maker. Djerba has seven free places and takes the Barbary tanneries and brass.

**What it changes in live play** (counts are the head world's; the receipt prints them again):

| Good | Harbour | rows whose affinity is re-derived | rows whose haul moves |
|---|---|---|---|
| songket / star-anise / tamarind / zedoary | Lingga | 20 / 45 / 56 / 24 | 84 / 197 / 75 / 67 |
| maghreb-brass / morocco-leather / saffian-leather / sumac | Djerba | 122 / 145 / 139 / 21 | 26 / 31 / 29 / 7 |
| abalone / sea-cucumber / shark / squid | Goto | 0 each | 246 each |
| **Total** | | **572** | **1,500** |

- 572 existing market rows change affinity because a new maker is nearer: affinity, max stock and production are re-derived and the stock is reset to the new max (what every growth since 0041 does; 0303's cut kept, 0252's base target kept in step where set). 1,839 distinct rows move in all, 12 goods, and nothing else: no player row, no roadstead, no switch, no knob.
- Goto's four goods go from a flat haul of 1.0 to the sailed premium (mean 1.48, at most 2.0), and they become tradable: their `haul_nm` goes from NULL to a number, so `wants_draw` may now choose them as city wants.
- The market is a hot table. The file runs ~10 s locally and holds row locks on about 2,000 `port_goods` rows; it sets `lock_timeout` 5 s as its first act, so a trade that holds one of those rows longer makes the file roll back whole instead of waiting (the deploy winds the jobs down while a migration runs, so only a player's trade can). **Deploy at a quiet minute.**

**Open, not done:** the paired prod-shaped NPC simulation (the 18 courses add merchant candidate legs); the coordinates are not checked against Wikidata (`wikidata` is null for the three; run `fetch-coords` on a networked machine); the committed `scripts/build-world-growth.mjs` now refuses (24 nations against 23) and is stale (it lacks 0280's production regime and 0303's stock cut), so it was neither run nor edited; re-lighting `city_treasury_switch` on prod would seed every harbour, these included (a hazard that was there before, untouched).

## Proof

- **The migration's own self-assert** (catalog and cheap pure reads, one `do` block: the pirate part is ~0.15 s locally, the harbours block 8.3 s, the whole file about 8.5 s): every hunk once and reversing, ACL/volatility/definer/config/parallel/owner/language unmoved for the 14; md5 over every other function unmoved; the three readers server-only; only the two knobs added, as shipped; the nation, the one pirate (a second is refused by the unique index), ten wars and no other relation moved; four homes held by the pirates with the flag clock held; tax quoted 0 and depth 0.5 on exactly the four; the home trigger enabled AND biting (an un-homing is refused `E_HOME_CITY`); `port_is_free` exactly the four, none with the lever off (probe rolled back); `city_capital` null at the four and unchanged elsewhere; `nation_joinable` 10 of 11 (11 with the knob, probe rolled back); **the money proof by construction**: the transaction wrote no row to `players`, `treasury_flows`, `treasury_daybook`, `ledger`, `port_influence`, `events`, `player_storage`, `fleets` or `ships`, wrote exactly 3 ports and 3 purses (the counters see them: a positive control), and the three purses hold 0 and no flow names them. It never executes a game step and never digests a live row (docs/OPS_HEALTH.md section 4); the live paths are in CI.
- **Proof 45** (`scripts/db/proofs/45_the_brethren.sql`, 12 markers, run by CI's "the rest" leg): SHAPE, FREE_PORT, TAX_DOOR, LEVER, NO_CROWN, NO_NAVY, DOORS, SNAPSHOT, BOARDS, GUARD, INFLUENCE, MONEY. Real functions on probe companies: a company of Portugal at each home pays tax 0, fee 0, dues factor 0 (war), Lisbon asks tax and fee; `set_tax` at Port Royal `E_FREE_PORT`, at Lisbon `E_NOT_MAYOR`; `depth_day` leaves Port Royal at 0.5 with 3,000,000 invested and moves Lisbon; `crown_aid` aids a poor Portuguese city and not a poor pirate one and moves no pirate gold; convoys lit: ten fleet numbers, a circuit and ships for a crown, none for the pirates; navy lit: ten realms, stations for Portugal, none for the pirates; the doors with the knob false and true (Port Royal pays the founding, W unchanged); the snapshot's 11 and 10; the Countries board's 11; the Levels list's 10; the lever off and on; a foreign point at Port Royal reads as war and makes no mayor; W unchanged to the ducat.
- **Harness** `scripts/ops/harness/the-brethren/proof-0338.mjs` (local, never from zero, nothing written to the cache): RED FIRST (proof 45 on the world with no file: `function public.nation_joinable(uuid) does not exist`); DARK PARITY (`dark-scene.sql`, 15 lines before and after, all equal: the quotes at every other harbour for a company and a merchant, the crown of every other harbour, the ten capitals, the ten cargo curves and navy sizes, every other port of the snapshot, the old fields of the old nations, the Countries board, the Levels list, depth, old relations, the influence book (3 rows, 37,044 points), flows, W, stances); the real file and proof 45 green; **36 mutations, each red for its own reason** (23 aimed at the file's own self-assert, 13 at proof 45; two of those 13 are caught earlier, by the self-assert).
- **Every other proof, run on the file**: all 43 other proofs in `scripts/db/proofs/` (01 to 44; there is no 24), one rolled-back transaction each (the harness's `--with=`), in three runs, all green (the slow ones: 05 takes 173 s and 12 takes 149 s; the rest 8 to 44 s). The proofs that read the powers or the allegiance are in it (14, 16 to 23, 25 to 27, 30 to 37, 40 to 44); the ones that count the ten powers (18, 19, 33, 36, 37) now count the crowns. The harbours block, by its author before the splice, on the head world: proofs 04, 05, 08, 09, 12, 14, 15, 30, 32, 35 and 38 green, `scripts/check-ports.mjs` PASS (249 ports, 629 goods, 0 failures, 60 warnings; 64 before), and the world guard on the head plus the block alone printed exactly the 17 findings that are the pirate part and none about a harbour, good, offer, haul, market, tongue, population or reach.
- `tsc -b` clean; eslint clean on the touched files; `tests/flags.spec.ts` (bundled flags, variance), `tests/cityKind.law.spec.ts`, `tests/duplication.spec.ts` and `tests/sections.spec.ts` ("every migration proves itself", "a migration that re-cuts declares the supersede") green; `db:check-versions` ok.
- **Browser** (`npm run build` ok with the 322 migrations in the world image; `vite preview` on port 4195 at `localhost`, headless, one worker): `tests/greatPowers.spec.ts`, `tests/rank.countries.spec.ts` (11 rows; The Brethren 4 home), `tests/db.image.spec.ts` (the emitted image is certified by the world guard) and the picture spec: 14 passed; `tests/map.landfall.spec.ts` (no harbour mark in drawn water, 390 and 1440 wide), `tests/map.marks.spec.ts` (249 harbours, 251 marks at the world view in all four glasses: 249 plus the two seam copies, worked out first and now measured) and `tests/flags.spec.ts`: 20 passed. The official runner `node scripts/db/proof.mjs brethren`: world guard ok, 12/12 markers. Pictures at DPR 2, taken on the built world: `2026-11-07-the-brethren/codex-nations-wide.png` (Great powers 11, The Brethren with the skull, capital Port Royal), `rank-countries-wide.png` (Countries 11, The Brethren 4 home, 0 won), `picker-phone.png` (ten tiles, no pirates).

## PROD CHECKS (read-only; each file is one statement; run from the worktree)

Volatility first: `npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/the-brethren/volatility.sql` (wanted: every value `s` or `i`; the three new readers null before the deploy, `s` after).

- **Before:** `scripts/ops/harness/the-brethren/before.sql`. Run by me 2026-11-07 ~10:30 UTC at head 0337: every `fns[].old_times` 1 and `new_times` 0 (the 14 live bodies are the ones the hunks were cut against); `absent` all true; counts nations 23, great 10, relations 13, harbours 246, places 260; Port Royal held by nobody, not home, influence 0, mayors 0, tax_rate 0.03, depth 0.5; Sale held by ESP; guard `O`; the switches as listed. The `with_hunk_md5` per function is what the live body must hash to after the deploy.
- **After:** `scripts/ops/harness/the-brethren/after.sql`. Wanted: head `20260818000338`; every `fns[].new_times` 1; `now_md5` = before's `with_hunk_md5` and `without_hunk_md5` = before's `now_md5`; `attr_md5` equal to before's (prod against prod; the local world prints other role names); nations 24; great 11; pirate `PIR`; `pirate_flag` `☠|The Brethren|POR`; homes `["DJE","GOT","LGA","POR"]`; held 4; wars 10; relations 23; guard `O`; knob `false`; lever `true`; `homes_tax_quote` [0,0,0,0] (`harbours_quoting_zero` 4: no other harbour quotes 0); `stored_rates` [0.03,0.03,0.03,0.03]; `depth` [0.5,0.5,0.5,0.5]; every entry of `homes_since` not after before's `flag_clock`; harbours 249; `new_purses` [0,0,0]; `new_flows` 0; joinable 10; `free_ports` the four; `capital_null_at_homes` true; `convoy_rows` 10; `fleet_sizes_pir`, `cargo_ships_pir`, `navy_realms_pir` 0.
The 14 live bodies, hashed on prod at head 0337 by `before.sql` (the first 10 hex of each md5), and what each must hash to after the deploy. **The local pre-image of every one is byte-identical to prod's** (the hashes of the local world, with the hunk taken out, equal the ones above), so the hunks were proven on prod's own text:

| function | live now (prod 0337) | wanted after the deploy |
|---|---|---|
| `cmd.change_country` | ef9ad6995e | f92d5dd864 |
| `cmd.found_house` | 5dd2f9a37c | fe6a8c0833 |
| `cmd.set_tax` | 0b8e90afa9 | e1d222859a |
| `public.city_capital` | bdc427aedb | e761d782bb |
| `public.convoy_ships_wanted` | 8beeb2e269 | 85747943fd |
| `public.depth_day` | 3e99c644a2 | cfe98a6752 |
| `public.navy_plan_step` | 3cf68cae91 | ca5844ae24 |
| `public.navy_read` | 5855601d70 | 4334b93c79 |
| `public.port_dues` | 32c251c758 | 7c0f67f969 |
| `public.port_fee` | 8381a786cd | f81cd93c8d |
| `public.tick_cargo_ships` | 3ba57fa06f | 9df1d29b78 |
| `world.levels` | 9a040ab889 | de42b140e0 |
| `world.snapshot` | d6b88ea524 | 47de4c9aee |
| `world.tax_rate` | 050cbe852e | 01bfcd04df |

- `bash scripts/ops/health.sh` after the deploy.

**After the deploy: a 30-minute after-check** (the free ports change play): the city job `byeharu-voyage:city` and `cargo-ships` durations unchanged (the file rebuilds no circuit: the flag clock did not move), no `E_*` spike in the order log, Port Royal's, Lingga's, Goto's and Djerba's trades and purses (read-only), and the NPC routes through them. **Forward rollback, ready:** `update public.world_config set value = 'false'::jsonb where key = 'pirate_ports_free'` (owner only; auto mode may refuse the write: then it is his `!` command). That puts the four back among the cities at once; `depth_day` walks their depth back to the formula at 10 % a day. To close the joining door again, `pirates_joinable` is already false.

## Not verified

- The migration on a real Postgres with the clock unwound: PGlite is Postgres 18 compiled to wasm; CI's `disposable-chain` is the real engine for this file (the runner there is statement by statement; the file is one block).
- What the free ports do to the NPC merchants' routes and to Port Royal's 993 M d. purse over a day. No switch is lit by this file, but four ports change; the after-check reads it.
- The Korean sweep does not cover the Nations face (above).
- The pixel look of the skull at 14 px is measured by variance, not seen on the chart.

## Rollback

The free ports: the lever. The joining: already off. The rest, forward and owner only: a NEW migration swapping the hunks (each OLD text is in the file) and dropping nothing else; the nation, the four homes and the three harbours are a **one-way door** once a city has been won, a company founded or a trade made there.
