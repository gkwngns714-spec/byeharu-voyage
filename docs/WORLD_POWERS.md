# WORLD POWERS: standing, levels, armed cargo ships, player war fleets, timed battles, navies, pirates


**Owner answers, 2026-11-05:** a player MAY join the pirates ("yes they can"); whether a pirate player may attack other players' merchants stays open, and the no-PvP law stands until answered. City reserve: capitals are sized and filled first. Bank #484 on hold.
**Status: DESIGN, build-ready, 2026-11-05. Nothing here is built. No migration, no code, no prod write.**
Prod head at writing: **0312**. All prod figures are pure SELECTs of 2026-11-05 about 08:30 UTC. Slices have names, not numbers: each takes prod head + 1 when cut.
**Owner rows:** 282-288, plus the ship-looks order of the same day (row 291). Every "decided by default" is mine; the owner reverses afterwards.
**Base docs:** `docs/CITY_CONVOYS.md`, `docs/PIRATES_AND_HAVENS.md`, `docs/GREAT_POWERS.md`, `docs/INFLUENCE.md`, `docs/FLEETS_AND_SLOTS.md`, `docs/CLOSED_ECONOMY.md`, `docs/DESIGN.md`. Where this doc differs, this doc is the owner's newer word (section 11 lists each difference).

The owner's orders, short:
- *"we need to build systems such as affinity prior to the system ... levels and stats for characters as well as ships ... these factors will be the power and ability of each company / ships. captains should also have stats"*
- *"rich cities should send cargo ship"*; *"not instantly. it should see on the map"*; *"cargoship should have defense and attacking power too"*; *"people can attack these npc"*
- *"each npc ships should have city of origin set ... respawn at their origin city, funded by the city"*
- *"players can make fleet - navy - style for pirate attack, or even attack countires which would then lose affinity to that country, and the navy of that country may attack your merchant fleet"*
- *"if a fight is made in pacifics, it would need a longer time for the navy to defend ... how would we design this?"*
- *"pirates are like countries - power, where they can also invest. pirate merchants too ... pirate port that has no tax, cheaper products"*
- *"the ship type (cargo, merchant, navy) should be distinguished, as in graphics or as in color. day and night"*

---

## 0. The answer in fifteen lines

1. Most foundations already exist but are switched off or unserved. The only new one is **standing with a country**, one small table (section 2).
2. **Levels:** the three company tracks, ship levels and captain levels all exist. `levels_bite` is **off**, so every level in force is 1. Lighting it is the owner's call and comes first.
3. **Captains** have a grade, traits and three levels, and the fight already reads them. They lack a stat sheet. It is a read, not a table.
4. **One engine change:** `voyage.fight_resolve` takes raiders as a strength. It must take real hulls on both sides. Nothing else about the fight changes.
5. **Cargo ships** stay the one path for aid. Lit, they load at rich cities, carry guns and 60 crew, and both instant paths stop.
6. **Origin** already exists for merchants and cargo ships (`home_port_id`). The missing part is one reader, plus a wreck rule: partial loss, then respawn at origin paid by that city.
7. **A war fleet** is any fleet with guns and an empty hold. No new fleet type. A player needs a second fleet first, and no player can make one today (`FLEETS_AND_SLOTS` F1, F2 are unbuilt).
8. **`ATTACK`** starts a **battle**: a row, about 10 real minutes, resolved once at the end by the one fight engine, in its own minute job.
9. **Loot** is capped: 15 % of what is aboard, at most 60,000 d. a ship and 240,000 d. a company a real day. It is moved money, never made.
10. **A navy** is a set of real ships based at regional stations, paid by the capital, sized by the country's purse. 75 ships at today's purses.
11. **Reach:** capitals alone reach 181 of 246 harbours in 10 minutes. Nine more stations reach 242. No capital reaches the Pacific coast of the Americas, so stations go there.
12. **What cannot be reached becomes WANTED:** the country's navy may fight that player's fleets later, rolled and frozen at departure, the way a raid is.
13. **Pirates** are an 11th great power on the existing tables. Their purse is their city purses. Plunder really moves: goods into their stock, gold into their purse. That makes their goods cheap, with no second price rule.
14. **Fix insurance first:** in the last 24 h cities paid out 29.5 M d. and took in 7.4 M d. Pirates would widen that. **Cause proven 2026-11-05: a bug, not a price; migration 0314, `docs/dev-log/2026-11-05-insurance.md`.**
15. **Each kind of ship gets its own hull and mark, day and night,** through the one renderer, chosen by a `kind` from the server (section 9).

---

## 1. What exists and what must be built (checked on the live chain)

