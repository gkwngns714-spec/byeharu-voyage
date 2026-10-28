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
