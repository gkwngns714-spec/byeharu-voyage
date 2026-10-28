# 2026-10-28 — The beat keeps its own clock (`osn-beat-splits`, migration 0261)

Owner order 2026-10-28: find the ROOT cause of the slow arrivals beat, then fix the root. No more guess-trims.
0248 / 0250 / 0256 trimmed what a local profile showed; prod barely moved (p95 ~1.6-1.7 s outside the reconcile).
By the fit a prod departure costs ~170 ms and a sale ~75-130 ms, against ~17 ms and ~8 ms locally (10x or more),
while readers timed alone are only 2-4x slower on prod.

## What was found before building (prod, read-only, head 0259, 10-28 ~00:10 UTC)

- **The purse checks are not in `arrivals_beats.ms`.** `ledger_reconciles` (ledger INSERT) and `players_purse_reconciles`
  (players INSERT/UPDATE) are constraint triggers, DEFERRABLE INITIALLY DEFERRED. They fire at the beat's COMMIT. The beat
  stops its clock before that commit (`tick_arrivals_each_second`: `ms` = hold_the_quay + tick_arrivals). So the lead
  suspect (every credit sums a house's whole uncompacted ledger) cannot be what makes the 1.6 s p95; it can only cost
  time between beats (runs a minute).
- **64 s of `pg_stat_user_tables` / `pg_statio_user_tables`** (cluster-wide, the beat dominates):
  - ledger: 608 index scans fetching 825,310 rows (~1,357 a scan) = 304 inserts + 304 player updates, one `ledger_sum`
    each. 384 k buffer hits, 351 heap + 1,725 index blocks read from outside shared_buffers.
  - Blocks read from outside shared_buffers, per minute: standing_route_laps 5,202 + 430, orders 2,257 + 370,
    voyage_events 1,979 + 517, port_goods 1,130 + 463, voyages 1,092 + 453, events 133 + 578, insured_voyages 74 + 321.
    About 17-18 k a minute in all (~290 a second). `track_io_timing` is off, so what each read costs is not on record.
  - Small tables read whole many times: skill_effects 1,962 seq scans (353 k rows), goods 1,015 (300 k), skills 1,746.
  - Prod: PostgreSQL 17.6, shared_buffers 256 MB, database 2.46 GB, synchronous_commit on.

## What 0261 does

`public.arrivals_beats.splits jsonb`, one object a beat, in ms:

| key | what |
|---|---|
| q | waiting for the quay (`hold_the_quay`) |
| run | `tick_arrivals()`; q + run = ms as before |
| arrive / repair / held / wake / ask | tick_arrivals' five loops (arrive = the due voyages settled: sea-days, arrivals, the stop's sells / buys / lines, a route's next SAIL) |
| defer | the deferred purse checks, fired by `SET CONSTRAINTS ALL IMMEDIATE` just before the row is written |
| commit | the commit (WAL flush), written by the next transaction |
| reads / reads_defer | per table, [blocks read from outside shared_buffers, blocks hit], for the run and for the checks |
| probe | what taking the readings cost, every beat |

- `public.beat_reads()` reads this backend's `pg_stat_get_xact_blocks_fetched / _hit` per game table (an index and a toast
  table count to their table); `public.beat_reads_diff` takes two readings' difference. Both server-only.
- tick_arrivals: 6 hunks, each only adds a `clock_timestamp()` reading into two new locals, and one
  `set_config('byeharu.beat_split', …, true)` before its return. The beat: 3 hunks. Same commits, same order.
  The purse checks fire at SET CONSTRAINTS instead of at the COMMIT right after: the same checks, same order, same
  transaction; one that fails aborts the procedure exactly as a failing commit did. `ms` keeps its meaning.

## The proof

