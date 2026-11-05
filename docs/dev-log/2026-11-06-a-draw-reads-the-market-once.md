# 2026-11-06: a draw reads the market once (migration 0318)

The job `byeharu-voyage:contract-wind` (0315) slowed the first seconds of every minute. This slice finds why and fixes it. Merchants answering requests, the bonus, the budgets and the 6-hour wait do not change.

## The cause, measured on prod (read-only, 2026-11-05 17:13-17:30 UTC, head 0315)

**It is not a lock. It is processor time, at the worst seconds of the minute.**

What the job holds:
- Read of the body: each post is its own transaction. The draw takes no row lock. The insert and `treasury_post` come last and commit at once. A BOUNTY post has no `p_player`, so it skips `public.treasury_lock`. The job never takes the quay (`hold_the_quay`).
- 23 wait samples of `pg_stat_activity` around :02, :06 and :10 of 8 minutes: the job was caught in 8, and on the processor in 8 of 8, never on a lock or the disk.
- The quay split of a first beat is 0 ms before and after.

Why 3 posts take 5 s: `public.contract_draw` asks `world.daily_cap_remaining` for all 629 goods, one at a time. Each call is a nest of SECURITY DEFINER functions with SET (`wc_num`, `player_skill_bonus`, `works_factor`, `city_level`, `game_day`).
- Four draws in one session: about 0.75 s a draw, alone, in calm seconds (wall clock against `select 1`, three reads).
- One draw's transaction was seen at 2.6 s old in the pile-up at :02.
- The harbour pick costs 0 to 0.3 s by the same clock: not the problem.

Why that hurts: pg_cron starts the job at :00 with arrivals, lap-starts, drift, compact and cargo-ships, each a new session that must compile and plan from cold. It adds 4-6.5 s of work to the only seconds already short.

### The overlap figures overstate it
Beats overlapping the job are the first beats of the minute, and those were slow before the job. The fair comparison is the same seconds before and after. Before: minutes :08 and :09 kept in `arrivals_beats_kept`, 25 hours to 16:08. After: `arrivals_beats` from 16:45, without the minutes of the Stats job.

| Second of the minute | Before p50 / p95, ms | After p50 / p95, ms | Over 1 s, before | Over 1 s, after |
|---|---|---|---|---|
| 0-1 | 1,702 / 2,643 | 2,836 / 4,142 | 27 of 37 | 32 of 33 |
| 2-4 | 383 / 1,281 | 767 / 2,011 | 9 of 71 | 27 of 65 |
| 5-7 | 304 / 687 | 354 / 862 | 1 of 75 | 3 of 89 |
| 8-12 | 278 / 568 | 356 / 755 | 0 of 125 | 1 of 156 |
| 13-59 | 208 / 595 | 214 / 585 | 5 of 1,175 | 8 of 1,467 |

- Time per 1,000 buffers in the first beat: 44.0 -> 60.5 ms; share of buffers missed 0.52 % -> 0.71 %. The same reads took longer, which points at the processor. This is a correlation across eras, not a controlled test.
- Seconds 2-4: the slower first beat leaves more due, so fleets a beat go from 11.5 to 18, and the wait for the quay from 42 to 131 ms.
- Lap starts: late laps 85-88 an hour before (21-22 per 15 minutes), 41 in the 15 minutes from 17:00. Lag p95 6.3 s -> 10.4-12.8 s; plan and open times did not move. Her job waits for the quay behind the longer first beat (5 of 23 samples on the advisory lock, all at about :02).

**Not caused by the job:** the first beat over 1 s is older than it. This fix cannot take the first beat under about 1.7 s.

**Not explained:** 17:13:00 had one beat of 10,033 ms with 307 fleets, and 128 fleets at 17:13:10. It lifts the averages at second 0 (fleets 21.4 with it, about 12 without) and p99. The job ran normally that minute. The cause was not looked for.

