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
- The real job on a merchant world. Steps: merchants lit (837 fleets), three arrivals runs, `npc_retention_hours` set to 0 locally so every row is past the cut, then `call public.tick_reconcile()` with commits.
  - Run 1: 16.6 s (tend 460 ms, companies 16 ms, compact 16.1 s, check 18 ms). All 821 houses were done, none left, none failed: 5,310 ledger rows rolled, 3,433 events, 11 orders. The receipt row was written.
  - Run 2, with nothing left to compact: 14.8 s, which is ~18 ms per house on wasm.
  - Then `call public.tick_arrivals_each_second(2)`: both beats ran, no error.

Prod before: see the finding above.

Prod after: below.

## Prod after 0249, and why 0253 followed

Deployed 2026-10-27 13:4x UTC: PR #362, merge `fb46b93`, main Acceptance green. Prod head 0249. Beats ran right after it: 169 in 3 minutes, 0 errors, p50 370 ms.

**14:07 run: succeeded in 75.4 s** (11 of the 14 runs before it hit the 120 s timeout). Its receipt (`public.reconcile_runs`): tend 33.1 s, companies 4.3 s, compact 34.5 s, check 3.3 s, 0 failed. But the compactor finished only **12 of 821 houses** (3,141 ledger rows, 3,349 events, 589 voyages, 818 trade_daily rows, 200 orders; 809 left).
- That is about 2.9 s a house. One house's 10-25 / 10-26 rows lie roughly one to a page across a day and a half, long out of the cache (shared_buffers 320 MB; events alone is 512 MB). So a house step read a page from disk for each row.
- At that rate the backlog would have taken days. The beats waited on those slow steps: in 14:07-14:08 they averaged 1.2-1.5 s (max 8.7 s), against 0.5 s at 14:05.

## The fix, part 2 (0253)

tick_reconcile's compact step now walks the backlog **by time**. Three hunks:
- A slice means "compact every house as of instant T", using `public.npc_compact_house(house, T)`: the same function and the same rules. T is six hours past the last slice finished, and never later than now.
- All the houses in one slice read the same few hours of rows. Those rows sit together on disk and stay in the cache.
- A finished slice is recorded in the run's receipt (`upto`). A slice that the 30 s budget cut short is done again the next hour; the houses it already reached have nothing left in it. The first run starts at the cut of the oldest merchant ledger row still waiting to be rolled.
- Compacting as of T and then as of a later T' leaves exactly what compacting once as of T' leaves. The carried row's sum, last instant and balance are all computed from the rows, and every delete is "older than the cut".

Self-assert (0253): the hunks reverse to the live pre-image. `npc_compact_house`, `npc_compact`, the beat and `tick_arrivals` are unchanged (md5). On a probe house (rolled back), compacting as of 10:30 and then 18:00 left byte-identical rows to compacting once as of 18:00, and to `npc_compact`. The first slice rolled 2 rows, the second 3; done once, 4.

