# 2026-11-05 - Cargo ships exist, dark (migration 0308)

Migration `supabase/migrations/20260818000308_cargo_ships_exist.sql` · proof `scripts/db/proofs/18_cargo_ships.sql`
· mutation harness `scripts/ops/harness/cargo-ships/proof-0308.mjs`. Prod head when cut: 0307. **Not deployed** (PR only). Dark: no after-check, nothing changes in play.

## The order
Step 3 of the REVIEW at the top of `docs/CITY_CONVOYS.md`, slice V1. Owner: *"transportation ship ... cargo ship ... with different graphics. npc like merchants but different."* Funds only, no goods run. Replacing instant aid is a later slice: `public.crown_aid` stays the one aid loop and V1 changes no live money path.

## How a cargo ship exists (read from prod bodies at head 0307)
**A real `public.fleets` row with one empty hull, owned by a house of her own (`players`, `is_npc`, purse 0), with a row in the new `public.cargo_ships`, and no row in `npc_houses` or `npc_fleets`.** That row is the kind; `public.fleet_kind` answers it.

| Merchant logic | What selects a fleet | Why she is out |
|---|---|---|
| Tend | `npc_tend_roster`: from `npc_fleets` | no row |
| Lap starts | `lap_starts_due`: needs a `standing_routes` row | she has no route |
| Invest | `npc_invest_roster`: from `npc_houses` | no row |
| Gifts | `capital_gift_roster`: from `npc_houses`; `player_gift` stops at `is_npc` | no row, and `is_npc` |
| Refound | gone since 0213; broke merchants are funded by gifts, above | |
| Market requests | `market_request_fill` on docking: sells only what she carries | her hold is empty |

Why not the other shapes:
- **Why a real fleet, not a table of her own:** `voyage.depart`, `voyage.settle`, `voyage.where_now`, `world.voyage_view` and compaction all work on `fleets` and `voyages`. A separate table would be a second voyage engine.
- **Why `is_npc` true:** with false she would be a player in `settle_standings`, `stats_me`, the purse totals and `tick_influence`. With true, `npc_compact_houses` deletes her ended voyages and events like a merchant's (proved). `players_npc_never_signs_in` also holds.
- **Why one house per ship:** `assert_house_caps` allows a house `fleet_max` 2 fleets. That trigger is a live path, so it is not touched. Merchants are 821 houses for 837 fleets, so this is the normal shape.
- **Why no crew:** `commission_ship(..., p_crewed false)`, as a built hull. Crew 0 means wage 0, stores never drink, `voyage.endurance_days` 9999, so she can never run dry and be forced home. The price is `crew_short_speed_mult`: 0.7 of the speed. A crew would be 341 nm a real minute, but then she needs wages and stores, and she has no purse. Decided by default; V2 can reverse it, nothing is built on it yet.
- **Why not `public.new_house`:** it writes a `FOUNDED` event and a `FOUNDING` ledger row, and crews her. A house needs none of these. `public.cargo_ships_commission` inserts the `players` row, then uses `form_fleet` and `commission_ship`, the one writers of a fleet and a hull.

**V1 writes no ship.** The commission does nothing while `convoys_enabled` is false and nothing calls it. This is required, not a choice: 50 rows would move `world.sea_traffic`'s `total` and `omitted` (see the leak below), so writing them now would not be byte-identical.

Goods-run tables and knobs (`convoy_float`, `convoy_goods_enabled`, `convoy_surplus_pct`, `convoy_lack_pct`) are left out: the REVIEW dropped the run. `convoy_low_water_days`, `convoy_target_days`, `convoy_floor`, `convoy_cap_per_city_day` and `convoy_capital_reserve_pct` are left out too: `crown_aid` and `city_aid_target` already decide who is short and by how much, and a second rule would be a fork. `convoy_max_days` and `convoy_upkeep_per_leg` wait for the slice that reads them; 10 "days" would be 10 real minutes, so it needs re-thinking in hours.

## What was built (one authority per concept)
| Concept | The one place |
|---|---|
| The kind | `public.cargo_ships` (fleet, her house, nation, home, ord). Server-only |
| What a fleet is | `public.fleet_kind(fleet)`: CARGO_SHIP, MERCHANT, COMPANY. STABLE, server-only |
| The switch | `convoys_enabled` false, read by `public.convoys_on()` alone |
| Making ships | `public.cargo_ships_commission(nation)`, server-only, idempotent up to `convoy_ships_per_nation` |
| Funds aboard | `public.convoy_cargo`, append-only as `capital_gifts`: a LOADED row, then closing rows DELIVERED or RETURNED that name it |
| Closing rule | `public.tg_convoy_cargo_closes`: the same ship, a return to the port it left, never more closed than loaded |
| Flow kinds | `CONVOY_LOAD`, `CONVOY_DELIVER`, `CONVOY_RETURN`: moved, none written yet |

