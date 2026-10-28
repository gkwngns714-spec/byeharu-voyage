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

## Deployed (0262)

2026-10-28 ~01:00 UTC: PR #374, push landed at head 0262, merged 95e0731, main Acceptance green. Profiled beats cost
the same as the others (median ms 337 vs 327), so `track_functions` itself is not visible in the numbers.

## The per-function profile (prod, 01:03-01:20 UTC, 187 profiled beats)

Beats with a lap start in the held loop (29 profiled, mean run 1,672 ms), per beat:

| function | total ms | self ms | calls |
|---|---|---|---|
| cmd.advance | 1,518 | 30 | 5.6 |
| public.npc_plan (the lap start's re-plan) | **779** | | 1.3 |
| public.npc_leg_lines | 636 | 32 | 20.4 |
| world.trade_routes | 373 | 64 | 20.4 |
| world.quote_priced | 266 | 162 | 303 |
| public.wc_num + public.wc (knob reads) | 221 + | 114 + 139 | 4,495 + 5,768 |
| public.npc_loop_candidates | 188 | 155 | 0.7 |
| world.mid_terms | 110 | 38 | 545 |
| cmd.standing_route_close_lap | 70 | 68 | 0.6 |
| public.ledger_sum (purse checks) | 67 | 67 | 28 |

All 187 profiled beats (mean run 542 ms): npc_plan 122 ms a beat (22 %), close_lap 54 ms self (~130 ms a lap close),
wc + wc_num 65 ms self (12 %), ledger_sum 33 ms (outside ms), 0261's own beat_reads 23 ms.

**The root cause:** the arrivals beat's slow seconds are the seconds in which a merchant's lap starts. Each lap start
re-plans her loop on today's prices (`npc_plan`, 0114): ~11 legs, each `world.trade_routes` over both quays plus up
to 12 quoted goods, and on most lap starts up to 16 candidate loops (`npc_loop_candidates`). That is ~600 ms a lap
start on prod and ~215 ms locally. 0250 / 0256 trimmed paths that do not include it (a port-time SAIL, an arrival), so
prod did not move. The ledger backlog (the lead suspect) costs ~30 ms a beat, at the commit, outside `ms`.

## 0264: a lap start reads only what it weighs (same answers)

Three cuts, each from the profile above:
1. `npc_loop_candidates`' rank of trade destinations reads only the goods each city makes (`haul_nm = 0`, ~6 of ~565
   rows a port) through a new partial index `port_goods_makes_0264`, not every market row of every destination looked
   up at home. Same maxima and nulls.
2. `wc_num` / `wc_int` become SQL-standard bodies (BEGIN ATOMIC), no definer, no SET, so they are inlined: a knob read
   is one definer call (`wc`, untouched), not two. ACL kept.
3. 0261's block readings only in the profiled beats (one in four).

The index is created LAST, so its SHARE lock on port_goods is held only to the commit, not through the probe.

Proof (self-assert): the hunks reverse; wc, npc_plan, npc_leg_lines, tick_arrivals, credit unmoved (md5); the knob read's
plan calls `wc` directly. OLD vs NEW: every knob (number, integer, a missing one); candidates for 60 merchant routes;
`npc_plan(now, route)` for 12 merchants resting at home, old bodies, new, old again (control), each rolled back.

Local (PGlite, merchant world lit, 6 rounds of rewound laps, ~200 resting at home): self-assert ok (282 knobs, 60 routes
/ 802 loops, 12 re-plans alike). Negative control: the back haul read from the wrong side: 16 of 60 routes differ.

| local, old vs new | old | 0264 |
|---|---|---|
| npc_loop_candidates, a call (60 routes, 2 passes) | 57.2 ms | 32.8 ms (−43 %) |
| wc_num, 20,000 reads | 497 ms | 315 ms (−37 %) |
| npc_plan, a lap start (20 resting, 3 passes) | 214.7 ms | 190.7 ms (−11 %) |

What 0264 does not do: after it, a re-plan is still mostly the pricing itself (local profile of 20 plans:
`quote_priced` 153 calls a plan, `mid_terms` 284, `trade_routes` 11, `wc` 2,215). Same-answer trims can only shave
that. Cutting it at the root changes WHEN or HOW OFTEN a merchant re-plans, which changes game results. That is the
owner's call (below, after the after-check).

