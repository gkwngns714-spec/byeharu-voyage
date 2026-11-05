# 2026-11-05: merchants answer requests (migration 0315)

Owner, verbatim: "merchants should also look for request to be fulfilled - more profit."

Follows #494 (0311). 0312, 0313 and 0314 are other slices' numbers; this file does not read them.

## What changes in the game
- A merchant docking with a good a harbour asks for delivers it, part or all, the way a player does. She gets the bonus, the budget falls, Stats and the money log count it.
- What the budget does not pay for she sells at the quay as before.
- When she plans a lap she counts the bonus at the next stop, and looks at a good asked for there even if it is not one of her house's wares.
- Boards now fill by themselves. A new job, once a minute, sends overdue budgets home and posts new requests. Before, a request existed only if someone read that harbour.
- **New cron job, required by the owner's order:** `byeharu-voyage:contract-wind`.

## Decided by default (the owner may change any of these)
| Decision | Value | Why |
|---|---|---|
| Players first | merchants wait **6 hours**, knob `contract_npc_after_hours` (0 = compete from the start, a high value = off) | Told to the owner. |
| One door | `cmd.run_fulfil`, the players' own | Same partial delivery, budget, flows, event, ledger. |
| Real extra profit | she delivers when sale price + bonus meets her line's floor (paid + `npc_sell_margin`) | She never sells under her floor for a bonus. A sale the floor refused can land when the bonus lifts it. |
| A refused delivery | goes on to the normal sale | A poor city or a spent allowance is not a failed order. |
| What is left after a delivery | sold at the quay at her floor; if refused, it stays aboard and the order stands | The delivery already happened. |
| Lap books | the SELL order's `total` holds the bonus; `tax` and `wages` hold both parts | Closing a lap, trades, the month book and merchant Stats need no change. |
| The plan | a parcel must pay **on its own**; the bonus only joins its profit | Another merchant may spend the budget first, so a good that pays only by the bonus is never bought. |
| Never leave a route for a small bonus | the existing loop-switch rule (`npc_route_switch_pct` 10 %, or a tier) | No new rule. |
| A poor city | the job leaves a city under `treasury_reserve_floor` (50,000 d.) alone | **Added after measuring:** 135 of 795 route sales in 30 minutes were refused `E_CITY_BROKE`. Escrow is money a purse cannot spend. A read of that harbour may still post. |
| Pace | `contract_wind_ms` 4,000 a minute (0 = off), `contract_wind_retry_minutes` 60 | About 4 draws a minute at about 1 s a draw. |
| Who else | an ordered SELL, a player's route and a set-quantity SELL are untouched | The order said merchants. |

## Two bugs found while building, fixed here
- **A delivery could freeze the quay for a second.** `cmd.run_fulfil` wound the board first, which can draw (about 1 s). A merchant's delivery runs under the quay. It no longer winds; it judges the row's own deadline. A player's delivery loses the same second.
- **The bonus was paid on what she offered, not what sold.** A short purse shrinks a sale (0122) but 0311 paid on the full offer. Merchants sell into poor cities all day. Now it is paid on what landed.

## Why a new book
`bonus_figures.paid` read the ledger, but a merchant's ledger is compacted after `npc_retention_hours` (6). Stats' 24-hour figure would have lost her bonuses. `public.contract_deliveries` has one row a delivery, kept 2 days, and `paid` reads it. `ledger_premium_at` served only that read and is dropped; PREMIUM rows already on the ledger are copied across.

## Why the job is split
The first design wound in one transaction, as a read does: expiry takes the city's treasury row, then the draw holds it for about 1 s, and any sale at that harbour waits under the quay. So expiry moved to `public.contracts_expire`, and the job commits between expiry and post. The draw runs holding nothing a sale needs. The read door keeps its old order (a read of a harbour with overdue rows); with the job running, a read should rarely find one.