Knobs: `convoys_enabled` false, `convoy_ships_per_nation` 5, `convoy_ship_class` `qpinnace` (the fastest hull, 21.3). The map will draw her by her kind (`docs/CITY_CONVOYS.md` section 2), not this class, so no new class was added: she needs none.

`convoy_cargo` carries `player_id` (her own house, by foreign key) because `public.forbid_mutation` reads `old.player_id`.

**Byte-identical while off:** no existing function, trigger, knob or word moves (asserted by hash). `stats_flow_lines` and `stats_sides` read the kinds found in the data, so three unused words change no answer. No `players`, `fleets` or `ships` row is written.

## Sizing: the REVIEW's open question
**Answer: 5 cargo ships a realm, 50 in all, on ONE circuit of the realm: capital, every city in turn, capital. The ships sail it evenly spaced. A city then has a ship about every hour, so it waits about what it waits today.**

Prod read 03:58 UTC, of the 03:37 run. 168 cities received 7,595,133 d. That was the first run with 0307 and held a backlog, so a normal hour should be lower. Not read again at a later hour: the circuit below covers every city of a realm, so it does not depend on which 168 were short.

Inputs:
- **Speed:** 237 nm a real minute, measured on a bare `qpinnace` in proof 18 (crew 0, empty hold). Merchants on prod: p50 288, 628 voyages.
- **Distances:** shortest route over the 1,253 merchant courses on prod. All 236 circuit legs were reachable; 125 are one course, the rest chain several. This matters for V2, because the server never finds a path.
- **Tour:** nearest neighbour then 2-opt, in a throwaway script, one minute in each port (`port_prep_seconds` 60).

| Realm | Cities (not the capital) | Short at 03:37 | One lap, min | Time between ships with 5 | With 2 |
|---|---:|---:|---:|---:|---:|
| AMS | 21 | 17 | 246 | 49 | 123 |
| BUS | 12 | 1 | 133 | 27 | 67 |
| GUA | 20 | 16 | 276 | 55 | 138 |
| IST | 33 | 27 | 226 | 45 | 113 |
| KAR | 19 | 15 | 284 | 57 | 142 |
| LIS | 23 | 17 | 246 | 49 | 123 |
| LON | 20 | 17 | 149 | 30 | 75 |
| MRS | 14 | 13 | 145 | 29 | 73 |
| SAK | 27 | 25 | 289 | 58 | 145 |
| SVQ | 37 | 20 | 303 | 61 | 152 |

- **Capacity:** 5 ships make about 300 stops an hour across the world against 168 needed, and each realm has more stops an hour than it had short cities.
- **The minimum is 44 ships** (3 to 6 a realm, by lap). One knob for all, so 5; SVQ is at 61 minutes, a minute over.
- **2 ships a nation, the design's default, is not enough:** 2 hours or more in 6 of 10 realms.
- **Why not one trip per city group from the capital:** I tried it. Sending trips out every hour needed about 135 ships at 200 nm a minute, because each must sail home.

**What cities would see:**
| | Today | With 5 ships |
|---|---|---|
| A city goes short, gold arrives after | mean 30, max 60 min (the `:37` run) | mean 13 to 30, max 27 to 61 min, while the ships stay spaced |
| Right after lighting | | **up to about 5 hours** until the first ship reaches the end of the circuit. If instant aid stops at the same moment, cities late on the circuit go without for that long |
| Weather | none | calm and storm delay a ship; ships may bunch up. **Not measured** |

So the wait is about the same once running. The real cost is the first lap and any bunching, which is what V2 must watch through `E_CITY_BROKE`.

Each ship should load about one hour of its realm's need, and the amount should be set at each dock (top up to `city_aid_target`, keep the rest aboard), since the short list changes during a 5-hour lap. On the 03:37 figure about 19 M d. would be aboard at any moment (2.5 hours of need). Estimate, and high, because of the backlog.

## What V2 and later must meet (found by reading, not built)
1. **Funds aboard must be counted in the world total** before the first `CONVOY_LOAD`, or the total falls by them. `stats_live_add` has no such bucket.
2. **Dock fee.** `voyage.settle` -> `port_call` charges her: 63 d. in proof 18, with `port_fee_base` 250. Her purse is 0, so it is owed in `port_fee_debts`, which adds up and is never paid. At 300 stops an hour this needs a rule.
3. **`world.sea_traffic`'s `total` counts her.** It counts `fleets` joined to `is_npc`, not to `npc_houses`, so `omitted` rises by 50. Her rows are absent, and `world.sea_roster` and `world.port_merchants` never show her. V4 must serve her kind and close this. Proof 18 has a marker for it (`CARGO_KNOWN_LEAK`).
4. **`stats_live_fold`'s `at_sea_merchants` will count her** while she sails.
5. **Hull wear.** Storms, shoals and fights lower her durability, she has no yard stop, and at 0 she docks as `UNABLE_TO_SAIL`. Speed falls with hull. Needs a rule ("delayed, not lost").
6. **Course:** chain `npc_courses` segments into one voyage, or sail stop by stop through real ports.
7. **Beat cost:** about 5 more arrivals a minute against about 57 for merchants (628 sailing, 11 minutes each, a rough figure), and about 2,000 more `voyage_events` an hour, compacted after 6 hours. Measure before lighting.
8. **A player may take the name** `Crown Cargo PRT 1` before the commission runs; it would then raise. Check at lighting.