- Self-assert: the 9 hunks reverse to the live pre-image; ACL / volatility / definer / config unmoved; credit, ledger_sum,
  the purse checks and the quay lock unmoved (md5); `byeharu.beat_split` named by exactly 2 functions; arrivals_beats has
  no trigger and no deferrable constraint; the readings work (a fixed diff checked) and are private. OLD run (pg_temp copy)
  vs NEW run from the same state at the first due voyage + 20 s, each rolled back, then OLD again as the control: the same
  answer and the same digest (at-sea voyages, fleets, ships, purses, quay stock, city purses, this transaction's ledger
  rows and events with uuids blanked).
- Local (PGlite, merchant world lit, 60 voyages rewound due each round): 3 rounds, 62-65 fleets and 190-216 sea-days
  each, old = new = control on answer and digest. `call tick_arrivals_each_second(4)`: 4 rows with splits, probe 5-7 ms
  on wasm.

## Measurements

Prod: below, after the deploy.

## Deployed (0261)

2026-10-28 ~00:31 UTC: PR #373, push landed at head 0261, merged cd53b39, main Acceptance green. Beats resumed at 00:32
(the first beat worked the deploy's backlog: 10.1 s, 59 fleets); 0 errors.

## First splits (prod, 00:34-00:43 UTC, 532 beats outside :07-:09)

| phase | share of beat time | mean ms | p95 ms |
|---|---|---|---|
| q (quay wait) | 0.0 % | 0.1 | 0.1 |
| arrive (due voyages settled) | 39.4 % | 257 | 640 |
| held (paced routes wake: a lap starts) | **47.5 %** | 310 | 1,411 |
| wake (port time up) | 12.1 % | 79 | 244 |
| repair / ask | 0.7 % | | |
| defer (the purse checks, outside ms) | 5.5 % of ms | 36 | 96 |
| commit | | 1.9 | 3.4 |
| probe (0261's own readings, outside ms) | | 27 | 34 |

- **The ledger is not the cause.** The purse checks cost ~36 ms a beat (p95 96 ms), all at the commit and outside `ms`;
  hot `ledger_sum` timed on prod: ~2-4 ms for an unrolled house (~1,200 rows), ~0.2-0.4 ms for a rolled one.
- **The held loop sets the p95.** Beats over 1 s (18 %): held 1,405 ms of a 1,957 ms run. Joined to the laps started at
  each beat's instant: no lap start, run 308 ms; one, held 594 ms; two, 1,115 ms; three, 2,474 ms. Review laps (every 6th)
  cost no more than others.
- **The run's time is the pages it touches:** run = 0.51 ms a block read from outside shared_buffers + 13.5 µs a buffer
  hit, R² 0.97 (hits 73 % of the time, reads 27 %). A held-heavy beat touches ~100 k buffers (world_config 22 k,
  port_goods 17 k + 363 cold reads, orders 12 k, ports 7 k, goods 5.6 k, treasury_flows 5 k); a beat with no lap start ~16 k.
- A lap start is `cmd.run_standing_route` at the lap's head: `public.npc_plan(p_now, route)` re-plans her lines leg by leg
  (`npc_leg_lines` → `world.trade_routes`, quotes, caps), then the stop's lines and her SAIL. The earlier local profiles
  timed port-time SAILs and arrivals, not this path. On prod, read-only: `world.trade_routes` ~40 ms a leg,
  `npc_loop_candidates` ~150 ms a call.
- `probe` is 24-36 ms a beat on prod (pg_class is larger than locally): outside `ms`, but it is wall time; the fix slice
  will thin or drop it.

## 0262: one beat in four names its functions

Which function inside a lap start holds the ~600 ms is not measured yet. `track_functions` is in
`supautils.privileged_role_allowed_configs` and postgres holds that role (SET LOCAL takes, checked read-only). So 0262
runs one beat in four with `SET LOCAL track_functions = 'all'` and stores `splits.fn`: the 40 functions with the most
self time (calls, total ms, self ms) and the totals. 3 hunks in the beat; tick_arrivals untouched (md5). A refused
setting leaves that beat unprofiled. Local: self-assert ok; 8 beats, profiled ones carry `fn`.