## Measured on prod (read-only, 2026-11-05)
- Head 0310. 246 harbours, 629 goods, an average 5.6 goods offered a harbour, about **619 goods a request can name** (10 harbours sampled, 605 to 624).
- Merchants, last hour: 2,493 laps with trades, 1,700 sold lines (85.6 M d.), **1,004 of a good that harbour does not offer** (32.7 M d., 86 units, 32,615 d. each). Only these can match a request.
- 4,255 legs in that hour; only 994 stops bought anything (1.12 goods a buy). Merchant net 4.03 M d. in an hour, about 96.7 M d. a day.
- Bonus: 8 % to 20 % of the mid, so about 14 % of a parcel.
- Purses: median 50,408 d.; 96 harbours under the 50,000 d. floor.
- Beats, last 30 minutes (two reads): p50 238-239 ms, p95 806-842 ms, p99 1,940-2,134 ms, 53-59 of about 1,750 over 1 s. Lap-start job: p50 57 s of its minute, 36-42 late, `due_left` 5.
- Route sales, last 30 minutes: 660 done, 135 refused `E_CITY_BROKE`.
- Treasury flow rows: 21,589 in 24 h.

## Estimate
**This is arithmetic, not a measurement. Nothing here has run on prod.**
- **Boards when full, with the floor gate:** about 335 requests at 145 harbours (92 hold three). 101 harbours post nothing today, mostly the ones under the floor. Lot used: the sampled mean, 1,184 d.
- **Gold held:** up to about **143 M d.** (it was 5,873 d. live on 2026-11-05, plus 6.56 M d. stale). About 132 M of that is 44 rich cities holding three full budgets. Median harbour: 8,333 d.
- **Requests delivered a day: about 40 to 255.**
  - Low: only what she carries anyway. 24,100 eligible lines a day x (1.36 asks a harbour / 619 goods) x 0.75 (18 of 24 hours past the wait) = about 40.
  - High, adding the plan: 102,000 legs a day x 5.6 goods x 1.36 / 619 x 0.75 = about 940 legs with a chance, x 23 % (legs that buy at all) = about 215 more. An upper figure: the plan re-lines at each lap start, the good must pay on its own, and merchants share one budget.
- **Bonus paid a day: about 0.2 M to 1.2 M d.** (about 4,600 d. a delivery, 14 % of a 32,615 d. parcel).
- **Extra merchant profit: the same figure, about +0.2 % to +1.2 %** on 96.7 M d. a day. It comes from city escrow; nothing is minted. **It is small.** The 6-hour wait and the one-good-in-619 match are why: `contract_npc_after_hours` 0 lifts it by a third.
- **Job load:** first fill about 335 posts at 4 a minute, about 1.5 hours. After that about one post every 4 minutes, plus one retry an hour at each harbour that cannot post. At most about 4 s of a minute's work.
- **A merchant's sale:** one indexed read more, at most 3 rows. A delivery about 8 ms more than a plain sale (PGlite, median of 20: 16 against 8 ms; not measured on prod), about 40 to 255 of them a day.
- **Flow rows:** at most about 670 more a day, about +3 %.

## Risk to watch
**Cities pay for this.** Once boards fill, up to 143 M d. sits in escrow instead of purses. Cities near the floor post until they go under it, then stop. So a city with a little above 50,000 d. can dip under it and draw on `CROWN_AID`. Already one route sale in six is refused `E_CITY_BROKE`. If after-check 9 shows that getting worse, set `contract_wind_ms` to 0.

## Proof
- `scripts/ops/harness/city-requests/proof-0315.mjs`, cached PGlite world, no from-zero replay: every mutation red for its reason, the real file green dark and on a lit, closed world, then the job as cron runs it, with real commits. The mutation count is printed by the run.
- The self-assert covers: too young; answered, spent, the rest sold, nothing made; the ledger, the book, the event, Stats; the floor kept and the floor lifted; not a player, an ordered sale or a set quantity; the knob both ways; a short purse; the allowance; a delivery past its deadline; a delivery draws nothing; the lap's books against her purse; the wind (overdue goes home, topped up to the cap, full board not asked, under the floor left alone, no surplus rests, resting not asked, budget, off); the plan (young not counted, the bonus in the leg's profit to the ducat, a good outside her wares looked at).
- A planner hunk is checked through `public.npc_leg_lines`. No real merchant steps in the self-assert.