PR #375's first CI run: `duplication.spec.ts:370` red (the header did not say "supersede"; fixed). Also red, first
sighting: `map.sun.spec.ts:305` (npc 2/2), `wide.lanes.length` 0 after 12 zoom-outs. Not caused by 0264: on the local
merchant world, `world.sea_traffic` with the old bodies and with the new serves the same 240 fleets, 49 with a lane;
no earlier failure of that test in the last 40 Acceptance runs. Recorded, not re-run; the fixed commit's run is the
next reading.

## Deployed (0264) and after-check

2026-10-28 ~02:53 UTC: PR #375, push landed at head 0264, merged dcaf531. Main Acceptance on dcaf531 went red on
`tests/map.perf.spec.ts:100` ("the wheel did not zoom the chart"): a test race, not 0264 (diagnosis and fix in PR #377,
`osn-zoomstep-wait`); main is green again on d12e482. 0265 (the compactor, every minute) merged 03:15, so the clean
0264 window is 03:00-03:12; after that both changes are in the numbers.

| beats outside :07-:09 | before (01:55-02:52, 0263) | after (03:00-03:12, 0264) | after + 0265 (03:16-03:32) |
|---|---|---|---|
| beats / fleets a beat | 3,045 / 10.96 | 457 / 10.75 | 789 / 12.41 |
| runs a minute | 56.6 | 57.2 | |
| p50 | 348 ms | 349 ms | 366 ms |
| p95 | 1,720 ms | **1,539 ms** | 2,012 ms |
| max | 6.1 s | 3.0 s | |
| over 1 s | 13.4 % | 14.0 % | 17.2 % |
| errors | 0 | 0 | 0 |
| probe (0261's own cost) | 28.5 ms | 10.0 ms | |

The reconcile minute (03:07, before 0265): p95 3,986 → 4,388 ms, 40 → 17 runs a minute. That is the compactor's 5 s
holds (0260), not the beat's work; 0265 replaced that schedule.

Per unit of work (0262 profiles), before → after (clean window) → after + 0265:
- a lap start's re-plan (`npc_plan`): 617 → 585 → 444 ms a call;
- `npc_loop_candidates`: 246 → 113 → 128 ms a call (−50 %);
- `cmd.standing_route_close_lap`: 129 → 139 → 138 ms (untouched by 0264);
- the knob wrappers are gone from the profile (inlined); a knob read ~46 → ~24 µs.

## Conclusion

- **Root cause:** the beat's slow seconds are a merchant's lap turnover inside the beat: closing her lap (~130 ms) and
  re-planning the next one on today's prices (`npc_plan`, ~450-600 ms: ~11 legs through `world.trade_routes`, ~150
  quotes, ~2,200 knob reads, and on most lap starts up to 16 candidate loops). The beats over 1 s are the beats with
  one or more lap starts. The local profiles behind 0250 / 0256 never ran this path.
- **Not the cause:** the ledger backlog. The purse checks run at the commit, outside `ms`, ~30 ms a beat. The backlog
  is also not draining by itself (784 of 821 houses unrolled at 02:10, median 1,202 ledger rows a house and rising),
  so "wait for the drain" is not a plan for it either; 0265 is the compactor agent's answer.
- **What same-answer changes can still do:** shave the pricing (e.g. `world.mid_terms` reads four knobs a call, ~280
  calls a plan). Each is a few percent. The p95 goal (< 1 s) cannot be reached that way while each lap start is
  priced whole inside a one-second beat.
- **What would cut it at the root (changes game results: OWNER's call, not built):**
  1. re-plan only on review laps (`npc_route_review_laps`, 6) or when her loop stops paying, and sail the standing
     lines otherwise (most lap starts would cost ~0.1 s instead of ~0.5 s);
  2. move the re-plan out of the beat: a merchant whose rest ends is queued and re-planned by a separate job (or the
     asking slot), and sails a beat or a few seconds later;
  3. cap the candidate loops priced per lap start (`npc_route_candidates`, now 16).