## PROD CHECKS (pure SELECTs from a file, one statement per file, before deploy)
Run 2026-11-05 04:10 UTC, all as expected:
1. Head and names free:
```sql
select (select max(version) from supabase_migrations.schema_migrations) as head,
  to_regclass('public.cargo_ships') is null and to_regclass('public.convoy_cargo') is null
  and to_regprocedure('public.cargo_ships_commission(uuid)') is null and to_regprocedure('public.fleet_kind(uuid)') is null
  and to_regprocedure('public.convoys_on()') is null and to_regprocedure('public.tg_convoy_cargo_closes()') is null as fns_free,
  (select count(*) from public.world_config c where c.key like 'convoy%') as knobs,
  (select count(*) from public.stats_flow_words w where w.kind like 'CONVOY%') as words,
  (select count(*) from public.ports p where p.code like 'QZ_') as ports,
  (select count(*) from public.nations n where n.code = 'QX8') as nations,
  (select count(*) from public.players p where p.company_name like 'Crown Cargo %') as houses,
  (select count(*) from public.ship_classes c where c.code = 'qpinnace') as class
```
-> `20260818000307`, true, 0, 0, 0, 0, 0, 1.

2. The self-assert's selections over real rows (all four functions `s`; a uuid that is no house):
```sql
select (select count(*) from public.npc_tend_roster()) as tend,
  (select count(*) from public.lap_starts_due()) as laps,
  (select count(*) from public.npc_invest_roster('00000000-0000-4000-8000-000000000308'::uuid)) as invest_one,
  (select count(*) from public.capital_gift_roster(now(), '00000000-0000-4000-8000-000000000308'::uuid)) as gift_one,
  (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) as fn_md5
```
-> 04:10 UTC: 837, 1, 0, 0, `c643098f9f81a355ac79595dfcbcfd06`. The whole CLI call took 4.1 s, against 3.6 to 4.3 s for `select 1` (0307's measure), so under the noise. The first two counts move with play; the hash only with a deploy.

Deploy: `~/bin/bv-deploy.sh <pr>`. After it, check that nothing was made:
```sql
select (select count(*) from public.cargo_ships) as ships, (select count(*) from public.convoy_cargo) as book,
  (select value from public.world_config where key = 'convoys_enabled') as lit,
  (select count(*) from public.players p where p.company_name like 'Crown Cargo %') as houses
```
-> 0, 0, false, 0.

## Tests
- **Red first** (`BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/cargo-ships/proof-0308.mjs`, cached world at 0307, 292 of 292 restored, no from-zero replay). 24 broken files, each failing for its intended reason: the knob ignored; shipped lit; a row in `npc_houses`; a route; crewed; not `is_npc`; founded with gold (refused by `mint_guard`); paid for by the capital; not idempotent; based away from the capital; the kind answering MERCHANT; a minted flow kind; closing more than loaded; another ship's closing; a return to another port; not append-only; a load naming a load; a client reading the kind; no row security; a client commissioning; a live function, knob, trigger or word touched.
- **Green:** the real file, about 105 ms on PGlite.
- **What the first runs caught:** `forbid_mutation` needs a `player_id` column, or a delete fails with the wrong error. A stable knob read in the same statement as a join raised "key does not exist" during planning; the class is read into a variable first.
- **Proof 18** (`node scripts/db/proof.mjs 18_`, 6/6 markers, 0.8 s): knob on over the whole local world, rolled back. 50 ships at 5 a realm; every purse summed, moved 0; tend, invest, gifts, laps, sea traffic, sea roster, quay and merchant stats name none of them. A real ship sailed LIS to SET through `voyage.depart` and `voyage.settle`, 38 nm, speed 14.805 (237 nm a real minute): docked, no wage, no stores, no forced home, owed a 63 d. dock fee. `npc_compact_houses` removed her voyage and its events.
- Proof 03 (grants): 12/12. eslint on the harness clean. `BYEHARU_PREFIX_CACHE=required npm run build` ran to the end.

## Not verified
- Nothing ran on prod: 0308 is not deployed.
- The self-assert's real time on prod (budget 45 s; about 105 ms on PGlite).
- The real-Postgres path (`disposable-chain`): CI runs it on this PR.
- A long voyage through the engine: proof 18 sailed 38 nm, one sim day. No storm, calm or pirate scene was run on a cargo ship.
- Sizing is arithmetic from one read of one hour, not a run. Weather delay and bunching are not in it. The 237 nm a minute is one hull on the local world with no roll on prod.
- The extra `E_CITY_BROKE` during the delay: only V2's run can show it.
- The 19 M d. aboard and the beat cost in the V2 list are estimates.