## Not proven here
- Nothing has run on prod, so the estimate above is unmeasured.
- Real Postgres: the self-assert has run only on PGlite until CI's `disposable-chain` runs it. `cron.schedule` runs only there and on prod.
- The self-assert's `npc_leg_lines` at Lisbon on prod: not run (volatile). Read-only proxy: `world.trade_routes` gives 9 rows on that leg.
- No browser check: no client file changes.

## PROD CHECKS (pure SELECTs from a file, one statement per file, before deploy)
1. Head, and the six bodies the hunks were cut against:
```sql
select (select max(version) from supabase_migrations.schema_migrations) as head,
  md5(replace(pg_get_functiondef('cmd.execute_order(uuid)'::regprocedure), E'\r', '')) as execute_order,
  md5(replace(pg_get_functiondef('cmd.run_fulfil(uuid,uuid)'::regprocedure), E'\r', '')) as run_fulfil,
  md5(replace(pg_get_functiondef('cmd.run_manifest(uuid,jsonb)'::regprocedure), E'\r', '')) as run_manifest,
  md5(replace(pg_get_functiondef('public.tick_contracts(uuid,timestamp with time zone)'::regprocedure), E'\r', '')) as tick_contracts,
  md5(replace(pg_get_functiondef('public.bonus_figures(uuid,timestamp with time zone)'::regprocedure), E'\r', '')) as bonus_figures,
  md5(replace(pg_get_functiondef('public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)'::regprocedure), E'\r', '')) as npc_leg_lines
```
-> head `20260818000314`, `b7f6aeca159bb8331dd5bc40eca2ffcf`, `dea3e4a2b099bab3e0e7b845b0c7ff20`, `e9b6ae9e4b70f13c21133d2f4ade3ac2`, `d9d0a9e09ef087c8a36f42ccc339fa1d`, `6faefba35c32a9db821416975e67d89d`, `5f0462448098a70a4583dbe1b823c3a3`. Run on prod 2026-11-05 at head `20260818000313`: all six equal these. The fix numbered 0314 changes `voyage.settle`, none of these bodies, so they should not move; if one does, the self-assert's hunk check fails safe (nothing is kept).

2. Nothing owes the new job a surprise:
```sql
select (select count(*) from cron.job where jobname = 'byeharu-voyage:contract-wind') as job_exists,
       (select count(*) from public.world_config where key in ('contract_npc_after_hours', 'contract_wind_ms', 'contract_wind_retry_minutes')) as knobs,
       (select count(*) from public.world_config where key in ('treasury_reserve_floor', 'npc_buyers_per_good')) as read_knobs,
       (select count(*) from public.trade_contracts where premium_per_unit <= 0) as no_bonus_rows
```
-> 0, 0, 2, 0. Run 2026-11-05: 0, 0, 2, 0.

3. The probe's leg still carries two goods:
```sql
select jsonb_array_length(world.trade_routes(p.id, null, null, 12, ((world.trade_routes(p.id, null, null, 12, null)->'routes'->0->'to'->>'id')::uuid))->'routes') as leg_rows
  from public.ports p where p.code = 'LIS'
```
-> 2 or more. Run 2026-11-05: 9.

## After-check, 30 minutes, and again when boards fill (about 2 hours)
Stamp the deploy as T. Pure SELECTs, one statement per file.