**It would have ended by itself, mostly:** at 17:20, 334 slots were left, at 2.74 posts a minute, so the job would go quiet at about 19:20 UTC, with about one post every 4 minutes after that (0315's estimate). The draw would still cost a second at every read door and every later post.

## The fix
- `public.daily_cap_base(player, port)`, new: the part of a daily cap that does not depend on the good. One inlined SELECT.
- `world.daily_cap_remaining`: reads that base. The same figure, and still the one authority for a good's cap.
- `public.contract_draw`: reads the base once, joins `port_goods` once, anti-joins `port_offered_goods` once. The same candidates in the same order, so the same good, quantity and bonus.
- `public.tick_contract_wind`: stops at `contract_wind_posts` asked in a run.

## Decided by default (the owner may change any of these)
| Decision | Value | Why |
|---|---|---|
| Make the draw cheap, not move the job | no schedule change | It removes the cost instead of moving it. A job that sleeps to :20 holds a connection and still burns 4 s. |
| A count of posts a run | knob `contract_wind_posts` = 3 | Only the clock held the pace. With a cheap draw, 4,000 ms would let far more through and pull up to 143 M d. out of city purses in minutes. Measured: 2.74 posted, 2.81 asked a run. 3 is the nearest whole number, about +9 % at most. |
| `contract_wind_ms` | unchanged, 4,000 | It stays the ceiling. |

## Proof
`scripts/ops/harness/city-requests/proof-0318.mjs`, cached PGlite world, no from-zero replay. Run with `PROOF_WORLD=browser`: this PC's preamble cache stops at 96 files, so the world came from the image's cache, 300 of 300 restored.
- Red first, the world as it is: 1,053 `works_factor` calls a draw, 192.7 ms; the job's only stops are the clock and an empty list.
- 14 of 14 mutations red for their reason.
- Green: the real file dark and on a lit, closed world (565 ms); 1 call a draw, 1.2 ms (155 x cheaper here; PGlite, so the ratio is the figure, not the milliseconds); the job as cron runs it, with a 30-second clock and real commits, stops at 3 posted, 13 ms.

The self-assert compares the old body (a `pg_temp` copy of the pre-image) with the new: every good's cap for a real house with a market work built; 3 harbours' draws; a draw where the cap excludes about half the goods; `works_factor` calls a draw; the job's stop at its count and at 0. Every row is rolled back.

Read-only on prod, a pure SELECT of the new shape: LIS, day 20000, seq 1 gives the same good as the live draw. A first shape that still called `port_offers` per good cost about 75 ms a draw over 40 draws (wall clock), against about 750 ms. The file's shape replaces that with one anti-join; it has not run on prod.

## Not proven here
- Nothing has run on prod. The figure that matters is the after-check.
- That removing the job's CPU gives the "before" column back: the cause is inferred from code, wait samples and per-buffer time. No controlled run was possible on prod.
- The job's cold start: each run is a new session, and that compile cost stays.
- The new draw's millisecond cost on prod.
- The call-count check in the self-assert runs only where `track_functions` may be set. CI's real Postgres refuses it, so there the check of the body stands alone. The beats do set it on prod, but this migration's role there is not proven.
- Compute size was not read from the platform; "processor" means the wait samples show no wait.

## PROD CHECKS (pure SELECTs from a file, one statement per file, before deploy)
1. Head and the three bodies the hunks were cut against:
```sql
select (select max(version) from supabase_migrations.schema_migrations) as head,
  md5(replace(pg_get_functiondef('public.contract_draw(uuid,integer,integer)'::regprocedure), E'\r', '')) as draw,
  md5(replace(pg_get_functiondef('world.daily_cap_remaining(uuid,uuid,uuid)'::regprocedure), E'\r', '')) as cap,
  md5(replace(pg_get_functiondef('public.tick_contract_wind(boolean,uuid)'::regprocedure), E'\r', '')) as wind
```
-> head `20260818000317`, `60b3a021e641c34341bb1642f134ca39`, `5d5d13deff13203a292b42240767e47d`, `cd8663a11122db4264fd7ebc45f3d955`. Bodies read 2026-11-05 at head 0315. If one moved, the hunk check fails safe (nothing is kept).

2. The probe's selection and nothing owed:
```sql
select (select count(*) from public.world_config where key = 'contract_wind_posts') as knob,
       to_regprocedure('public.daily_cap_base(uuid, uuid)') as helper,
       (select count(*) from public.world_config where key in ('market_cap_per_level', 'daily_cap_fraction', 'contract_open_max', 'treasury_reserve_floor', 'trade_step_tuns', 'contract_qty_steps_min')) as read_knobs,
       (select count(*) from (select p.id from public.ports p
         where p.kind = 'HARBOUR' and not exists (select 1 from public.contract_wind w where w.port_id = p.id)
           and not exists (select 1 from public.trade_contracts c where c.port_id = p.id and c.status = 'open' and c.expires_day <= world.game_day()) limit 3) x) as probes
```
-> 0, null, 6, 3. Run 2026-11-05 at head 0316: 0, null, 6, 3.

## After-check, 30 minutes (stamp the deploy as T; pure SELECTs, one statement per file)
3. The job: fast, at its pace, nothing failed:
```sql
select count(*) as runs, round(avg(ms)) as avg_ms, max(ms) as max_ms, round(avg((receipt->>'posted')::numeric), 2) as posted_avg, max((receipt->>'tried')::int) as tried_max, sum((receipt->>'failed')::int) as failed
  from public.contract_wind_runs where at > 'T'
```
-> `avg_ms` under about 1,000 (was 4,678), `posted_avg` about 2.7 to 3 while boards fill, `tried_max` 3, `failed` 0.

4. The beats, the same seconds as the table above:
```sql
with b as (select ms, (splits->>'q')::numeric as q, extract(second from at) as s from public.arrivals_beats
            where at > 'T' and extract(minute from at)::int not in (6, 7, 21, 22, 36, 37, 51, 52))
select case when s < 2 then '00-01' when s < 5 then '02-04' when s < 8 then '05-07' when s < 13 then '08-12' else '13-59' end as sec, count(*) as n,
       round(percentile_cont(0.5) within group (order by ms)::numeric) as p50, round(percentile_cont(0.95) within group (order by ms)::numeric) as p95,
       count(*) filter (where ms > 1000) as over_1s, round(avg(q)) as q
  from b group by 1 order by 1
```
-> near the Before columns: 00-01 p50 about 1,700; 02-04 p50 about 380, about 13 % over 1 s. Worse than the After columns: forward rollback.

5. Lap starts:
```sql
select count(*) as runs, sum((receipt->>'late')::int) as late, round(avg((receipt->'lag_ms'->>'p95')::numeric)) as lag_p95, sum((receipt->>'due_left')::int) as due_left
  from public.lap_start_runs where at > 'T'
```
-> about 43 late in 30 minutes, `lag_p95` about 6,300.

6. The money and the draws:
```sql
select (world.stats_now()) -> 'drift' as drift, (select count(*) from public.trade_contracts where created_at > 'T') as posted_rows, (select count(*) from public.contract_deliveries where at > 'T') as deliveries
```
-> `drift` all zero; `posted_rows` about 80 to 90 in 30 minutes while boards fill, not hundreds.

## Forward rollback (a NEW migration, owner only)
To stop the job at once, no code: `contract_wind_ms` 0. In full: the three bodies back to their pre-images (digests in check 1), `daily_cap_base` and `contract_wind_posts` dropped. Rows posted stay; they drain on their own deadline.
