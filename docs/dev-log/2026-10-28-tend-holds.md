# 2026-10-28: 0269, the quay writes down its long holds (recording only)

Follows `2026-10-28-lap-start-spike.md`. That log proved the :07 lap-start lag comes from the reconcile's tend phase. It runs ~836 single-merchant quay transactions, some holding the quay ~1-1.4 s. It did not prove WHICH steps hold ~1 s, what they did, or why tend runs 25-32 s when the :06 count spills into :07 and 12 s when it does not. 0269 records those facts. It changes no decision.

## What 0269 records

| # | where | what |
|---|---|---|
| 1 | `reconcile_runs.receipt.tend_holds` = `{n, kept[≤300]}` | Each tend step that **held the quay > 100 ms, or waited for it > 100 ms**. Fields: fleet, route, house, `was` (fleet status / route pause when the step began), `asked` / `got` / `done` (quay asked for, granted, committed), `wait_ms`, `held_ms` = `step_ms` (npc_tend_route) + `check_ms` (her purse check) + `commit_ms`, and `did` (the step's non-zero counts and notes, or `"raised"`). |
| 2 | `lap_start_runs.receipt.steps[]` | Every lap start of the minute: `fleet`, `due`, `plan_at` / `plan_ms` / `plan`, `wait_at` / `wait_ms` / `late`, `open_at`, **`quay_ms`** (the open step's own wait for the quay), `open_ms`, `open`. |
| 3 | `public.arrivals_beats_kept` | The ring's beats of :06:30-:09:00 of each hour, copied at :10 by `byeharu-voyage:keep-beats` (`public.keep_reconcile_beats()`), kept 7 days. The window ends at :09:00, not :08:00, because the 11:07 reconcile ran to 11:08:50. |
| 4 | `public.stats_runs` | One row per count that finished (7 days). Fields: `at`, `slot`, `started_at`, `ms`, `receipt.phases` (prev, recent, period, world, goods, cities, city_goods, merchants, fold, day, live, in ms, in run order). A count that hits the 120 s timeout writes no row, as before; `cron.job_run_details` still has the error. |

Correction to the brief: `tick_stats` did NOT return phase times. It returned only the total `ms`. 0269 adds the phase stamps (11 hunks) and keeps the return object the same.

## Why nothing else moves

- There are 20 hunks: tick_reconcile 3, tick_lap_starts 6, tick_stats 11. Every one reverses to the live pre-image. They were cut from prod at head 0267 and checked offline against the prod bodies before the local apply.
- What the hunks add:
  - clock readings and new local variables;
  - one plain read of a merchant's route and fleet rows (takes no lock);
  - the receipts' new keys;
  - the count's own receipt row;
  - one extra request for the quay in the lap open's own subtransaction, right before `lap_start_open`. That function takes the same lock first thing; the second take is granted at once.
- The self-assert checks the hunks text-wise:
  - no new row lock, advisory lock or LOCK;
  - no new insert, update or delete, except stats_runs;
  - the quay is still taken first.
- 0265 / 0267 lock order is unchanged: the quay first, then her rows. Everything the bodies decide with is unmoved (md5): npc_tend_route, npc_plan, cmd.advance, lap_start_open / plan, the beat, the compactor, stats_compact / fold_day / live_fold, the quay.

## The self-assert's probes (all rolled back, from the same state)

- **Tend:** up to 8 merchants (4 the hour re-plans, 4 running, none the sweep asks in turn). Each runs through pg_temp copies of the OLD and the NEW tick_reconcile, plus the old again as a control. The new copy writes down every step (bar set to 0). The probe compares their rows (route, stops, lines, laps, orders, fleet, ships, voyages, purse, new ledger and events, port market and treasury) and the receipt.
- **Lap starts:** up to 3 resting merchants (route held, fleet docked, nothing queued), each made due alone. Old job, new job, old again; compares the same rows and the receipt, and checks one whole step entry.
- **Count:** old and new, two hours ahead. Compares the five stats tables' rows at that slot. The answer is compared with its clock readings masked: every `ms`, and `live.at`, which is `stats_live_fold`'s `clock_timestamp()` and differs between any two runs. The probe then checks the receipt row with 11 phases.
- **Kept beats:** 5 planted ring beats in an hour two hours ahead. Exactly the 3 inside :06:30-:09:00 are kept, once; an 8-day-old kept row is removed.

## Local results (PGlite, chain restored at 0267 + 0269)

- `0269 self-assert ok`. Tend: 4 merchants, same rows and receipt, 4 steps recorded with all fields. Count: same rows (1,380 city-goods) and same answer. Kept beats: 3 of 5.
- **The lap-start probe found 0 candidates in the chain's fresh world** (no merchant is resting there), so it proved nothing locally. On prod, 65 merchants are resting (read-only count, 12:5x UTC), so it will run there. To check it locally anyway, I used the same scratch session:
  - ran 6 merchants through their tend steps and resolved arrivals forward until 5 were resting;
  - aged their laps so their rest was over;
  - ran `pg_temp.lap_case_0269` old / new / old on 3 of them.
  - Result: control same, rows same, receipt same; all 3 opened a lap; each step was whole (`plan` 1, `open` 1, `quay_ms` 0, `open_ms` ~105).
- **The tend probe on a mixed sample** (8 from the roster after those starts): rows, control and receipt all the same. 5 steps were recorded; 3 were skipped as `waiting`. Example entry: `was` DOCKED/unassigned, `did` {started: 1}, held 365 = step 364 + check 1 + commit 0 ms.
- **Overhead, timed in the self-assert:**

| what | cost | inside the quay hold? |
|---|---|---|
| every tend step: route/fleet read + 4 clock readings | 34-36 µs | yes |
| a recorded step (`quay_hold_note`, timed with the list at its 300 cap) | ~0.76 ms | no (it runs after the COMMIT) |
| a lap start's entry (60-entry list) | ~83 µs | no (it runs after the COMMIT) |

- Per hour, that is ~836 × 35 µs ≈ **30 ms of extra quay hold**, against 6.7-13.4 s of tend hold. Both per-step costs (a recorded step, a lap entry) are paid outside the quay.

## PROD CHECKS (before deploy; read-only, run 2026-10-28 ~12:55 UTC)

Each is a pure SELECT from a file (`supabase db query --linked -f`). Only functions with provolatile `s`/`i` are called (`pg_get_functiondef` s, `wc_num` s).

1. The live bodies are the ones the hunks were cut against. Re-run before the push; it must still match:
   ```sql
   select p.proname, md5(replace(pg_get_functiondef(p.oid), E'\r', '')) from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.proname in ('tick_reconcile','tick_lap_starts','tick_stats') order by 1
   ```
   Expected (head 0267):
   - tick_lap_starts `39e33151a52f669935ef047fa4f9be7a`
   - tick_reconcile `5157faf7a854390bff49c066e887e372`
   - tick_stats `beff4f0f2cfbe6f33753252d374691e7`

   0268 (the switch lock) must not change these. If one differs, 0269 refuses at its hunk check, as designed.
2. There are lap-start probe candidates: 65 resting merchants (route held, docked, no pending/failed order).
3. **The migration takes ~2-4 min on prod**, with the clock unwound for that time. The count probe runs tick_stats twice. Recent prod counts took 54-95 s (12:06 95 s, 12:21 73 s, 12:36 61 s), and 10:21-11:51 timed out at 120 s. The guard sets `statement_timeout` 20 min.
   - **Push 0269 when the counts are healthy** (last 2 runs < 100 s, `jobid 58` in `cron.job_run_details`).
   - **Not during a slow window like 10:16-12:05.**
4. Order: **0268 first, then 0269** (one migration PR at a time). 0269's guard needs only 0267.

## After deploy: reading the recordings

All are pure SELECTs on the receipts.

**A. The long tend holds of an hour** (wait for the next :07; the receipt lands when the reconcile ends):
```sql
select r.at, (r.receipt->'tend_holds'->>'n')::int as n, e->>'got' as got, (e->>'held_ms')::numeric as held,
       (e->>'step_ms')::numeric as step, (e->>'check_ms')::numeric as purse_check, (e->>'commit_ms')::numeric as commit_ms,
       (e->>'wait_ms')::numeric as wait, e->>'was' as was, e->'did' as did, e->>'house' as house
  from public.reconcile_runs r, jsonb_array_elements(r.receipt->'tend_holds'->'kept') e
 where r.at > now() - interval '3 hours'
 order by (e->>'held_ms')::numeric desc limit 40
```
Then group by what the step did: `select e->'did' ..., count(*), sum(held_ms)` on the same rows. If `check_ms` dominates, it is the purse check, which reads an uncompacted house ledger (the compactor backlog). If `step_ms` dominates, group by `did`: started / resumed / waiting are re-plans; towed is a tow plus a repair.

**B. Lap starts in :07, per lap:**
```sql
select l.at, s->>'fleet' as fleet, s->>'due' as due, (s->>'plan_ms')::numeric as plan, s->>'wait_at' as wait_at,
       (s->>'wait_ms')::numeric as gap_wait, (s->>'late')::boolean as late, s->>'open_at' as open_at,
       (s->>'quay_ms')::numeric as open_quay_wait, (s->>'open_ms')::numeric as open, (s->>'open')::int as opened
  from public.lap_start_runs l, jsonb_array_elements(l.receipt->'steps') s
 where l.at >= date_trunc('hour', now()) + interval '7 minutes' and l.at < date_trunc('hour', now()) + interval '8 minutes'
 order by s->>'plan_at'
```

**C. The :07 beats, kept** (from :10 each hour), lined up against A and B:
```sql
select at, ms, (splits->>'q')::numeric as quay_wait, fleets, error from public.arrivals_beats_kept
 where at >= date_trunc('hour', now()) + interval '6 minutes 30 seconds' and at < date_trunc('hour', now()) + interval '9 minutes'
 order by at
```

**D. The count's phases** (ties tend's long hours to a count phase, or rules it out):
```sql
select at, started_at, ms, receipt->'phases' as phases from public.stats_runs where at > now() - interval '6 hours' order by at
```

- Job health: `select jobname, active from cron.job where jobname = 'byeharu-voyage:keep-beats'` should be active after `wind_the_clock()`.
- `cron.job_run_details` should show it succeeding at :10.

## What is NOT proven

- **The lap-start probe was vacuous in the chain's own world.** CI's disposable chain has the same world, so its run will also probe 0 merchants there. The probe is proven by the hand run above and will run on prod against 65 resting merchants.
- **Overhead on prod** was not measured. The local per-step figures are on PGlite. Prod reads of two rows by primary key should be the same order of magnitude or cheaper.
- **A count that times out records nothing**, so a stall like 10:16-12:05 leaves no phases. The cron log's error is all there is.
- **No trim is proposed.** This slice only makes the next diagnosis possible.