4. The job runs and stays in its budget:
```sql
select count(*) as runs, max(ms) as max_ms, sum((receipt->>'tried')::int) as tried, sum((receipt->>'posted')::int) as posted, sum((receipt->>'failed')::int) as failed,
       sum((receipt->>'home')::bigint) as home, max(receipt->>'note') as note
  from public.contract_wind_runs where at > 'T'
```
-> `failed` 0; `max_ms` under about 6,000; `posted` up to about 4 a minute. `home` about 6.56 M d. at the first runs, if those rows are still overdue.

5. Cron agrees:
```sql
select d.status, count(*), max(d.end_time - d.start_time) as longest
  from cron.job_run_details d join cron.job j on j.jobid = d.jobid
 where j.jobname = 'byeharu-voyage:contract-wind' and d.start_time > 'T' group by 1
```
-> `succeeded` only.

6. No beat or lap budget worsens:
```sql
select (select jsonb_build_object('n', count(*), 'p50', percentile_cont(0.5) within group (order by ms), 'p95', percentile_cont(0.95) within group (order by ms), 'p99', percentile_cont(0.99) within group (order by ms), 'over_1s', count(*) filter (where ms > 1000)) from public.arrivals_beats b where b.at > 'T') as beats,
       (select jsonb_build_object('late', sum((receipt->>'late')::int), 'due_left', max((receipt->>'due_left')::int), 'open_ms_max', max((receipt->>'open_ms_max')::numeric)) from public.lap_start_runs r where r.at > 'T') as laps
```
-> near p50 239, p95 about 840, p99 about 2,130, 59 over 1 s in 1,730; 42 late, `due_left` 5. Worse by more than 15 %: stop the job and look.

7. Merchants deliver, and the books agree (after 6 hours for a request the job posted; requests already standing older than 6 hours qualify at once):
```sql
select p.is_npc, count(*) as deliveries, sum(d.bonus) as bonus, count(distinct d.port_id) as harbours
  from public.contract_deliveries d join public.players p on p.id = d.player_id
 where d.at > 'T' group by 1
```
-> a merchant row within 7 hours of T. Under about 15 a day after a full day means the low end is too high; say so, do not tune.

8. The money:
```sql
select (world.stats_now()) ->> 'total' as total, (world.stats_now()) -> 'drift' as drift, public.bonus_figures(null, now() - interval '24 hours') as bonus,
       (select count(*) from public.trade_contracts where status = 'open' and expires_day <= world.game_day(now())) as overdue_left
```
-> `drift` all zero; `held` under about 143 M; `overdue_left` falling to about 0.

9. The cities:
```sql
select count(*) filter (where o.executed_at > now() - interval '30 minutes' and o.error_code = 'E_CITY_BROKE') as broke_30m,
       count(*) filter (where o.executed_at > now() - interval '30 minutes' and o.verb = 'SELL' and o.status = 'done') as sells_done_30m,
       (select count(*) from public.ports p where p.kind = 'HARBOUR' and public.treasury_balance(p.id) < 50000) as under_floor
  from public.orders o where o.status in ('done', 'failed', 'skipped') and o.route_lap_id is not null
```
-> near 135, 660, 96. `broke_30m` up by more than a quarter, or `under_floor` up by more than 15: set `contract_wind_ms` to 0 (owner's call, forward).

## Forward rollback (a NEW migration, owner only)
To stop harm at once, no code: `contract_wind_ms` 0 stops the job's work; `contract_npc_after_hours` 1000000 stops merchants answering. Open requests drain on their own deadline, through a read.
To go back in full:
1. `cron.unschedule('byeharu-voyage:contract-wind')`.
2. The six bodies back to their pre-images (digests in PROD CHECK 1). Keep the short-purse fix unless the owner says otherwise: the pre-image pays a bonus on units that did not land.
3. `bonus_figures.paid` back on the ledger, `ledger_premium_at` rebuilt, `contract_deliveries`, `contract_wind`, `contract_wind_runs`, `contracts_expire`, `contract_asks`, `cmd.do_sell_answering` and `tick_contract_wind` dropped, the three knobs removed.
4. Before dropping, expire overdue rows through the job or a read, so no escrow is left stranded.
