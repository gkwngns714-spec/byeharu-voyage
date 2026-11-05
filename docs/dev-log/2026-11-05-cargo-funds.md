# 2026-11-05 - A cargo ship carries funds, dark (migration 0309)

Migration `supabase/migrations/20260818000309_a_cargo_ship_carries_funds.sql` · proof `scripts/db/proofs/19_cargo_funds.sql` (and proof 18's dock-fee line)
· mutation harness `scripts/ops/harness/cargo-ships/proof-0309.mjs`. Prod head when cut: 0307; 0308 (#488) deployed during the work, so 0309 is head + 1. **Not deployed** (PR only). Dark: no ship, no switch, nothing changes in play.

## The order
The next cargo ship slice, funds only, owner-approved 2026-11-05. `crown_aid` keeps deciding who is short. Lit, a ship carries what the instant loop would have paid. **Exactly one path per state of the switch.** Client (own hull graphics, EN+KO words, map, roster) is V4, later.

## How it works, in one lap
1. **Load.** `:37`, `tick_city` -> `city_day` -> `crown_aid`. The roster and `crown_call` run as today. Then, lit, the roster goes to `public.cargo_ships_load`, which replaces the instant loop. Per capital: what its cities need, less what its ships already carry, up to its surplus, onto one idle ship.
2. **Sail.** `public.tick_cargo_ships`, a new minute job `byeharu-voyage:cargo-ships`. Each ship not at sea takes `public.cargo_ship_step`: the next leg of her circuit, through `voyage.depart`. `voyage.settle` docks her in the arrivals beat, like anyone.
3. **Deliver.** At each stop, up to `city_aid_target`; she keeps the rest aboard.
4. **Return.** Back at the capital the rest goes into its purse and she is mended.

**One ship a run** is what spaces the ships: one leaves each realm per hourly run at most. It needs no spacing rule and no fleet lock in the city run.

| Concept | The one place |
|---|---|
| Who is short, how much | still `public.crown_aid` and `public.city_aid_target` |
| A capital's draw on its nation | still `public.crown_call`, lit and dark |
| What a ship carries | `public.cargo_ship_aboard(fleet)`, STABLE |
| Funds at sea, world-wide | `public.funds_aboard()`, STABLE |
| Funds moving | `public.convoy_book`: the flow, the book row and the live figure, together. The one writer |
| The circuit | `public.cargo_circuit_plan(nation)`, STABLE, so a prod check can ask it; `public.cargo_circuit_build` writes it down |
| What a ship does in port | `public.cargo_ship_step` |
| The job | `public.tick_cargo_ships` |

Tables: `public.cargo_circuits`, `public.cargo_circuit_legs`, server-only. Columns on `public.cargo_ships`: `circuit_id`, `leg`, `out_load`. Knob: `convoy_wreck_seconds`, 600.

## The V2 list, solved
| Item (0308 dev-log) | Decided by default | Why |
|---|---|---|
| 1. Funds aboard in the world total | They count in `set_aside`, by one term `public.funds_aboard()` in `tick_stats` and `stats_live_fold`. `convoy_book` journals the move | `set_aside` is the figure for gold in no purse (open escrow, coupons), and `world.stats_now`'s `total` already adds it. No new bucket, no `stats_live_add` change. Her house purse stays 0, so the merchants' figure is not inflated. Stats' "Set aside" (1.57 B, almost all uncollected dividends) rises by what is at sea, about 19 M on the 0308 estimate |
| 2. Dock fee with an empty purse | `public.port_fee` answers 0 for a cargo ship's house | A crown's own ship calling at her own crown's cities. No debt row. She keeps her 60 s of port time |
| 5. Hull wear | Mended free at the capital after every lap. A ship that docks wrecked (`UNABLE_TO_SAIL`) still delivers, lies `convoy_wreck_seconds` (10 minutes), is patched and sails on | "Delayed, not lost". No gold moves, so nothing is minted. A cost to the capital could come later |

Also met:
- **6. Course:** stop by stop, each leg a chain of `npc_courses` as one voyage.
- **7. Beat cost:** the job runs outside the beat. Not measured on prod: only an arrival per minute adds to the beat, as the 0308 estimate says.
- **Not solved, V4:** `world.sea_traffic`'s `total` and `at_sea_merchants` still count her (0308's items 3 and 4). **8. The name:** check at lighting.

## Decided by default (the owner may reverse any)
- **The job runs dark, as an active cron row.** It reads the switch and an empty table, and writes nothing. Reason: 0304 scheduled its job paused, but here lighting the switch with no job would stop instant aid with nobody sailing. One switch, no second step.
- **Off mid-lap:** she pays nobody, sails the rest of the circuit and returns everything. The circuit is the only way home she has. A load not yet gone comes straight back ashore.
- **`crown_call` still calls for the full need while ships carry funds,** so a capital may draw more than this hour's load. It sits in the capital, moved, not made, and the next hour's gap shrinks by it. No change to `crown_call`.
- **Flags change, so a circuit is not forever.** `tick_influence` moves flags daily (last on prod 00:47 UTC today). After any flag change the job rebuilds every realm's circuit, one a run. A ship finishes the lap she began on; an old circuit goes when no ship is on it. A city that changed flag mid-lap is passed, not paid.
- **Delivery has no purse lock.** A positive moved kind takes none. Two ships at one city in one minute could overshoot by what a sale paid in between; harmless, and rare.
- **Delivery and return write whatever the purses' switch says** (`p_always`), so funds aboard can never vanish into a dark purse.

## The circuit on prod's own data
Prod's 1,253 courses and its flags, read with a pure SELECT at 04:15 UTC, loaded into a rolled-back local world, then the real plan and build. **Every city of every realm was reached; nothing left out.** Speed 232 nm a real minute (proof 18, this run).

| Realm (capital) | Stops | nm | Lap, min, 1 minute a port | Lap, min, with the job's 1.5 | Plan, ms (PGlite) |
|---|---:|---:|---:|---:|---:|
| ENG (LON) | 21 | 30,620 | 153 | 163 | 106 |
| ESP (SVQ) | 38 | 63,394 | 311 | 330 | 190 |
| FRA (MRS) | 15 | 31,089 | 149 | 157 | 90 |
| JOS (BUS) | 13 | 28,745 | 137 | 143 | 70 |
| JPN (SAK) | 28 | 62,282 | 296 | 310 | 155 |
| MNG (GUA) | 21 | 60,918 | 284 | 294 | 102 |
| MUG (KAR) | 20 | 62,966 | 291 | 301 | 104 |
| NLD (AMS) | 22 | 53,450 | 252 | 263 | 110 |
| OTT (IST) | 34 | 45,953 | 232 | 249 | 169 |
| PRT (LIS) | 24 | 53,123 | 253 | 265 | 114 |

Within about 5 % of the 0308 tour. A stop costs up to 2 minutes, not 1: port time plus the wait for the minute job, about 1.5 on average. The 1.5 column is that estimate, not a run.

**A gap the 0308 sizing does not show:** ESP, JPN and MUG lap in over 300 minutes. With 5 ships and one departure an hour, the first is not back when the sixth run comes, so that run sends nothing and those realms have one 2-hour gap about every 6 hours. A sixth ship, or `convoy_ships_per_nation` 6, closes it; that is the owner's knob. The other seven are fine.

## Dark: why this is byte-identical
Six hunks on five bodies, each occurring once, each reversing to its pre-image:
- `crown_aid` (2): one comment line; the branch `if public.convoys_on() then return ...`. Off, it falls through to the loop as written.
- `port_fee` (1): one more `or exists` on an empty table, by a unique index.
- `tick_stats`, `stats_live_fold` (1 each): `+ public.funds_aboard()`. No ship, 0.
- `tg_convoy_cargo_closes` (1): not a live path, no row exists. One open load a ship, which keeps `cargo_ship_aboard` one lap's walk however long the book grows.

Self-assert: `crown_aid` and `port_fee` equal `pg_temp` copies of their pre-images in a probe scene, flow by flow and purse by purse. The job makes nothing dark. Every other function, knob, word, trigger and cron row is hashed unmoved.

**Cost while dark:** one more index probe in `port_fee`, an empty-table read in `tick_stats` and in the fold, and one no-op cron row a minute. Not measured on prod.

## PROD CHECKS (pure SELECTs from a file, one statement per file, before deploy)
Run 2026-11-05 about 04:40 UTC.

1. Head, and the bodies the hunks were cut against:
```sql
select (select max(version) from supabase_migrations.schema_migrations) as head,
  md5(replace(pg_get_functiondef('public.crown_aid(uuid)'::regprocedure), E'\r', '')) as crown_aid,
  md5(replace(pg_get_functiondef('public.port_fee(uuid,uuid,numeric)'::regprocedure), E'\r', '')) as port_fee,
  md5(replace(pg_get_functiondef('public.tick_stats(timestamp with time zone)'::regprocedure), E'\r', '')) as tick_stats,
  md5(replace(pg_get_functiondef('public.stats_live_fold(timestamp with time zone,boolean)'::regprocedure), E'\r', '')) as stats_live_fold
```
-> `20260818000308`, `91fecb3b8bbd3a99d7a23a273a51b72e`, `7dcb8a36dca29bf8086a875627b45002`, `a4f65a9d635da3f4863cbd903423dc99`, `7721c10b1724c43f9aba70b55743f79d`. The cached local world gives these same four hashes.

2. Names free, and the self-assert's own selections over real rows:
```sql
select to_regclass('public.cargo_circuits') is null and to_regclass('public.cargo_circuit_legs') is null
  and to_regprocedure('public.convoy_book(text,uuid,uuid,uuid,bigint,bigint)') is null and to_regprocedure('public.funds_aboard()') is null
  and to_regprocedure('public.tick_cargo_ships(timestamp with time zone,uuid)') is null as names_free,
  (select count(*) from public.world_config c where c.key = 'convoy_wreck_seconds') as knob,
  (select count(*) from public.ports p where p.code like 'QW_') as ports,
  (select count(*) from public.nations n where n.code = 'QX9') as nations,
  (select count(*) from public.players p where p.company_name = 'Probe 0309 house') as houses,
  (select count(*) from cron.job j where j.jobname = 'byeharu-voyage:cargo-ships') as job,
  (select max(a.since) from public.port_allegiance a) as last_flag,
  (select count(*) from public.stats_live_deltas d where d.at >= now() - interval '1 minute' and d.set_aside = 98900) as journal_probe,
  (select count(*) from public.players p where p.company_name like 'Crown Cargo %') as cargo_names
```
-> true, 0, 0, 0, 0, 0, `2026-11-05 00:47:00`, 0, 0. The whole CLI call took 3.7 s, inside the 3.6 to 4.3 s of `select 1`.

Deploy: `~/bin/bv-deploy.sh <pr>`. After it, still dark (both `s`, safe to select):
```sql
select public.funds_aboard() as aboard, public.convoys_on() as lit,
  (select count(*) from public.cargo_ships) as ships, (select count(*) from public.cargo_circuits) as circuits,
  (select count(*) from public.convoy_cargo) as book,
  (select count(*) from cron.job j where j.jobname = 'byeharu-voyage:cargo-ships' and j.active) as job
```
-> 0, false, 0, 0, 0, 1.

Then, once, the real plan on prod, read only (`cargo_circuit_plan` is `s`): `select n.code, jsonb_array_length(p.p -> 'legs') as legs, p.p -> 'nm' as nm, p.p -> 'left_out' as left_out from public.great_powers g join public.nations n on n.id = g.nation_id cross join lateral (select public.cargo_circuit_plan(g.nation_id) as p) p order by 1`
-> the table above, `left_out` `[]` for all. Flags move, so the counts may differ.

## Before anyone lights it (owner only; not this slice)
**Lighting stops instant aid at the next `:37`. Cities late on a circuit then wait up to 5 hours for the first ship** (0308's table, and the 5.5-hour laps above). Also: V4 must ship first (`sea_traffic`'s count, her graphics), and check no player holds a `Crown Cargo %` name.

The 03:37 result in the REVIEW also matters: funds reached 168 cities and most were spent within the hour. A ship changes when the funds arrive, not how many are needed. It does not lower `E_CITY_BROKE` by itself.

## Tests
- **Red first** (`BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/cargo-ships/proof-0309.mjs`, cached world at 0308, 293 of 293 restored, no from-zero replay). **37 broken files, each red for its intended reason:** both paths paying; the branch ignoring the switch; shipped lit; the job working dark; no draw on the nation when lit; loading what is aboard; loading more than the capital holds; loading without taking; the live figure not moving; `tick_stats` or the fold leaving the funds out; a delivery 1 d. over; paying with the switch off; paying a city of another flag; ignoring port time; the rest not coming home; a load not yet gone sailing with the switch off; not mended; a wreck staying wrecked or not waiting; still paying the fee; every NPC docking free; two loads on a ship; a circuit not coming home; a left-out city dropped in silence; a flag change not rebuilding; a rebuild dropping a circuit in use; a client running the job or reading a circuit; no row security; the plan not stable; a hunk against another body; a hunk that does not reverse; a live function, knob, trigger or word touched.
- **What the red pass caught:** "the job works dark" first PASSED. The dark tick and its counts were one statement, so the counts read the snapshot from before it. Fixed by separating them. The same trap had hit the first draft's step reads.
- **Green:** the real file, 330 to 400 ms on PGlite, one DO block.
- **Proof 19** (`node scripts/db/proof.mjs 19_`, 9/9 markers, 2 to 8 s), the switch lit over the whole local world, rolled back: dark the real `city_day` pays by `CROWN_AID` with no `CONVOY` flow; 10 realms, 133 stops, every city; the real lit `city_day` writes no `CROWN_AID` and loads exactly 98,000 d.; every purse plus funds aboard summed, moved 0; live world total unmoved; **the fold reports `cities` and `set_aside` drift 0 with funds at sea**; a real `tick_stats` writes them into `stats_world.set_aside`; **one real lap of Portugal, 25 stops in order through `voyage.depart` and `voyage.settle`**, 49,000 d. delivered, 49,000 d. home, the book closed; no debt, wage, ledger row or forced home; hull whole; `voyage.fight` at four raider strengths, `raid_takes` and `insurance_claim` on a crewless hull, no error and nothing taken; a real arrival at hull 0 docks `UNABLE_TO_SAIL`, then is patched, waits and sails; compaction takes her voyages and reports.
- Proofs 16 (5/5), 17 (5/5), 18 (6/6, its dock-fee line now expects 0), 03 grants (12/12). eslint on the harness clean. `BYEHARU_PREFIX_CACHE=required npm run build` ran to the end. `src/` untouched.

## Not verified
- Nothing ran on prod: 0309 is not deployed, and no ship has ever sailed on prod.
- The self-assert's real time on prod (budget 45 s; 330 to 400 ms on PGlite).
- The real-Postgres path (`disposable-chain`): CI runs it on this PR. **PGlite has no `pg_cron`, so the `cron.schedule` line and its assert have not run locally.** It is 0304's line, with this job's name and schedule.
- **No two-session test.** PGlite has one connection, so the `SKIP LOCKED` in the step, the race of a load against a step, and the no-deadlock reasoning are by reading the code, not by a test.
- The real run time of a lit job, and the beat cost of about 5 more arrivals a minute (0308's item 7): not measured.
- The extra `E_CITY_BROKE` during the wait: only a lit run can show it.
- Weather on a lap varies by run, because the roll is seeded by the voyage id. A real pirate day was not guaranteed in the lap, so the fight is called by name. Bunching of ships is not measured.
- Lap times are arithmetic from one speed on the local world; the 1.5 minutes a port is an estimate.
