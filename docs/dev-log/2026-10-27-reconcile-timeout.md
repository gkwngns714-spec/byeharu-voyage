# 2026-10-27: the hourly reconcile hit its 120 s timeout (`osn-reconcile-timeout`, migration 0249)

## The finding (prod, read-only, head 0248)

`byeharu-voyage:reconcile` (jobid 3, `call public.tick_reconcile()`, hourly at :07), `cron.job_run_details`:

| window (UTC) | run time |
|---|---|
| 10-25 05:07 → 10-25 23:07 | 10-19 s |
| 10-26 00:07 → 12:07 | 16 → 24 → 30 → … → 50 s, rising every hour |
| 10-26 19:07 → 23:07 | 67-115 s |
| 10-27 00:07 → 12:07 | **10 of 13 runs hit the 120 s statement timeout** (most in `npc_compact`'s events delete; also its ledger roll, the events FK check, the append-only trigger, and once the final invariants pass) |

**The compactor had committed nothing since the 10-25 23:07 run.**
- The oldest merchant event waiting to be compacted was from 10-25 17:07:00.98. That is the 23:07 run's cut (now minus `npc_retention_hours` = 6). The newest `NPC_CARRIED` ledger row was from 10-25 17:06:46.
- After that, every run rolled the compactor back. The whole world was one statement block under `exception when others`. Before 10-27 its error was caught and lost: the run's receipt is only a NOTICE, and nobody keeps it. From 10-27 00:07 the error was the 120 s timeout on the whole CALL, which no handler catches.
- Each failed run left one more hour of rows for the next run, so the compactor never caught up. The run time climbs by about 4.5 s for each hour of backlog.

What was waiting, at about 12:30 UTC on 10-27:

| table | rows waiting (merchants', older than the cut) | a clean hour |
|---|---|---|
| events | 943,287 (624,459 of them still named by a ledger row) | ~25 k |
| ledger | 741,544 (the largest house: 2,535) | ~21 k |
| voyages (ended) | 186,759, plus ~7 voyage_events each and one insurance row each | ~5 k |
| trade_daily (past game-days) | 122,486 | — |

The indexes were not the problem. `events (player_id, created_at desc)`, `ledger (ref_event_id)` (partial, used by the FK check) and `ledger (player_id, created_at desc)` all exist. The problem was the backlog: one transaction for the whole world cannot clear 43 hours of rows in what is left of 120 s.

**Why the first failure (10-26 00:07) happened is not on record.** The error was swallowed, notices are not logged, and `pg_stat_statements` only tracks top-level statements. The likely cause is a lock wait longer than the step's 2 s `lock_timeout`. Inserting the `NPC_CARRIED` row takes a KEY SHARE lock on the house's `players` row, and that waits behind an arrivals run that has the row FOR UPDATE (`public.credit`). This fits the timing: 0220 made ships three times faster at 16:45 UTC on 10-25, and 0225 (provisioning on every SAIL) went in at about 23:45, so arrivals runs got busier. It is inferred, not proven.

**The deadlock, 10-27 04:07:23:** the arrivals run was updating a fleet's ships, which takes an FK KEY SHARE lock on her `players` row. The reconcile held that row FOR UPDATE (`credit`, in an upkeep step) and was itself waiting on a row the arrivals run had written. The arrivals run was the victim and lost that second.

## The fix (0249)

1. **The same rules, one house at a time.** `public.npc_compact_house(house, now)` is npc_compact's per-house work, moved over unchanged: her ended voyages, her past trade_daily days, her ledger rolled into one `NPC_CARRIED` row (the balance is computed, then checked), and her events. `public.npc_compact_orders(now)` is its orders delete, unchanged. `public.npc_compact(now)` keeps its signature, gate and answer, and is now those two pieces run in order. A new partial index, `voyages (fleet_id, eta) where status <> 'SAILING'`, finds one house's ended voyages.
2. **The hour compacts house by house, one transaction each, with its own 30 s budget.** The house compacted longest ago goes first (her oldest ledger row is her `NPC_CARRIED` row at her last cut). The houses not reached are first in line the next hour. A house that fails is rolled back on its own and counted.
3. **No upkeep step runs beside an arrivals beat.** `public.hold_the_quay()` takes one transaction-level advisory lock. Every arrivals beat takes it right before `public.tick_arrivals()`. Every write step of the hour takes it first and holds it until it commits: each merchant, the companies, the orders, and each house. So a beat and an upkeep step never hold row locks at the same time. They cannot deadlock, and the compactor never waits on a beat's rows. A beat waits for at most one step, and a step waits for at most one beat. The beat's `now()` is still its own second, because the lock is taken inside the beat's transaction.
4. **`public.reconcile_runs`** keeps one row per run for 7 days: the receipt that used to be only a NOTICE, plus each phase's ms (`tend`, `companies`, `compact`, `check`). The next failure can be read instead of guessed.

Unchanged: which rows are deleted, what the carried row says, what a merchant's upkeep decides, and what an arrival does. `public.tick_arrivals` is checked byte for byte. No knob, flag, schedule or grant moves.

Rollback: a forward slice reverses the 8 hunks. Every OLD text is in the file. The new functions, the index and the table are additive and harmless if left in place.

## Self-assert (0249)

- All 8 hunks (npc_compact 2, tick_reconcile 5, tick_arrivals_each_second 1) reverse to the live pre-image. ACL, volatility, definer and config are unchanged, and `tick_arrivals` is byte-identical.
- tick_reconcile takes the quay lock exactly 4 times and no longer calls `npc_compact(`. No other function takes the lock. None of the new pieces are reachable by a client.
- **Probe (rolled back):** one merchant house with rows from before a cut at 2026-08-01. That cut is earlier than every real row on prod (the first real ones are from 2026-08-22), so only the probe's rows are touched. Three runs start from the same state: the 0248 compactor (kept in pg_temp), the new `npc_compact`, and the hour's pieces (`npc_compact_orders` + `npc_compact_house`). They must leave identical rows (digests of ledger, events, voyages, voyage_events, orders and trade_daily) and identical counts. What went must also be exactly what the rules say: 1 voyage and its day row, 2 events (one freed by its ledger row being rolled), 3 ledger rows into 1 carried row, 1 order, 1 trade_daily day. The FOUNDED event, the event named by a kept ledger row, and the newer rows stay. The purse still reconciles.

## Measurements

Local (PGlite, cached prefix p0237 + 0249):
- 0249 self-assert ok. The three ways left identical rows and counts `{events 2, orders 1, voyages 1, trade_daily 1, ledger_rolled 3}`: old 29 ms, new whole-world 119 ms, the hour's pieces 4 ms.

Prod before: see the finding above.

Prod after: below.
