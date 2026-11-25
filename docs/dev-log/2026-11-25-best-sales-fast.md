# 2026-11-25: `best-sales-fast`: 0536 (PLACEHOLDER number; a repair, nothing dark), stacked on batch 2

Asked: world.best_sales at least FOUR times faster, byte-identical. **Delivered: 1.25 to 1.4 times. Four times is not reached.**

## Where it went (Lisbon, local PGlite 18.3, the full 159,766-row market, prod's 16 switches + sea_conditions_bite lit; 322 ms tracked, 18,200 calls)

| Part | Before | After |
|---|---|---|
| `voyage.reach_passage` (once; 64,516 pairs asked of the seas and sorted) | 62 | 30 |
| the walks (`world.board_trips` x 11, 200 legs) | 66 | 17 |
| unpacking 254 legs of 19 columns for every good (`board_sell_memo` self) | 46 | 37 |
| 186 quotes (`quote_priced`) | 63 | 60 |
| a harbour's spread, fee and tax terms (89 / 60 / 48 harbours) | 30 | 30 |
| her buy capacity x 10, half-coin and top-up quotes | 45 | 45 |

About 37 ms of what is left is `power()` (4,500 price steps at 8 us in WASM; native is much cheaper, so prod's share of it is smaller).

## Before and after, 254 harbours each, every answer the same text (0 of 1,270 differ)

| World | Mean | Worst |
|---|---|---|
| lit, 200,000 coin, first hull | 195 -> 140 | 333 -> 245 |
| lit, 3,000,000, the largest hull | 280 -> 224 | 628 -> 548 |
| lit, 5,000, two hulls | 201 -> 142 | 353 -> 246 |
| lit, 3,000,000, two hulls, cargo aboard | 291 -> 231 | 670 -> 584 |
| dark, cargo aboard | 162 -> 121 | 341 -> 223 |

(The largest-hull worlds are quotes' price steps, which 0536 does not touch.)

## Why not four times

- What is left is many small reads, none above 20 %. With the pathfinder and walks free it would still be 160 ms of 300.
- PRUNING BY AN UPPER BOUND was worked out and dropped. Of 120-150 priced rows 36-56 could matter at the served spread (50 %); a bound loose enough to
  be proved by the mid keeps 91-139. A tight one must bound the price inside `quote_priced`, and 0517 (premium goods) adds a price above the mid there:
  the proof would stop holding when 0517 lands. It also cannot skip the want read, which every marked row asks.
- `quote_priced`, `mid_terms`, `tax_rate` and `spread_pair_from` are cut by 0505, 0506, 0507, 0517: re-cutting them here would break those hunks.

## Proposed, not built

- A KEPT ANSWER, for Assign, Trade and HQ asking the same thing within a drift slot: one row a player fleet (tens of rows; one upsert a miss), keyed by
  harbour, purse, fleet version and the served `clock.next_change_at`. It does not help the job tick (a plan each 16 minutes is a miss).
- `good_board_quoted` 10 / `_near` 5 are owner's knobs: fewer rows is the only large cut left, and it changes answers.

## Conflicts with 0503-0535 (text, batches as pushed)

- `voyage.reach_passage`: 0510 (6 hunks) and 0513 (4) cut the sea part; their OLD texts all still stand once in this body.
- `world.board_sell_memo`: 0517 hunk 16 (the `rk` line) still stands once. `world.best_sales`, `board_trips`, `trip_leg`, `stores_*`, `ship_speed_of`: none.
- NOT RUN: those batches on top of this file. Anything that pins a digest of these bodies (batch checks) must be regenerated.

## Prod files (not run)

`scripts/ops/harness/best-sales-fast/plans.sql` (statistics, indexes, settings, catalog only) and `explain.sql` (EXPLAIN without ANALYZE).

## Checks

0536's self-assert: 14 of 15 perturbed worlds (the other is the known founding refusal). The 254-harbour sweeps ran the same bodies by hand on 0503's
chain, before batch 2 was merged in. Proofs 07, 101, 105, 113, 134, 157, 162, 165, 175, 177, 178, 182-188, 194, 200, 62, 241 green. 190 and 191 pinned the
text of `stores_need_days`, `best_sales` and `board_sell_memo`: each puts that text back first (amended here). Not run: `vite build`, the browser specs, PostgreSQL 17.

## Is it PostgreSQL 17? (measured 2026-11-25)

The chain's world (0503's, every row and body) carried into PGlite 0.3.15 (PostgreSQL 17.5) beside PGlite 0.5.5 (18.3), prod's switches lit, warm:
Lisbon 316 ms on 18, 358 on 17; Colombo 225 / 263; Guayaquil 320 / 347. So the version is about 8 to 15 %, not 2.4 s. With 0536: 18 -> 233 / 170 / 240,
17 -> 268 / 197 / 264. Seventeen SQL readers made plpgsql as well, on 17: 244 / 177 / 247 (about 8 % more; not in 0536).
`force_custom_plan` on reach_passage: 0206, a pooled session's generic plan of 0205's matrix build took 8,101 ms against 268; left as it is.

`stages.sql`, Lisbon, old bodies, ms (18.3 / 17.5): cpu_float 400,000: 74 / 77; cpu_numeric 100,000: 19 / 28; cpu_power 4,500: 33 / 37; 3,000 calls: 18 / 18;
2,540 port rows: 4 / 3. whole 310 then 304 / 346 then 336; the stages' sum 296 / 332 (within 3 %): origin 66 / 83, sells 192 / 199, capacity 14 / 20, legs 12 / 14,
half 6, amounts 3 / 4, hulls 1 / 4, offered 2. In five goods' sells: 72 quotes 31 / 37, trips 31 / 34, dock 6 / 5, tax 6 / 3, mids 5, quay 3.