| Asked for | Exists today | State | Must be built |
|---|---|---|---|
| Company levels | `public.player_progress` (0069, 0127): Trading, Exploration, Combat, derived from ledger and reports, curve `level_from_points` to 20. `title_level` = lower of Trading and Exploration, cap 11 | **Live for Trading, Exploration.** Combat answers level 1, `playable` false, while `levels_bite` is off | Nothing but lighting, and new fight points |
| `level-track` | `YouScreen.tsx` `Track`, `data-testid="level-track"`. Combat bar only when `playable` | Live | Nothing |
| `players.company_level` | Column, every row 1, no reader decides anything by it (`src/lib/db/README.md`, ProfileScreen) | Dead | Leave it. Do not build on it |
| Ship levels | `public.ship_xp` (max on prod 225 = level 4), `world.ship_stats` adds accuracy, handling, sighting per level | **Dark.** `level_in_force` = 1 | Lighting |
| Ship stats | `ship_classes` 103 classes: speed, hold, durability, armour, attack, accuracy, reach, sighting, wave, crew; rolled per hull (`ship_base`, 0276); gear (`item_effects`); skills (`skills_bite` on) | **Live** | Nothing |
| Character | No player character. Tracked people are captains. The title is "the captain level" (0215) | Live | Decided by default: "character" = captain |
| Captain stats | `captain_grades` C B A S, `captain_xp` (three levels per signing, capped by the company's), 25 traits, `crew_pct`, seats. Gunner and Boarder feed the fight (`combat_bite` on) | **Live, levels dark.** No sheet of figures | One read |
| Affinity company-country | **None.** `affinity` in the chain means a good's price term. `power_relations` is nation to nation (13 rows: 5 ally, 6 rival, 2 war); `power_stance` reads it; `country_factor` (home 0.25, ally 0.5, peace 1, rival 2, war 2) is on tax and dock fee. `port_influence` is points per port, player, nation. The hall's "Relationship" shows the stance | Live, nation level only | **New: company standing** |
| Fight engine | `voyage.fight_resolve` (0189, 0202), lit: sizing up, sighting, 6 rounds, boarding. Called only from `voyage.settle`'s PIRATES arm | **Live.** One sided: raiders are a number, built as xebecs inside | Hulls on both sides |
| Player attack | **No command.** `cmd.*` has no attack verb | None | New |
| Second player fleet | `form_fleet` exists; only founding calls it. No `house_room`, no `cmd.move_ship`. Prod: 19 humans, 19 fleets, 22 ships | **Not built** | F1, F2 of `FLEETS_AND_SLOTS` |
| Cargo ships | 0308, 0309, 0310 live. Table, circuits, funds book, map, card, Stats. Job `byeharu-voyage:cargo-ships` active. **`convoys_enabled` false, 0 ships exist** | Dark | Rich-city loading, arms, crew, wreck rule |
| Origin city | `npc_houses.home_port_id`, `cargo_ships.home_port_id` | Live | One reader |
| `port_nation`, capitals, crown | `port_nation`, `city_capital`, `crown_aid`, `crown_call`, `treasury_post`, `mint_guard`, `credit`, `city_pays` | Live | Reused |
| Economy closed | `economy_closed` true | Live | Every flow below must be moved |
| Great powers | 10 in `great_powers`, three foreign keys, 4 homes each, guard trigger | Live | One more row |
| Havens, pirate fleets, escorts | `PIRATES_AND_HAVENS` design only. No `sea_danger`, no `pirate_*` table, no HAVEN port | Not built | Section 7 |
| Raids | PIRATES hazard rolled per voyage-day, frozen by the voyage's seed. RANSOM takes **no money** today: `voyage.settle` writes nothing for it, whatever `PIRATES_AND_HAVENS` §3.4 says. PLUNDERED takes 25-50 % of goods, and they vanish | Live | Plunder moves |
| Insurance | 0213: premiums and payouts from city purses | Live, **mispriced** | Knob, section 7.6 |
| Map rule | Merchants and cargo ships drawn. Rival players never. Law 3 amended 2026-08-23 | Live | Section 9, 10 |

**Who can fight today:** richest human 2,104,465 d., next 235,000 d.; all six richest sail tier 1. Cheapest armed hull is 160,000 d. (`xebec`, attack 60). **Three of 19 can afford one. One can afford two.** All humans hold 3,329,555 d., merchants 10.38 B, cities 23.3 B.

---

## 2. Part 1: foundations

Owner's order: these come first. Build nothing that fights until W1-W5 of section 12 are done.

### 2.1 Standing: the company and a country

The word in the database is **regard**, because `affinity`, `stance` and `standings` are taken. The player reads the existing **Relationship** / 관계.

```
public.house_regard (player_id, nation_id, points numeric, as_of timestamptz, primary key (player_id, nation_id))
```
- Only earned points are stored. The rest is derived, so a merchant has no row and pays no cost.
- **One reader:** `public.regard_of(player, nation)` = `stance_base + points × 0.5 ^ (hours since as_of / regard_half_life_hours)`.
- **One writer:** `public.regard_add(player, nation, delta, reason)`: folds the decay in, adds, writes event `REGARD_CHANGED`.
- `stance_base` comes from `power_stance`: home +200, ally +100, peace 0, rival -100, war -200.
- A decayed read needs no job and no beat cost.

| Band (EN / KO) | Score | Effect |
|---|---|---|
| Honoured / 명예 | 500+ | Tax and dock fee × 0.8 |
| Friendly / 우호 | 150 to 499 | × 0.9 |
| Neutral / 중립 | -149 to 149 | × 1 |
| Wary / 경계 | -299 to -150 | × 1.25 |
| Hostile / 적대 | -300 or less | × 2, and that navy may attack (section 6) |

The multiplier sits on `country_factor`'s result, in `world.tax_rate` and `public.port_fee`, one hunk each, read only for a human company. **A Hostile company is never refused a dock:** a refusal could strand a fleet (`docs/STRANDED_AT_SEA.md`).

| Event | Change, with that country | Knob |
|---|---|---|
| Attack its cargo ship | -150 | `regard_attack_cargo` |
| Attack its navy ship | -250 | `regard_attack_navy` |
| Sink one of either | -100 more | `regard_sink` |
| Donate or invest in a city it holds | +10 per 100,000 d. | `regard_per_100k` |
| Drive off a pirate ship | +30, every great power | `regard_pirate` |
| Clear a pirate port or haven | +150, every great power | `regard_pirate_port` |
| Pay a fine | +1 per 200 d. | `regard_fine_per_point` |
| Trade at a pirate port | -5 per trade, own country | `regard_pirate_trade` |

**Money:** `FINE` is a moved kind, player to that country's capital, through `public.pay_city`. Nothing minted.
**Cost on the beat:** none. One primary-key read per human tax quote. A merchant's quote short-circuits on `is_npc` before the read.
**Dark:** `regard_enabled` false, multiplier 1, `regard_add` writes nothing.

### 2.2 Company levels and character levels

Decided by default: **the company's level is its three tracks, a character's level is a captain's three levels.** No fourth number. `company_level` stays dead.

- **Light `levels_bite`** (owner only). It moves hull handling, accuracy, sighting; captain bonuses; slot locks (`E_SLOT_LOCKED`, `E_SHIP_LEVEL`); the Combat bar appears.
- **Measure before lighting:** per company, what each stat moves and which fitted item would lock. 19 companies, a read. A locked item already fitted must stay fitted. Proof red-first.
- **Cost warning:** `captain_level` calls `player_progress` above level 1, which scans the company's ledger and reports. Lit, that runs for humans in settle. Measure per call on prod-like I/O; if over 50 ms, cache the tracks in a side table written at arrival.
- **Combat points:** `fight_points` (EVADED 5, DRIVEN_OFF 15) gains `BATTLE_WON` 20, `SHIP_SUNK` 30, `PIRATE_PORT` 60. `title_level`'s comment already says Combat joins once playable: decided by default, it stays out, because a trader who never fights must not lose her title.
- **What levels buy:** already wired. Ship accuracy, sighting, handling; captain bonus × (1 + 2 % a level); fleets and ships by `earned_caps`. No new effect. *"These factors will be the power and ability"* is met by lighting what exists.

### 2.3 Ship levels and stats

All exist. Two additions:
- `world.ship_view` serves a **Power** line: attack, accuracy, reach, armour, sighting, hull, crew, already all computed. Client only.
- `FLEETS_AND_SLOTS` §2.5's fleet line gives fleet totals.

NPC hulls: merchants already have constant levels (`npc_fix_level`). Crown and pirate hulls take a fixed level by knob, `npc_ship_level` 5.

### 2.4 Captain stats

A sheet, derived, stored nowhere: `world.captain_stats(signing)`, read by the existing captain card.

| Stat (EN / KO) | Value | Comes from |
|---|---|---|
| Gunnery / 포술 | Combat level + grade floor × seated Gunner share | `captain_level`, `crew_pct(accuracy, reach)` |
| Boarding / 백병 | Combat level + grade floor × seated Boarder share | `crew_pct(attack)` |
| Seamanship / 항해 | Exploration level + speed, storm and supply shares | `crew_pct(speed, storm, supplies)` |
| Trade / 교역 | Trading level + hold and spread shares | `crew_pct(hold, spread)` |
| Care / 돌봄 | Surgeon share + Hospitality | `crew_pct(crew_saved, homesick_relief)` |

The sheet changes no fight: the fight reads the same `crew_pct`. **Decided by default:** no new stored stat, because a stored stat would be a second authority beside `trait_effects`. NPC crown ships have no captains; their hulls fight on class, level and gear.

### 2.5 The fight takes two sides

`voyage.fight_resolve(voyage, day, raider numeric, escort, ships)` builds raiders inside from `fight_raider_class`.

| Change | Rule |
|---|---|
| New pure core | `public.fight_sides(seed uuid, round int, a jsonb, b jsonb, opts jsonb)`, hulls on both sides in the `p_ships` shape |
| Old function | Becomes a skin: build xebecs (one builder, `voyage.raider_hulls`), call the core, answer in today's shape |
| Both sides lose hull | Returns `hull_lost` for both, by ship id |
| Parity | Dark, 0202's 960-day probe: every fight word for word |
| Guard | The core reads no table but `world_config` |

**Rollback:** the skin keeps the old answer; a forward migration restores the old body from the file's hunks.

### 2.6 Part 1 slices

| Slice | Content | Red-first proof |
|---|---|---|
| **W1** `a_house_has_a_regard` | Table, reader, writer, bands, multiplier hunks, `FINE`, hall line. Dark | Quote dark equals pre-image; lit probe gets each band's factor; decay is exact at one half-life; a merchant reads no row; no minted kind |
| **W2** `levels_are_lit` | Measurement dev-log, the guard for fitted items, then the owner's switch | Fitted item stays; a stat moves by exactly the knob; title unchanged; `player_progress` cost printed. 30-minute after-check |
| **W3** `a_captain_has_a_sheet` | `world.captain_stats`, card lines, Power line | Sheet equals `crew_pct`'s own answers for a probe crew; a fight is byte-identical with and without the read |
| **W4** F1 + F2 of `FLEETS_AND_SLOTS` | Room counted, a ship changes fleets | That doc's proofs |
| **W5** `a_fight_has_two_sides` | Core, skin, builder; `scripts/ops/harness/raid/sim.mjs` runs on it | 960-day parity; both sides' `hull_lost`; core names no table |

---

## 3. Part 2: armed cargo ships, origin and loss

### 3.1 Rich cities send the ships

| Step | Today (dark, V2) | Lit after this design |
|---|---|---|
| Who is short, how much | `crown_aid`, `city_aid_target` | **Same** |
| Where the gold comes from | Instant `CROWN_CALL` into the capital, then a ship loads there | **No call.** A ship loads at its **origin**, a rich city of the realm |
| Delivery | Tops each city to target | **Same**, and the capital is a stop like any other |
| What is left | Back to the capital | **Back to the origin** |

- **Rich city:** the top `convoy_rich_ports` (3) harbours of the realm by `crown_call_room`, the room that already keeps a donor above about an hour of payouts plus its reserve.
- **Origin:** set at commissioning, round-robin over those 3. Decided by default: re-based only after a ship has lain idle 7 real days, by one sailed leg, never by teleport.
- **Load:** `min(realm need - funds aboard, crown_call_room(origin))`. `CONVOY_LOAD` from the origin's purse. One ship a run, as 0309.
- **Circuit:** `cargo_circuit_plan(nation, start)`: same stops, starting and ending at the origin.
- **Same nation only** (default). BUS holds 6.1 M in its whole realm, so little helps JOS; ally aid is a later knob, and an owner question.

**No second path, as hunks:**
1. `crown_aid`: the `convoys_on()` branch moves above `crown_call`, so lit, the city call never runs.
2. `cargo_ship_step`: `city_capital(port) = home` becomes `port_nation(port) = ship's nation`. A capital becomes a normal stop.
3. **A second writer of `CROWN_CALL` exists:** the 0234 capital-pays body for gifts and starting money. Lit, a gift pays from what the capital holds, else `GIFT_WAITING`. Founding keeps `p_must` (the world's richest harbour), because a sign-up must never fail.

**Warning already in the dev-logs:** lighting stops instant aid at the next `:37`, and cities late on a circuit wait up to about 5 hours for the first ship. The 03:37 run also showed funds spent within the hour, so ships change when funds arrive, not how many are needed.

### 3.2 An armed class

**Decided by default: `convoy_ship_class` from `qpinnace` to `navire` (Navire marchand).** Prod figures:

| | `qpinnace` (today's knob) | **`navire`** | `nau` |
|---|---|---|---|
| Attack, guns | 0, 0 | **130, 13** | 120, 12 |
| Accuracy, reach, armour | 0, 28, 2 | **59, 70, 30** | 55, 70, 30 |
| Hull | 280 | **1,800** | 1,800 |
| Crew needed, max | 6, 16 | **60, 140** | 60, 140 |
| Speed, kn | 21.3 | **13.8** | 13.2 |

- **Why `navire`:** it beats `nau` on guns and speed at about the same price (630,000 d. against 600,000 d.). A lone `xebec` has less than half her attack. Who wins is for the sim, section 12.
- **Speed:** 237 nm a minute was a crewless `qpinnace` at 0.7. Crewed she would do 341, so about 16 nm a minute per knot. `navire` crewed: about 221. Laps grow about 7 %. Arithmetic, not measured.
- **Build cost:** none. No ship exists, and she is commissioned empty as a built hull, unpaid, as V1. Decided by default: 50 hulls are a world object, not a purchase; she costs money only when she dies.
- **Crew and stores:** crew 60 means wages and stores, and her house has no purse. `owe_wages` would carry forever. **Rule:** at each departure her origin pays `convoy_upkeep_per_leg` (500 d.), moved, to the harbour she leaves; her wages and stores count as paid by that; stores are topped up free in the same hunk. At about 300 stops an hour (0308) that is about 3.6 M d. a day worldwide, from rich cities to the harbours she calls at. The upkeep knob was left out of V1 for this.
- **Size at 5 ships a realm:** 50 ships. ESP, JPN, MUG already show a 2-hour gap every 6 hours (0309). Unchanged; `convoy_ships_per_nation` 6 closes it. Owner's knob.

### 3.3 One reader for origin

`public.fleet_origin(fleet)`: `cargo_ships.home_port_id`, else `npc_houses.home_port_id`, else the new navy and pirate tables, else null for a human. **No new column.** It stands beside `public.fleet_kind`.

### 3.4 What a loss is

Applies to every NPC ship: merchant, cargo, navy, pirate.

| Result of a fight | Hull | Cargo goods | Gold aboard | Crew |
|---|---|---|---|---|
| Drove them off | The fight's `hull_lost` | None | None | -2 % |
| Paid them off (RANSOM) | Fight's | None | Share `ransom_share` 8 %, new | None |
| Boarded (PLUNDERED) | Fight's | 25-50 % (`raid_takes`) | 15 % capped, section 4.4 | -10 % |
| Hull reaches 0 | 0 | Rest is lost at sea, value only in Stats | Loot share, then **all the rest back to origin** | Refilled at refit |

**A ship at 0 hull, the "wreck":**
1. The battle closes. Her loot is paid, her book closes `RETURNED` to the origin's purse (`convoy_book`, one writer).
2. Her voyage ends. She is placed at her origin, status `UNABLE_TO_SAIL`. This is a respawn, not a voyage: event `RESPAWNED`, drawn nowhere until she sails.
3. Each hour `npc_refits` asks her origin to pay `npc_refit_share` (0.25) × class build cost: `navire` 157,500 d.
4. **Paid:** hull whole, crew filled from the port's pool, ready after `npc_refit_minutes` 30.
5. **Broke city waits:** she lies there and is retried hourly. Only cities with more than the cost and their reserve pay (`city_surplus`). Event `REFIT_WAITING`, once a day.

**Who gets the refit money:** paying yourself moves nothing. `REFIT` is two `treasury_post` rows, origin to `public.refit_yard(origin)`, the nearest harbour with a yard, not itself, same nation first. Moved. A shipwright elsewhere earns it.

**Merchants:** the owner's words say the city pays, so the city pays, though a merchant's purse (p50 962,642 d.) could. Her cargo is insured as today. Her route resumes from origin: she re-joins through `npc_tend_route`.

**The goods lost in a wreck** have no owner and vanish from stock figures, as PLUNDERED goods do today. No gold is involved: money stays closed. Goods are not, and never were.

### 3.5 Cost, rollback, slices

**Beat:** 50 ships add about 5 arrivals a minute against about 57 merchants' (0308, rough). Prod beat, last 30 minutes: p50 242 ms, p95 842 ms, 621 voyages sailing. `cargo_ship_step` and `npc_refits` run in their own jobs, not the beat.
**Rollback:** `convoys_enabled` false: instant aid returns the same hour; ships sail home and return funds (0309 proved it). No gold is stranded.

| Slice | Content | Red-first proof |
|---|---|---|
| **W6** `every_npc_ship_has_an_origin` | `fleet_origin`, `npc_refits` job, `REFIT` moved kind, wreck rule, `refit_yard`, `ransom_share`, all dark | Probe wreck: book closes, every purse summed moves 0; broke city waits and retries; pays once; no hull restored unpaid |
| **W7** `rich_cities_send_the_ships` | Origin at commissioning, circuit from a start, load at origin, the three hunks of 3.1 | Lit probe: no `CROWN_AID`, no `CROWN_CALL`; donor above its room; capital tops up as a stop; dark equals pre-image |
| **W8** `the_cargo_ship_is_armed` | Class knob, crew, upkeep, stores, sim printed | A real lap in proof 19's shape: no debt, no forced home, upkeep moved; `voyage.fight` at four strengths; speed printed |
| **W9** Light | Owner's switch, then `E_CITY_BROKE` and bids for 30 minutes | Forward rollback ready; 5-hour first-lap warning repeated to the owner |

---

## 4. Part 3: player attacks

### 4.1 A war fleet

**A war fleet is a fleet with attack above 0 and an empty hold.** That is the owner's "navy style", with no new table and no gate beyond the guns (he has reversed every gate I invented). The fleet line (`FLEETS_AND_SLOTS` §2.5) shows **War fleet** / 전투 함대, derived.

### 4.2 The verb

**`ATTACK <fleet> <target>`**, one more verb through `cmd.parse`, `cmd.preview`, `cmd.issue`. The target's sheet (`CargoSheet`, the merchant card, new navy and pirate cards) offers **Attack**, handing the intent to the same composer: section 10.

| Who may be attacked | Allowed | Regard |
|---|---|---|
| Cargo ship at sea | Yes | -150 with her nation |
| Navy ship at sea | Yes (owner) | -250 |
| Pirate ship at sea | Yes | +30 with all |
| Pirate port | Later, section 7.5 | +150 with all |
| Merchant of a country | **No, default** (owner question 2) | |
| Another player's fleet | **Never** | Section 10 |
| A city | **No.** A country is attacked through its ships | |
| Anything docked | **Never** | |

**Pre-conditions, each its own refusal:** `E_NO_GUNS`, `E_HOLD_NOT_EMPTY`, `E_TARGET_DOCKED`, `E_OUT_OF_REACH` (prints the distance), `E_SHIP_FOUGHT_THIS_LAP`, `E_ATTACK_COOLDOWN`, `E_FLEET_BUSY`, `E_YOUR_OWN_COUNTRY` (default: you may not attack your own nation's ships; owner question 3).

**Reach:** `attack_reach_nm` 240, about a minute's sail. Measured from your fleet's point (`voyage.position`, or its port or anchor) to the target's `voyage.position`, as the crow flies. A ship does about 220 nm a minute, so a passing ship is in reach for about two minutes: you lie in wait near her route, which the map shows.

**Limits:** one attack a ship a lap (`cargo_ships.last_attacked_lap`; for other kinds 60 minutes). A fleet may start one battle in `attack_cooldown_minutes` 30.

**Preview** prints the sides, never a forecast: the word from `voyage.escort_score` bands (weaker, about even, stronger, far stronger), her funds as a band only, and **"Navy arrives in about 6 min"** when one would.

### 4.3 Who pays what, in order

The battle runs (section 5). At its end:

| Outcome for the attacker | Gold | Hull, crew | Regard |
|---|---|---|---|
| Boarded her | Loot, 4.4 | Fight's | Full |
| She paid off | `ransom_share` of aboard | Fight's | Full |
| Beaten or broke off | None | Fight's, crew -10 % | Full (the attack was made) |

Goods on a merchant or pirate target move to your hold only if there is a rule for it: **v1 takes gold only** (an empty hold is the entry rule). Decided by default.

### 4.4 The loot limit

Owner: players hold 3.3 M d. in all; a ship carries about 380,000 d. (0308's estimate, 19 M aboard over 50 ships, high because of the backlog). Taking it all would double the players' money in nine ships.

| Knob | Default | Why |
|---|---|---|
| `loot_share` | 0.15 | Partial, as ordered |
| `loot_per_ship` | 60,000 d. | About 15 % of 380,000 |
| `loot_per_company_day` | 240,000 d. | Four good ships |

**The worst day:** every human at the cap is 4.56 M d., moved from funds aboard to player purses, 1.4 × all players' money. It takes 19 war fleets; today one player can afford a pair. It is the owner's knob and a Stats line (`LOOT`, 24 h).

**Money:** `LOOT` is moved. Funds aboard (inside `set_aside`) to the player through `credit`. `convoy_cargo` gains a closing state `LOOTED`; `tg_convoy_cargo_closes` accepts it; the rest sails on or returns. Σ purses + set aside unchanged to the ducat.

**The real sinks** against loot: hull 160,000+ d., repair, crew, one battle in 30 minutes, the fine for regard.

### 4.5 Protection

| Situation | Rule |
|---|---|
| Docked at a harbour, any fleet | **Never attacked, by anyone.** The harbour's peace |
| Under repair | Same |
| At sea, player offline | Only NPC fights. Rolled at departure from a frozen list, so a voyage started while not Hostile stays safe to its end |
| Hostile, at sea | Navy may fight her: at most one a voyage |
| Player's own attack | Her war fleet fights whether she stays online or not. Battle runs on the server |
| Flagship | Never captured, no hull ever taken (DESIGN B.6 stands) |

**A way back:** wait (half-life 72 h); pay the fine at that nation's capital (`cmd.pay_fine`); donate or invest there; hunt pirates. No permanent mark. A company that changes country keeps its regard rows.

### 4.6 Cost, rollback, slices

**Beat:** none. `cmd.attack` is a door, the battle job is its own. Reach reads `voyage.position` twice per attempt.
**Rollback:** `attack_enabled` false: the door refuses `E_NOT_IN_USE`. Battles under way finish. Regard and loot already written stay.

| Slice | Content | Red-first proof |
|---|---|---|
| **W11** `a_player_attacks` | `cmd.attack`, `preview_attack`, loot, `LOOT` kind, regard hooks, card button, report, words | Every refusal; loot never above any cap; moved 0 across purses and set aside; one attack a lap (PGlite has one connection, so the race is reasoned and said so in the dev-log); dark door refuses; a docked target is refused |

---

## 5. Part 4: timed battles

### 5.1 The owner's Pacific question

**Today, by sailed distance on prod (`sea_reaches`, flags of today):**

| From | Harbours within 2,400 nm (of 246) | Not reached |
|---|---|---|
| The 10 capitals | **181** | Pacific Americas 18, North America 7, Caribbean 10, West Africa 9, South America 7, Oceania 6, East Africa 6, others 2 |
| Capitals + 9 stations (Cartagena, Guayaquil, Elmina, Island of Mozambique, San Francisco, Buenos Aires, Banten, Boston, Jeddah) | **242** | Auckland, Hobart, Sydney, Wellington |
| Each power covering its own cities | 46 stations in all | Listed in 6.2 |

**The Pacific coast: none of its 18 harbours is within 2,400 nm of a capital, and 17 are beyond 4,800 nm.** A navy based at home can never arrive.

**So three layers:**
1. **A stopwatch:** a battle takes about 10 real minutes.
2. **Regional stations:** ships are spread where trade is, not at home.
3. **WANTED:** what no ship can reach is answered later.

### 5.2 A battle is a row

```
public.battles (id, kind, site jsonb, attacker_fleet, defender_fleet, started_at, resolves_at,
                status: FIGHTING | RESOLVED | BROKEN_OFF, seed uuid, result jsonb)
public.battle_sides (battle_id, fleet_id, side, joined_at, arrives_at)
```
- `battle_seconds` 600. The owner's "about 10 real minutes".
- **Both fleets stop.** `fleets.status` gains `IN_BATTLE`; orders queue, as in `REPAIRING`.
- **A sailing ship is held.** Her voyage takes a `BATTLE` row with `delay_hours` = battle length × `time_compression` / 3600, through `voyage.recompute_eta`, the path STORM uses. So law D.2 holds: position stays a pure function of the row and time. **This is the riskiest hunk here.** Prove the point stands still and arrival moves by exactly the delay.
- **Resolved once,** at `resolves_at`, by `public.tick_battles`, its own minute job. One call of `fight_sides`, every side present. Seed: (battle id, 1). No per-round state, so no beat cost and no drift.
- **Reinforcement:** a ship joins if `arrives_at <= resolves_at`. She takes a real voyage to the nearest harbour of the site and is on the sheet.
- **Break off:** the attacker may leave at any time: `BROKEN_OFF`, no loot, her fleet takes one round's fire at long range, regard loss stands.
- **Offline:** resolved by the job alike.

**The player sees:** on her fleet card, **"In battle 7:24"** and **"Navy arrives 5:10"**; a written report at the end, in the `payloadFights` shape, read by the existing History tray. On the map: the two ships stopped, nothing moving. No animation (section 10).

**Why 10 minutes works:** a war hull at 14.4 kn does about 230 nm a minute crewed (arithmetic from 341 at 21.3 kn), so 10 minutes is about 2,300 nm; the owner's figure was 2,400 at 237 from a crewless pinnace. Knob `battle_seconds`.

### 5.3 WANTED

`public.wanted (player_id, nation_id, battle_id, since, until)`, one row per battle whose nation arrived too late or not at all, or where the attacker won. `until` = since + `wanted_hours` 48, or a paid fine.

**WANTED is regard plus memory:** a Hostile company is hunted; a WANTED row makes that twice as likely. No second rule.

**The roll, at departure, frozen:**
- `voyage.depart` for a **human** fleet with a WANTED row or a Hostile regard writes a small side row: `voyage_hostile (voyage_id, nation_id, chance)`. No row, no cost. Merchants never reach it.
- `voyage.hazard_roll` gains kind `NAVY`, for a voyage with that row, on days in waters within `navy_reach_nm` of that nation's station, chance `navy_hunt_per_day`.
- `voyage.settle`'s new NAVY arm fights her with one real ship of the station, through `fight_sides`, at most once a voyage.
- It is the same shape as PIRATES: settled late, it rolls the same. The offline-equivalence law stands.
- **The Pacific answer:** she fights Spain's ship off Callao, wins, sails on. Spain's ship cannot reach her. For 48 h any voyage through Spanish station waters may meet that navy, wherever she trades. If her route stays away, she is safe, and she paid in regard and fines.

**What the navy takes from a player's merchant fleet:** the PLUNDERED table, cargo 25-50 %, crew -10 %. Goods go to the nation's capital stock. A **fine** of 5 % of her cargo value, capped 100,000 d., capital's purse, moved. Hull by the fight, never below 25 % (`navy_hull_floor`). Insurance pays what it covers, from the same purses. Decided by default.

### 5.4 Cost, rollback, slices

**Beat:** none for the job. One indexed read of `battles` a minute. `depart` gains one read per human departure. Expect a handful of battles a day. Worst case 19 at a time.
**Rollback:** `battle_seconds` cannot fall mid-fight; `attack_enabled` false stops new ones and running ones finish. `navy_hunt_per_day` 0 stops the hunt.

| Slice | Content | Red-first proof |
|---|---|---|
| **W10** `a_battle_takes_ten_minutes` | Tables, status, hold, job, report, card clock; probe battle only | A held voyage's position is unchanged across the battle; arrival moves by the delay; job resolves once under a retry; `voyage.position` parity on every non-battle voyage; offline proof unchanged |
| **W14** `wanted` | `wanted`, `voyage_hostile`, NAVY arm, fine, words | Same settled twice is identical; no read for a merchant; floor holds; a voyage started before Hostile never meets it |

---

## 6. Part 6: navies

**This part comes before pirates in this doc because navies are built first** (section 12).

### 6.1 What a navy ship is

As a cargo ship: a real `fleets` row, one hull, a house of her own (`is_npc`, purse 0), a row in **`public.navy_ships`** (fleet, house, nation, station, mission, ord), none in `npc_houses`. `fleet_kind` answers `NAVY`; `sea_houses` serves her with `kind`. She is outside tend, invest, gift and refund, by the 0308 table.

**Hull:** `navy_ship_class` = `galion` (attack 250, hull 2,800, crew 130, 14.4 kn, 1,156,000 d.). A power's own line if it builds one is a later data change.

### 6.2 Size follows the purse

`navy_size(nation) = min(navy_max 24, 2 + floor(sqrt(realm purse / 25,000,000)))`, read daily with the other daily settings. Realm purse = Σ `treasury_balance` over its harbours.

| Power | Realm purse, M d. | Ships | Stations, in coverage order |
|---|---|---:|---|
| PRT | 4,400 | 15 | LIS, MOG, MAC, REC, LUA, COL |
| FRA | 3,365 | 13 | MRS, BOR, BEL, LAG, NUU |
| ESP | 2,288 | 11 | SVQ, BRI, CLL, BUE, OUI, PLO |
| NLD | 1,610 | 10 | AMS, CAP, STA, JAK, SFR |
| MNG | 633 | 7 | GUA, GAL, AST, HOB |
| OTT | 365 | 5 | IST, HAD, PON, ELM |
| JPN | 301 | 5 | SAK, KOZ, AMB, COQ, MAS |
| MUG | 106 | 4 | KAR, NAV, GOR, CPT, TID |
| ENG | 74 | 3 | LON, CAL, NEW, GIB |
| JOS | 6 | 2 | BUS, MLE |
| | | **75** | 46 stations; a power mans the first `min(ships, stations)` |

Stations are computed, not authored: `navy_station_plan(nation)`, STABLE, greedy over `sea_reaches` for the cities it holds, re-run after any flag change, one a run, as 0309 does for circuits. Table above: today's flags, a throwaway script, not a prod function. ENG and JOS cover only part of their world.

**Why a root:** one ship per 200 M d. gives PRT 22 and three powers none. Portugal's realm holds about 720 × Joseon's; the root gives it 7.5 × the ships. Owner's knob.

**Falling purse:** a ship above size is **not scrapped.** She is laid up at her station, paid nothing, in no mission, until size rises. A rising size builds one ship a day.

### 6.3 Paid by the capital

| Flow | Rule | Kind |
|---|---|---|
| Build | Class build cost, capital to the nearest yard of its realm. Only from `city_surplus` | `BUILD_NAVY`, moved |
| Upkeep | `navy_upkeep_day` 60,000 d. a ship, hourly slices, capital to the harbour she last called at | `NAVY_PAY`, moved |
| Wreck | Origin = station; `npc_refit`, section 3.4, station's purse | `REFIT`, moved |

**At today's numbers:** build about 87 M d. once. Upkeep 4.5 M d. a day, against 70 M dock fees and 33 M tax a day, moved between cities. Seven capitals hold under 300,000 d. today: they have nothing to pay with, and instant calls stop in Part 2, so **their cargo ships must top them up first, and until then their ships stay unbuilt.** Unpaid, she is laid up, never in debt. No `E_CITY_BROKE` is ever raised by a navy.

### 6.4 Missions

One job, `public.tick_navy`, a minute, own cron, `SKIP LOCKED`, like `tick_cargo_ships`.

| Mission | Who | What |
|---|---|---|
| **Patrol** | Default | Sails a short circuit of her station's nearby harbours through `npc_courses`, back to station |
| **Escort** | One ship a realm while funds are at sea | Follows the richest cargo ship's next leg, one leg behind. Joins any battle on her at once |
| **Hunt** | Lit with pirates | Sails to the sea with the highest `sea_danger` in reach |
| **Reinforce** | Called by a battle | Real voyage to the nearest harbour; arrives or does not |

**Navy against pirate:** both in one sea at a job pass: one `fight_sides`, no timer, nobody watching, at most once an hour a ship. Reported in the world feed.

**Navy attacks a player:** only by section 5.3. Never a chase on the map. No player sees a ship turn to hunt her.

### 6.5 Cost, rollback, slices

**Beat:** 75 ships at about 11 minutes a leg is about 7 more arrivals a minute, on about 57 + 5. Estimate. **Measure the job per call before lighting.**
**Rollback:** `navy_enabled` false: ships finish the leg and lie at station; nothing is paid; a battle has no reinforcement. Hulls remain.

| Slice | Content | Red-first proof |
|---|---|---|
| **W12** `a_country_has_a_navy` | Table, kind, size, stations, build, upkeep, patrol, job, card, map through section 9's kind | Dark: nothing written, sea reads byte-identical; size matches the formula at probe purses; a broke capital lays up, no error; moved 0; merchants' tend roster names none |
| **W13** `the_navy_comes` | Call at battle start, reinforcement voyages, join rule, escort | Within reach joins, one minute past does not; late ship writes `wanted`; no ship counted twice |

---

## 7. Part 5: pirates, the 11th power

`PIRATES_AND_HAVENS.md` stays the base for danger (`sea_danger`, frozen at departure), hazard mix, captains by name, loot table, escorts. **Superseded by the owner's newer word:** pirates are not world rows with no purse; a haven is not a place with no market; pirate ships are drawn.

### 7.1 On the existing systems

| Concept | Reused | New row |
|---|---|---|
| Power | `nations`, `great_powers`, `GREAT_POWERS` in `world-derive.mjs`, world guard | `PIR`, The Brethren / 해적단 (decided by default) |
| Relations | `power_relations` | PIR **war** with all ten, 10 rows; stance factor applies |
| Cities | `port_allegiance`, home-city guard | 4 homes |
| Purse | `port_treasury`, `treasury_post` | **Hoard = Σ PIR city purses.** No `pirate_hoards` table |
| Investing | `cmd.invest`, `cmd.donate`, `npc_invest`, `port_influence`, the daily count | None. PIR can hold contested cities |
| Merchants | `npc_found`, `npc_houses`, routes | Section 7.4 |
| Shares | `city_shares` | Works as any city |
| Not a country to join | `cmd.found_house`, `cmd.change_country`, the picker | Refuse PIR by the one `E_MINOR_POWER` hunk (question 1) |
| No crown aid | `crown_aid`, cargo ships | PIR has no cargo ships and no aid: plunder funds it |

**HQ and homes, decided by default:** existing free cities first, so no gold is seeded and no world is built.

| Home | Port | State today | Why |
|---|---|---|---|
| **HQ** | **Salé (SAL)**, no holder, 99 M d. | Exists | The pirate republic of Salé, 1627-. 90 harbours within 2,400 nm |
| Home | **Port Royal (POR)**, no holder, 997 M d. | Exists | Caribbean. Named after 1655, a law 6 stretch; Tortuga is the true one |
| Home | **Lingga** | New harbour | Malacca Strait |
| Home | **Gotō** | New harbour | Wokou of Kyushu |

Two new harbours are a data slice as 0217, purse 0, `port_goods` rows, spur legs. **A warning:** Port Royal's purse would make PIR richer than four realms the day it lands. It is a city's own money, no gold is made. `pirate_spend_day_pct` 0.5 % a day caps what the power may spend. An alternative is an owner question.

The other seven havens of `PIRATES_AND_HAVENS` wait for later slices.

### 7.2 A pirate port

| Owner's word | Rule |
|---|---|
| No tax | `ports.tax_rate` 0 on PIR homes; `cmd.set_tax` refuses there; `port_fee` 0 by one hunk through `public.port_is_free(port)`. A contested city PIR wins keeps its rate: decided by default, only homes are free |
| Cheaper products | **No new price term.** `depth_mult` is fixed at 0.5 on PIR homes, so `stock_target` is half, and plunder may fill stock up to twice that (7.3). Through the existing `(target/stock)^0.5` a full port sells at 0.71 × the normal price, an empty one at the normal price or dearer |
| Pirate merchants | 7.4 |
| Who may dock | Anyone. Docking is safe (4.5). Trading costs -5 regard |

### 7.3 Plunder really moves

| Today | With pirates lit |
|---|---|
| PLUNDERED goods vanish | `raid_takes`' result goes to `public.pirate_stow`: into the stock of the raider's home port, up to 2 × its `stock_target` for that good; beyond that lost |
| RANSOM costs nothing | `ransom_share` 8 % of the cargo's cost basis, from the company's purse (merchant or player), kind `RANSOM`, moved to the PIR home. A purse that cannot pay pays what it holds |
| Gold on a cargo ship | Plundered share: book closes `LOOTED`, onto the pirate ship's own book; delivered when she docks home |

**A raid with a real ship:** pirate fleets are `pirate_ships` rows, kind `PIRATE`, as `navy_ships`. **Position decides who raids:** at departure the frozen segment names a pirate ship in that sea, if any (`PIRATES_AND_HAVENS` §2.3). If none, the anonymous xebecs of today. So the hazard is the same engine, and a pirate ship in a sea makes it worse through `sea_danger`.

**Size:** `pirate_size` = min(30, 4 + floor(hoard / 100 M)). Paid from the hoard, `NAVY_PAY`. A hoard at 0: no new ships.
**A player meets her:** attack on the map at sea. Loot from her book.

### 7.4 Pirate merchants and investing

- **Founded from the hoard**, through `npc_found` with PIR as her nation, paid by `city_pays`. `pirate_merchants_max` 30. Only from `pirate_spend_day_pct`.
- She runs standing routes among PIR ports and free cities. She is a real merchant: drawn in the pirate kind's ink, insured by nobody (decided by default: no city insures her, so no city pays for her).
- She invests and donates by `npc_invest` for PIR, so **PIR contests cities** by the one daily count. Owner: *"where they can also invest"*.
- A pirate merchant may be attacked by navies; regard is unaffected.

### 7.5 Attacking a pirate port

v1: **no.** A docked fleet is never attacked and no port is taken by force (law, section 10). `PIRATES_AND_HAVENS` §4's assault is a later slice; if lit, the loot comes from the purse, capped by `loot_per_company_day`, and that doc's waves become one battle row. Owner question 7.

### 7.6 Limits

**Arbitrage:** buy cheap at a pirate port, sell dear.

| Limit | Effect |
|---|---|
| Stock is plunder, not production | Regen off at PIR homes, one condition in `tick_market_drift`, so stock above target stays there and only plunder adds to it |
| The walk | Each purchase moves the price up by `quote_priced`, so the discount eats itself |
| Regard | -5 per trade, own country, so a heavy trader turns Wary, and pays × 1.25 at home |
| Daily | `pirate_port_day_cap` 5 % of a good's max stock, per company a day, on `trade_daily` |
| Merchants | Cannot buy there: their route planner skips PIR ports unless she is PIR |

**Insurance: fix before pirates.** Last 24 h on prod (`stats_world`, 96 slots):

| | Today |
|---|---|
| Premiums in (`INSURANCE`) | **7.44 M d.** |
| Payouts (`INSURANCE_PAID`) | **29.50 M d.** |
| Net out of city purses | **-22.1 M d. a day** |

Paid out is 4 × what is charged. The brief's "31 M a day" is close to this read. **The cause is now measured and is a bug (`docs/dev-log/2026-11-05-insurance.md`):** 92 % of the money paid went on `FORCED_HOME`, and every one of those ships had already arrived; a raid-only book earns 1.74 × what it owes. Migration 0314 fixes it, and **premiums do not need to rise**. The rest of this paragraph is the first read, kept for the record: `insurance_raid_loss` 0.084 sets the premium; to break even at today's take it would be about 0.33, arithmetic only. **Knob, owner's.** A payout is from `city_surplus` only and 129 of 246 cities hold under 50,000 d., so more raids mostly raise `short`, not the drain: the insured loses out. With pirates lit, raids rise by half where a ship is present (`pressure` +0.5).

**Also:** merchants insure every laden voyage and pay the same premium, from purses of 10.4 B. So a higher premium moves gold from merchants to cities, which the cities need. That helps, on top.

**Bound:** plunder is capped by what raids already take. `pirate_spend_day_pct` caps the outflow. A hoard above `pirate_hoard_cap` 2 B d. pays nothing in: raids take no gold.

### 7.7 Cost, rollback, slices

**Beat:** `sea_danger` adds one column read per segment at depart (`PIRATES_AND_HAVENS` Z1: arrivals ≤ 3 s, p95 < 5 s). 30 pirate ships add about 3 arrivals a minute.
**Rollback:** `pirates_bite` false: raids are anonymous xebecs again; no stow, no RANSOM money; ships lie at home; PIR keeps its cities, since a flag is a city's fact. Full removal is a one-way door: **an owner decision before W16.**

| Slice | Content | Red-first proof |
|---|---|---|
| **W0b** `insurance_pays_its_way` | A bug, no knob: migration 0314 | Quote × loss over what `insured_voyages` keeps (7.6 hours); dev-log prints it |
| **W15** Z1 of `PIRATES_AND_HAVENS` | `sea_danger`, frozen segments | That doc's parity for all 51 seas |
| **W16** `the_brethren` | Nation, 4 homes, relations, free port hunks, two harbours, Codex, picker hides PIR | World guard; W unchanged; no gold made (`SEED` refused and not used); home guard re-enabled; picker shows 10; influence rows re-keyed Σ constant |
| **W17** `pirate_ships_sail` | Kind, size, map, hazard hand-off, stow, RANSOM, book | Raid dark parity 960 days; moved 0; goods conserved into stock; cap holds; a hoard at 0 builds none |
| **W18** `pirate_merchants` | Founding, routes, investing, `pirate_port_day_cap` | Founded only from the hoard; `spend_day_pct` holds; daily count runs with 11 |
| **W19** `the_navy_hunts` | Hunt mission, navy against pirate, regard hooks | At most once an hour; fight written on both hulls; arrivals bound |

---

## 8. All new money kinds

Every one is **moved** in `stats_flow_words`. `mint_guard` is untouched. **No new exception to it.** Every slice proves Σ players + merchants + purses + set aside + funds aboard unchanged by its probe.

| Kind | From | To |
|---|---|---|
| `FINE` | Player | Capital |
| `LOOT` | Funds aboard, pirate book | Player |
| `RANSOM` | Company | PIR home, or a pirate ship's book |
| `REFIT` | Origin purse | Refit yard |
| `NAVY_PAY` | Capital, or PIR home | Harbour last called at |
| `BUILD_NAVY` | Capital | Yard city |
| `CONVOY_UPKEEP` | Origin | Harbour left |

**`set_aside`:** `funds_aboard()` already covers book rows. Pirate ships' books are the same table.

---

## 9. Ship looks: every kind has its hull and its mark, day and night

Owner: *"the ship type (cargo, merchant, navy) should be distinguished, as in graphics or as in color. day and night"*.

### 9.1 What is measured today

Contrast on the chart's grounds (`src/index.css`, computed, WCAG). Ground: night sea `#070c14`; day sea `#3d7ab8`, deep `#1d4f8c`, shallow `#8ec6e4`; light-scheme sea `#95b8d6`.

| Ink | Night sea | Day sea | Day deep | Day shallow | Light sea |
|---|---:|---:|---:|---:|---:|
| Nation inks (eight) | 7.4-10.8 | 1.7-2.5 | 3.1-4.5 | 1.0-1.4 | Not used |
| Light-scheme nation inks | Not used | | | | 3.7-4.9 |
| Pale deck `#eef2f4` (a merchant by day) | 17.4 | 4.0 | 7.3 | **1.6** | 1.8 |
| Gold accent `#e2b45c` | 10.2 | **2.3** | 4.3 | 1.0 | 1.1 |
| Red `#e5484d` | 5.0 | **1.1** | 2.1 | 2.1 | 1.9 |
| Near-black `#0b0f14` | **1.0** | 4.3 | 2.3 | 10.4 | 9.2 |

**What this says:**
- **By day a hull loses her nation.** `.bv-sun-merchant-nation` mixes all the way to the pale deck, so at noon every merchant, and every cargo ship, is the same colour.
- **No single colour works on both.** Gold, red, nation ink all fail the day sea. Black fails the night.
- **On pale shallows a pale hull fails:** 1.6 : 1. Her keyline by day is the day-sea blue, about 2.4 : 1 on shallows, also under 3.
- **A gold mark on nation ink fails:** 1.3-1.8. I first planned a gold coin; these figures killed it.

### 9.2 Why 0310's crown fails

It is a hole wound in the path, 5.9 × 5 CSS px at 1×, showing the sea. A hole at night shows near-black: a dark notch. The contrast is fine; **the shape is too small and too fine to name.** Three points need at least 1.5 CSS px each, at 1× that is mush.

**Fix:** remove the crown subpath from `cargoHullPath`. No hole at all. A shape that survives 1× is a **bold bar**, not a picture. The crown stays where there is room: her card and the Codex. `tests/cargo.design.spec.ts` changes with the reason written.

### 9.3 One table, one renderer

A kind is a row in one table in `src/chart/glyphs.ts`. Nothing else names a kind.

```ts
export const KIND_LOOK: Record<ShipKind, { hull: HullShape | null; mark: KindMark; fill: KindFill; minHalfLength: number; thin: boolean }>
```

- **`kind` comes from the server only** (`public.sea_houses().kind`), on the roster row, as 0310. Merchant keeps no key, so her rows stay byte-identical.
- `hullPath` stays the one hull renderer. New shapes are added inside it. `HullGroup` stays the one group.
- **One new function, `kindMarkPath(mark, halfLength)`**, and one generic second `<path>` in `HullGroup`, drawn when the table has a mark. No branch by kind in `FleetsLayer.tsx`. This reverses 0310's "no second path" for a measured reason.
- `.bv-sun-kind` is one CSS rule reading `--kind-night` and `--kind-day` custom properties set from the table.
- Merchants draw no mark: 837 hulls add no element.

| Kind | Hull (`hullPath`) | Mark | Night fill | Day fill | Keyline |
|---|---|---|---|---|---|
| **Merchant** | Class silhouette, today's | None | Nation or blue | Pale deck | **Day: dark, new** |
| **Cargo** | `cargo`, wide and blunt, today's, no hole | **Two full-beam bars**, 3 px, aft | Nation ink | 45 % nation over deck | Day: dark |
| **Navy** | New `navy`: long dart, sharp bow, swept stern, beam 0.32 | **One bow-to-stern stripe**, 2 px | Nation ink | 45 % nation over deck | Day: dark |
| **Pirate** | New `pirate`: crescent, forked stern | **An X**, 2 px strokes, full beam | Red `#ff6b6b` | Near-black, turned at `--night` 0.5, as names | Day: pale |
| **Yours** | Class silhouette | None, her halo and gold | Gold | Gold on halo | Halo, today's |
| **Pirate merchant** | Class silhouette | One X | Red | Near-black | Day: pale |

**Mark ink:** dark scheme `#0b0f14`, light scheme `#eef2f4`, token `--color-kind-mark`. Checked on hulls: near-black on nation inks 7.3-10.6, on pale deck 17.1, on 45 % day hulls 12.7-14.1; pale on light-scheme nation inks 6.9-9.1. Near-black on light-scheme inks fails, 1.9-2.5, which is why it is a token.

**The 45 % day hull is close to the line:** 3.0-3.3 on day sea, 5.4-6.1 on deep, 1.2-1.4 on shallows (there the dark keyline carries her). I estimated that mix in linear light; CSS mixes in sRGB, so the spec must read the real figure and may move the 45.

**Red by day:** `#ff6b6b` night 7.1. Light scheme red `#b3122a` on light sea 3.3.
**Keyline by day:** `.bv-sun-keyline` today mixes to the day sea, which by construction shows nothing. New day value `#16212c`: day sea 3.6, shallow 8.8, deep 2.0; on deep the fill carries it (pale 7.3). **Fixes the merchant on shallows too.** It touches every hull: 837 strokes change colour, no element added.

**Small zoom:**
- `minHalfLength`: cargo 9 (today), navy 7, pirate 7. So they stay 14 px long or more at every zoom.
- Marks are drawn at 2 px or more in CSS pixels at any size. A hull is the same CSS size at every zoom, so this holds. Bars and stripes survive 1×; the proof pictures must show it at 1×, on the phone's DPR too. The owner's laptop is DPR 2; test both.
- `shipMarks`: cargo, navy, pirate are never thinned (`thin: false`), at most about 155 in all, which keeps the 0310 rule. Generalise `t.merchant.cargo` to `t.kind !== undefined`.
- Fleets group: an NPC kind has one hull, so `hullGroup` is unaffected.

**Words:** the card and Codex carry each kind's name, EN and KO. No legend on the map (`MAP_ATMOSPHERE` §4). Regions filter: cargo and navy stay inked whatever it says, as 0310.

### 9.4 Slices and the contrast proof

| Slice | Content | Red-first proof |
|---|---|---|
| **W0a** `each_kind_its_look` | Table, `kindMarkPath`, keyline, no crown hole, cargo bars. Client only. **Ship now: 0310 stands dark, no ship exists** | `tests/map.kinds.spec.ts`, below |
| With W12, W17 | `navy`, `pirate` shapes and rows of the table | Same spec gains the row |

**`tests/map.kinds.spec.ts`, written first, red on main:**
1. **Contrast law:** reads the tokens from the built CSS, not a copy. For each kind × 8 nation inks × {night sea, day sea, day deep, day shallow, light sea}: **fill or keyline ≥ 3 : 1** against the ground (for yours, against her halo: gold on bare day sea is 2.3); **mark ≥ 3 : 1** against the fill. It prints the whole table. It fails on today's merchant on shallows.
2. **Twilight:** at `--night` 0, 0.25, 0.5, 0.75, 1. A mixed fill must pass at each one. Black mixing into red at dusk is the case to catch.
3. **Silhouette law:** the kinds' paths at 1× and 2× rasterised on the sea colour: two kinds' pixels differ by at least 20 % of the hull's area. Compares shapes, so colour is not the only channel (colour-blind safe).
4. **One renderer:** `FleetsLayer.tsx` has one `hullPath(`, one `HullGroup`, no kind name; `kindMarkPath` called once.
5. **Mark width:** every mark's narrowest bar ≥ 2 CSS px at each `minHalfLength`.
6. **Parity:** a merchant row carries no `kind`, and no merchant hull gains an element.

**Pictures in the dev-log:** served map, headless, at DPR 1 and 2, day, night and twilight, phone and laptop, each kind. Rule: `test-on-owners-real-setup`. Not a stub page. Not verified until a real ship is on a real map.

**Rollback:** a client revert. No server state.

---

## 10. The laws this breaks

`docs/DESIGN.md` says: *"These come from the owner's brief and override anything else"*. **The owner overrides his own brief here.** Each is listed so nobody builds on a dead law, or breaks a live one.

| Law | Text | Owner's words change | What stands |
|---|---|---|---|
| **J.2 No PvP** | *"There is no player-versus-player combat of any kind ... All the raiders in this game are NPC hazard rolls."* | **Half breaks.** Players now fight the world: NPC ships, navies, pirates. A navy may fight a player. *"All the raiders are NPC hazard rolls"* is false once a player raids | **No player ever targets another player's fleet.** No port capture, no blockade, no duels, no transfer. The owner never asked for these. See question 1 on joining the pirates, which would test it |
| **Law 4, No visual combat** | *"Danger resolves server-side and is reported as written prose."* | **Stands in full, with one added fact.** A battle is on the map as two stopped ships and a clock on a card | No animation, no battle screen, no sprite, no projectile. The fight is one server resolution and a written report. Pressing Attack leads to a text clock |
| **Law 3, The map is an output device** | *"It never accepts input."* Already amended 2026-08-23 for SAIL | **Amended again.** Attack is a second intent from a tray, chrome, into the same composer | **What is defended stands:** one composer, one grammar, one judge. No argument picker, no quantity control, no client legality check in `src/features/map`. Every control on the glass, never on a coordinate. `cmd.preview` judges |
| **J.3 Only your own fleets are drawn** | *"Adding them would turn the map into a targeting surface"* | **That now happens, for NPC ships, on purpose.** Cargo, navy and pirate ships are targets. Owner: *"it should see on the map"* | **Rival players are never drawn,** and `sea_houses` stays the only door. `FleetsLayer.tsx`'s "no other players" stands |
| **DESIGN B.6** | *"The flagship is never captured."* | No change | No hull is ever taken from anyone. A wreck respawns |
| **D.2 pure function of time** | A voyage settled late rolls the same | Tested by battles, section 5.2 | **Stands.** A battle is a recorded delay. Navy hazards are frozen at departure |
| **Law 8 server-authoritative** | | None | Stands |
| **Law 6 real world** | 1500-1650 | Bent by Port Royal, section 7.1 | Stands; flagged |
| **`CLOSED_ECONOMY` §2.3** | Nothing minted | None | Stands: section 8 |
| **`ECONOMY_LOOP` §12.3, `GREAT_POWERS` §6 row 4** | *"Money only ... no war and no PvP"* | **War exists** between players and countries, in ships only | Influence stays money only: fighting wins no flag |
| **`PIRATES_AND_HAVENS` §10** | No PvP, no pirate company, pirates not drawn, haven has no market | Reversed for pirates: section 7 | Danger is one number, no zone geometry, no client-writable row |
| **`CITY_CONVOYS`** | *"Delayed, not lost"*; *"cannot be boarded"*; capital is her base | Reversed: sections 3, 4 | One path per state of the switch |

**Docs to update when each slice lands:** `docs/DESIGN.md` J.2, J.3, law text; `FleetsLayer.tsx` and `glyphs.ts` headers ("No rival", "three glyphs"); `docs/WORDS.md`. Decided by default: the laws are amended with the first slice that breaks them, W11, not before. A law true today stays written.

**Words** (1-2 plain, EN and KO, `src/lib/i18n/dict/*`): Attack 공격, War fleet 전투 함대, In battle 전투 중, Break off 후퇴, Loot 전리품, Wanted 수배, Fine 벌금, Navy ship 군함, Pirate ship 해적선, Station 기지, Relationship 관계. Hostile 적대, Wary 경계, Neutral 중립, Friendly 우호, Honoured 명예. Never "PvP", "affinity", "regard", "dungeon".

---

## 11. Decided by default, in one place

| Decision | Default | Change it by |
|---|---|---|
| Regard, decay, bands | Section 2.1 | Knobs |
| Character | A captain | |
| `company_level` | Left dead | |
| Combat in the title | Stays out | One hunk |
| Captain stats | Derived sheet, no stored stat | |
| War fleet | Guns + empty hold, no type | |
| Merchants as targets | No | Owner question 2 |
| Own nation's ships | Refused | Owner question 3 |
| Loot | Gold only; 15 %, 60,000, 240,000 | Knobs |
| Reach, cooldown | 240 nm, 30 min, one a lap | Knobs |
| Armed class | `navire` | Knob |
| Ship cost | Crown hulls free at start; refit paid | |
| Origin | Top 3 rich cities | Knob |
| Same nation aid | Yes | Knob later |
| Gift call | Off while ships carry funds | |
| Refit payee | Nearest other yard | |
| Battle | 600 s, one resolution, ships stop | Knob |
| WANTED | 48 h, frozen at departure | Knobs |
| Navy fine | 5 %, cap 100,000 | Knobs |
| Navy size | Root of purse, cap 24, min 2 | Knobs |
| Upkeep | 60,000 d. a day | Knob |
| Pirate HQ | Salé; Port Royal; Lingga; Gotō | Question 5 |
| Cheap goods | Through stock, no term | Question 6 |
| Pirate ports attackable | Not in v1 | Question 7 |
| Pirate merchants insured | No | |
| Name | The Brethren | |
| Looks | Section 9.3 | |

**This doc overrides, in earlier docs:** `CITY_CONVOYS` §0.7, §2 (boarded, crew 0), V1's no-crew default, ship class knob. `PIRATES_AND_HAVENS` §0.4-5, §3.1, §4.1, Q1, §3.4's RANSOM line (wrong for live). 0310's crown and "no second path". `GREAT_POWERS` "ten". `FLEETS_AND_SLOTS` unchanged.

---

## 12. Strict build order

**Foundations first,** as the owner ordered. This table is the build order. It differs from the section order once: **battles are built before attacks,** because the verb starts a battle. Attacks stay dark until navies can answer: a player must not attack a country that cannot respond.

| # | Slice | Needs | Live play changes? |
|---|---|---|---|
| **W0a** | `each_kind_its_look` | Nothing | Keyline on all hulls only |
| **W0b** | `insurance_pays_its_way` | | Yes: ships dry at the ETA now dock. No premium moves |
| **W1** | `a_house_has_a_regard` | | Dark |
| **W2** | `levels_are_lit` | | **Yes, owner** |
| **W3** | `a_captain_has_a_sheet` | W2 | Reads |
| **W4** | F1, F2 | | First second fleet; own window |
| **W5** | `a_fight_has_two_sides` | | No, parity |
| **W6** | `every_npc_ship_has_an_origin` | W5 | Dark |
| **W7** | `rich_cities_send_the_ships` | W6 | Dark |
| **W8** | `the_cargo_ship_is_armed` | W7 | Dark |
| **W9** | Light cargo ships | W8 | **Yes, owner** |
| **W10** | `a_battle_takes_ten_minutes` | W5 | Dark |
| **W11** | `a_player_attacks` | W1, W4, W10 | Dark |
| **W12** | `a_country_has_a_navy` | W5, W9 | Dark, then **owner** |
| **W13** | `the_navy_comes` | W10, W12 | Dark |
| **W14** | `wanted` | W1, W12 | Dark |
| | **Light `attack_enabled`, cargo and navy** | W11-W14 | **Yes, owner, 30-minute after-check** |
| **W15** | Z1 `sea_danger` | | No, parity |
| **W16** | `the_brethren` | W15 | **One-way, owner** |
| **W17** | `pirate_ships_sail` | W5, W16 | Dark, then owner |
| **W18** | `pirate_merchants` | W17 | Dark, then owner |
| **W19** | `the_navy_hunts` | W12, W17 | Dark, then owner |

**Every migration slice:** one PR, number order, `~/bin/bv-deploy.sh`, self-assert on rolled-back probes only, red-first harness in `scripts/ops/harness/`, a `scripts/db/proofs/` file, hunks that reverse, dark byte parity, `docs/dev-log/` file. **Parallel:** W0a, W1, W4 and W5 can be built together, deployed in order. W9, W2 and the attack light each get a measured window of their own.

**W4 is built, migration 0321, dark, not deployed** (`docs/dev-log/2026-11-06-a-ship-changes-fleets.md`). Lighting it is `fleet_room_bite`, the owner's, in its own window.

**Before lighting attack, simulate:** `scripts/ops/harness/raid/sim.mjs`, on W5's core, prod hulls exported read-only, printing win rates of 1 and 2 xebecs, a `nau`, 2 `galion` against `navire` and `galion`, 500 runs each. **Not simulated in this doc.** No claim here says who wins.

**Not verified, anywhere here:** every speed and beat figure marked arithmetic or estimate; the 46-station list (one script, today's flags); contrast on land, on the region tints and on the twilight mix (`--night` steps computed only at ends). The battle hold on `voyage.progress_nm`: read, not run. Whether 10 minutes feels right: only play shows. Insurance's cause.

---

## 13. Questions only the owner can answer

1. **May a player join the pirates?** Default: no. PIR is not on the country picker. If yes, an owner of a pirate fleet raids at sea and the *"no player attacks a player"* law needs a ruling: can she attack other players' merchants? I recommend: join yes later, players stay off-limits.
2. **May a player attack ordinary merchant ships of a country?** Default: no. They are the economy, 821 houses, 10.4 B. You said *"cargo ship"* and *"countries"*.
3. **May a player attack her own country's ships?** Default: no.
4. **Light order:** levels (W2), then cargo ships (W9, stops instant aid, first lap up to about 5 hours), then attacks. Each is your switch. (The insurance question that stood here is closed: the 22 M d. a day was a bug, 0314, and premiums need not rise.)
5. **Pirate homes:** Salé as HQ, Port Royal, plus two new harbours (Lingga, Gotō)? Port Royal holds 997 M d. and would make the pirates richer than four countries at once. The alternative is a free port with a small purse, or new harbours only, starting at 0.
6. **"Cheaper products":** default is cheap by stock only, so a pirate port with little plunder is not cheap. A flat discount is one term, and more arbitrage.
7. **Pirate ports attackable?** Default not yet. It breaks nothing in law if the attack is ships in its roads and takes no flag; taking the city by force would.
8. **Should a Hostile company be refused docks?** Default: no, it costs double; a refusal may strand a fleet.
9. **The first 50 armed cargo ships and 75 navy hulls:** cargo hulls free, navy hulls paid by capitals. Seven capitals hold under 300,000 d. today. Agreed?