The migration was deployed as **0253**. 0250 (arrivals trim, #363), 0251 (near-city board, #359) and 0252 (E5b, #358) landed first, and none of them touches `tick_reconcile`. The live body was still md5 `ed8cad1b` at head 0252, and all 3 hunks were re-checked against it. One more change went in after the first local run: within a slice, the house with the oldest row waiting to be rolled goes first, so a slice the budget cuts short does not starve the same houses every hour.

Deployed 2026-10-27 ~15:48 UTC: PR #364, merge `01c1c92`, main Acceptance green. Prod head 0253. Beats ran right after: 45 in 2 minutes, 0 errors.

## After-check (prod, the two hourly runs after 0253)

| run (UTC) | status | total | tend | companies | compact | check | houses done / left | rows compacted |
|---|---|---|---|---|---|---|---|---|
| 10-27 13:07 (0248) | failed | 120.0 s (timeout) | | | | | 0 | 0 |
| 10-27 14:07 (0249) | succeeded | 75.4 s | 33.1 s | 4.3 s | 34.5 s | 3.3 s | 12 / 809 | 3,141 ledger, 3,349 events, 589 voyages |
| 10-27 15:07 (0249) | succeeded | 62.9 s | 22.2 s | 5.3 s | 31.7 s | 3.6 s | 14 / 807 | 4,036 ledger, 4,730 events, 898 voyages |
| **10-27 16:07 (0253)** | **succeeded** | **57.3 s** | 18.9 s | 4.4 s | 30.8 s | 3.2 s | 12 / 809 | 1,506 ledger, 2,531 events, 524 voyages |
| **10-27 17:07 (0253)** | **succeeded** | **58.8 s** | 20.7 s | 4.6 s | 30.0 s | 3.4 s | 34 / 787 | 5,215 ledger, 7,717 events, 1,511 voyages |

- Every run since 0249 has succeeded, at about half the 120 s timeout. No tend step failed or was busy.
- No arrivals beat failed and there was no deadlock. Beats are late while the hour runs: the companies step (~4.5 s) holds the quay lock, and each compaction step holds it for ~1-2 s, so in that window a beat takes 1-5 s. They catch up within the minute.

**What is still open: the compactor does not keep up.** Neither 0249 nor 0253 got past ~12-34 houses in 30 s, so the slice never finished (`upto` is still null) and the backlog is still about 1.01 M merchant events.

IO counters (`pg_statio_user_tables`) sampled at 16:11, 17:06:45 and 17:08:08 show why:
- During the 17:07 run the **ledger** read 25.8 k heap blocks and 16.5 k index blocks from disk. Events read 7 k + 7 k, port_goods 12 k.
- Even with nothing running, the ledger reads **~1,700 heap + ~1,500 index blocks a minute**.

The cause is `public.assert_ledger_reconciles`, which runs `ledger_sum(player)` over the house's **whole** ledger. It runs after every merchant ledger insert (the deferred `ledger_reconciles` trigger, so every `credit` in every beat), in every compaction step, and in the check pass. With ~900 uncompacted rows per house spread over ~900 pages that are not in the cache, each of those calls is about a thousand random disk reads.
- So the backlog makes each house's compaction step slow (~1-2 s, almost all of it that sum), and that keeps the backlog in place.
- It also very likely explains much of the arrivals' per-fleet cost that 0248's dev-log left open (~45 ms a fleet).

**Next slice (proposed, not built):** a set-based form of the same rules for a batch of houses, `npc_compact_houses(houses[], now)`, with `npc_compact_house` becoming the batch of one, so there is still one authority.
- One batch of ~100 houses per transaction, under the quay lock, at the normal cut.
- Its ledger and events reads become bitmap scans that read each page once, in block order, instead of one random read per row.
- Rolling a house's ledger once shrinks her `ledger_sum` to a handful of rows for good. That is what makes the hourly compaction, the beats' `credit` and the check pass cheap again.

## The fix, part 3 (0257): a hundred houses a transaction

`public.npc_compact_houses(houses[], now)` holds the compaction rules, set-based. Same four steps, same order, same keeps and deletes: ended voyages, past trade_daily days, the ledger before the cut rolled into one `NPC_CARRIED` row (balance computed from the purse, then asserted), events. Each step is one statement for the whole batch. `player_id = any(batch)` on the `(player_id, created_at)` indexes is a bitmap scan (prod plan checked with plain EXPLAIN), so each page is read once, in block order, for every house in the batch.
- `npc_compact_house(house, now)` is now the batch of one (1 hunk). One authority. `npc_compact` is unchanged and runs through it.
- tick_reconcile (3 hunks) keeps 0253's slices and house order, but takes the houses 100 to a transaction: `hold_the_quay()`, the upkeep scope, the batch, commit. A batch that fails is rolled back whole, and then its houses are done one at a time (the 0249 step), so a bad house holds back only herself. The 30 s budget is checked before every transaction. The receipt adds `batches`.
- Batch = house by house, because the houses' rows are disjoint. The one way it could differ is a ledger row of house B naming an event of house A. Prod, read-only, 10-27 17:13: 0 of 811,251 named events cross houses.

**ledger_sum is not changed (decided by default).** It is THE statement of the purse invariant (0004). Once a house is rolled, it sums her one carried row plus the last ~6-7 hours of rows (~26 a house-hour, so ~150-180 rows), all recently written and in the cache. Players' ledgers are small (19 houses, p50 2 rows, max 206). A running total would be a second authority for the purse. The drain is the fix for the sum's cost.

Self-assert (0257): the 4 hunks reverse to the live pre-image; ACL, volatility, definer, config unchanged; `npc_compact`, `npc_compact_orders`, `ledger_sum`, `assert_ledger_reconciles`, `credit`, the beat and `tick_arrivals` unchanged (md5); no other function takes the quay lock. Probe (rolled back): 3 merchant houses (two with rows to roll, one with a single old row) and 1 player house, rows before a 2026-08-01 cut. The 0249 house step one house at a time, the batch, the new house step, and `npc_compact` left byte-identical rows and identical answers. The player's rows were untouched.

Local (PGlite, cached prefix p0242 → 0257): 0257 self-assert ok, answer `{events 6, voyages 6, trade_daily 6, ledger_rolled 8}` the same all four ways. The real job on the seeded merchant world (821 houses, merchants lit, `npc_retention_hours` 0 locally, `call public.tick_reconcile(true)`): compact **375 ms** for 3 slices × 9 batches (27 batches, 0 failed, 3,492 ledger rows rolled, 821 carried rows after). 0249's house-a-transaction step took 16.1 s for one pass on a similar world. `call public.tick_arrivals_each_second(2)` afterwards: no error.

## After-check (prod, the two hourly runs after 0257)

Deployed 2026-10-27 ~17:37 UTC: PR #367, merge 4665f63, prod head 0257 (after 0256, #366). Main Acceptance went red once on `tests/city.goodTrades.spec.ts:78` (the wide-glass step of a player's own Bought row). That spec cannot reach the compactor: nothing in `src/` calls `tick_reconcile` or `npc_compact*`, and a player's rows are never compacted. Re-running the failed shard once, as a diagnostic, passed. Recorded as a first-seen flake.

| run (UTC) | total | tend | companies | compact | check | houses / batches / left | rolled |
|---|---|---|---|---|---|---|---|
| 10-27 17:07 (0253) | 58.7 s | 20.7 s | 4.6 s | 30.0 s | 3.4 s | 34 / — / 787 | 5,215 ledger, 7,717 events, 1,511 voyages |
| **10-27 18:07 (0257)** | **68.1 s** | 16.5 s | 5.0 s | **42.1 s** | 4.5 s | **200 / 2 / 621**, 0 failed | **30,357 ledger, 47,292 events, 9,568 voyages**, 6,421 trade_daily |
| **10-27 19:07 (0257)** | **79.8 s** | 26.4 s | 5.8 s | **43.5 s** | 4.2 s | **200 / 2 / 621**, 0 failed | **26,230 ledger, 40,966 events, 8,339 voyages**, 5,495 trade_daily |

Backlog (merchant rows older than the 6 h cut; events not of a kept kind):

| at (UTC) | ledger waiting | events waiting |
|---|---|---|
| 17:23 (before) | 820,179 | 1,036,817 |
| 18:08 | 806,334 | 1,008,539 |
| 19:09 | 801,723 | 992,631 |

Arrivals beats (`public.arrivals_beats`): **0 errors** before, during or after.
- Outside the hourly run, the beats are the same: p50 365 → 343 → 352 ms, p95 1,712 → 1,652 → 1,589 ms (17:00-17:37, 17:37-18:07, and later).
- During the run (xx:07-xx:10) they wait longer: p95 9.0 s at 18:07 and 14.6 s at 19:07, max 27.0 s and 26.0 s. Under 0253 the worst was ~11 s. The cause: each batch of 100 holds the quay lock for ~20 s, so a beat waits that long once or twice.
- `ledger_sum` per house (p50 rows) is still 1,102. It falls only as houses are rolled at the normal cut.

**What this means.** 0257 compacts ~6x more rows per run than 0253 (26-30 k ledger rows, 41-47 k events), with no failures. But the 6 h slice keeps each house's ledger long, so every batch still sums ~1,100 cold rows per house, twice (the explicit check and the deferred trigger). It also reads her voyages and their voyage_events one row at a time (fleet by fleet, then per voyage in the cascade). So each batch is ~20 s. Net drain is ~10 k ledger rows and ~20-28 k events an hour, against 800 k and 990 k waiting.
- **Estimate: the ledger backlog empties in ~3-4 days (around 10-31), events about the same.** That holds only if the merchants' write rate stays where it is.
- The first 6 h slice finishes in about 2 more runs (621 houses left, ~200 a run).

**Proposed next (0258, not built):**
1. A smaller batch (~25 houses), so a batch holds the quay lock for ~5 s, not ~20 s.
2. Compact each batch at the normal cut, not the 6 h slice. Each house is then rolled once for good, and her checks sum ~150 hot rows instead of ~1,100 cold ones.
3. Read voyages by `fleet_id = any(...)`, and delete their voyage_events and insurance rows set-based before the voyages, so those pages are also read once, in block order. This leaves the same end rows as the cascade.
