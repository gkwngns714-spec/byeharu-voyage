# 2026-10-28: the lap-start lag spike at :07, and the compactor backlog (prod, read-only, head 0267, measured 12:09-12:20 UTC)

Read-only: SELECTs on receipts (`lap_start_runs`, `reconcile_runs`, `compact_runs`, `arrivals_beats`), `standing_route_laps`, `cron.job_run_details`, `pg_stat_*`. No function was called.

## 1. The compactor backlog: NOT drained

| at (UTC) | merchant ledger rows waiting past the 6 h cut | oldest unrolled row |
|---|---|---|
| 05:14 | 779,837 | 10-26 05:32 |
| **12:12** | **266,564** | **10-27 12:38** |

- All 814 due houses are still due every minute (every house has rows more than 1 h past the cut).
- Rows crossing the cut: 20,652 in the last hour. Rows written: 20,711.
- **What `compact_runs` removed, per hour:**

| hour | runs | ledger rolled | events | houses | failed | notes | skipped | longest batch |
|---|---|---|---|---|---|---|---|---|
| 05 | 60 | 103,147 | 124,209 | 672 | 0 | 0 | 0 | 7.5 s |
| 06 | 60 | 107,674 | 124,023 | 680 | 0 | 0 | 0 | 2.1 s |
| 07 | 59 | 109,078 | 127,004 | 723 | 0 | 0 | 0 | 4.0 s |
| 08 | 60 | 124,541 | 144,577 | 779 | 0 | 0 | 1 | 1.9 s |
| 09 | 60 | 135,336 | 158,169 | 852 | 0 | 0 | 1 | 9.2 s |
| 10 | 60 | **61,433** | 72,350 | 347 | 0 | 0 | 1 | 15.6 s |
| 11 | 60 | **30,126** | 35,053 | 200 | 0 | 0 | 2 | **40.2 s** (25 houses, 11:16) |
| 12:00-12:10 | 11 | 11,146 | 12,944 | 83 | 0 | 0 | 0 | 6.7 s |

- **0 failures and 0 notes in any run.** `pg_stat_database.deadlocks` is still 126, the same as 04:13.
- **The drain stalled from ~10:20 to ~12:05.** A house's hold (`ms_house`) went from ~0.4-0.7 s to 3-15 s. The rows rolled per house did not change (~150), so the extra time is not the work. See §3.
- From 12:06 it is back to ~0.6 s a house and 12-14 houses a minute (~1.3-1.9 k rows a minute).
- **ETA, if the healthy pace holds:** ~780 house-visits an hour at ~150 rows each is ~110 k rolled an hour, against ~20.6 k crossing the cut. That is ~90 k net an hour, so 266 k takes ~3 h: **~15:00-16:00 UTC 10-28**.
- Cross-check: every house sits at 10-27 ~12:30, and the cut is 10-28 06:12. That is ~18 h, three 6 h visits a house. At ~one visit per house an hour, plus the cut moving 1 h an hour, it is ~3.5 h.
- Another stall like 10:20-12:05 pushes the ETA back by its own length: at 30 k/h the net drain is only ~10 k/h.

## 2. The lap-start lag spike at :07

### Per hour (lag = lap start - (previous lap's close + 120 s rest); this formula matches `lap_start_runs.receipt.lags` exactly at 08:07)

| :07 | stats job (prev :06 run) ended | tend phase (held / longest hold / waited) | laps started; lag p95 / max (receipt) | laps started :00-:20: p95 / service gap a lap | late (full 1.5 s gap waits) | wait / open a lap | open max |
|---|---|---|---|---|---|---|---|
| 08:07 (ref) | 08:07:29 | 31.7 s (13.4 s / 1.17 s / 18.2 s) | 30; 13.9 / 14.6 s | 14.2 s / 2.04 s | 4 | 412 / 199 ms | 1.30 s |
| 09:07 | 09:07:11 | 25.6 s (8.3 s / 1.01 s / 17.2 s) | 29; 14.6 / 16.4 s | 10.3 s / 2.81 s | 7 | 548 / 361 ms | 2.71 s |
| 10:07 | **10:06:54 (no overlap)** | **12.2 s** (6.7 s / 0.93 s / 5.4 s) | 19; **3.4 / 3.5 s** | 3.5 s / 2.96 s | 1 | 231 / 166 ms | 0.44 s |
| 11:07 | 11:08:00 **failed (statement timeout)** | **99.4 s** (16.3 s / 2.59 s / 83.1 s) | 7; 124.9 / 126.9 s, 56 left | (inside the 10:16-12:05 stall, §3) | 7 | | 8.2 s |
| 12:07 | 12:07:35 | 26.8 s (10.4 s / 1.39 s / 16.4 s) | 24; 6.2 / 7.3 s | 5.8 s / 3.18 s | 7 | 710 / 354 ms | 1.70 s |

**The :07 minute against the other minutes.** Clean windows: 08:00-10:15 and 12:06-12:10, 143 minutes.

| minute class | late a minute | plan a lap (outside the quay) | gap wait a lap | open a lap (under the quay) | open max (mean) |
|---|---|---|---|---|---|
| :07 (n=4) | **4.75** | 545 ms | **487 ms** | **275 ms** | **1,537 ms** |
| stats tail :22/:37/:52 (n=6) | 1.00 | 548 ms | 248 ms | 168 ms | 651 ms |
| stats start :06/:21/:36/:51 (n=10) | 0.60 | 541 ms | 243 ms | 163 ms | 428 ms |
| other (n=129) | 0.36 | 491 ms | 199 ms | 149 ms | 429 ms |

**Other minutes also lag early.** The p95 of laps started in :00-:20: median 3.7 s, p90 6.9 s, max 10.3 s.
- Laps due in :57-:00 wait for the next minute's session (`c_end` 57 s). The first lap of a minute starts at median 1.6 s.
- Laps due in the first ~20 s: :07 7-15, other minutes median 10, p90 14. **:07 does not have more laps due; it serves them slower.**

### Second by second, 12:07 (the only :07 still in the `arrivals_beats` ring; its 3,600 slots are one hour)

- Beats before 12:07:00: `q` (quay wait) = 0.0 ms.
- **12:07:00-:13: beats waited for the quay**: 63, 11, 18, 37, 9, **1,391** (:05), **969** (:06), 8, **1,072** (:08), 291, 11, 448 (:12), 235 ms. The tend phase's longest hold that hour was **1,393.8 ms**, which matches the 1,391 ms wait.
- From :14 the beat's `q` is ≤ 40 ms, except 145 ms at :31, when the companies step started.
- **Lap starts:** from 12:07:02 to :34, one every ~2-3 s (lags 2.2-7.3 s). **From :35 they come every 0.4-1 s** (lags 0.2-1.6 s). The stats job ended at 12:07:35.1. The tend phase ran ~:00-:27, and the companies phase ~:27-:42 (holds ≤ 81 ms).

### What is proven, and what is not

**Proven (numbers above):**
1. The excess at :07 is in the **quay-gated half of a lap start**:
   - the open step: 275 vs 149 ms a lap, max 1.5 vs 0.43 s;
   - its gap wait: 487 vs 199 ms; `late` 4.75 vs 0.36 a minute. The gap wait times out when the second's beat commits late, and a beat is late when it waits for the quay.
   - The plan step, outside the quay, is the same in every minute class (545 vs 491 ms). So it is not machine-wide contention.
2. **The only extra quay holder in :07:00-:3x is the tend phase**: 836-837 transactions, 6.7-13.4 s of hold, longest 0.93-1.39 s. The beat's quay waits at 12:07 line up with it (1,391 ms against the 1,394 ms longest hold). The companies phase after it holds ≤ 81 ms a transaction.
3. **NOT the compactor's :07 sweep.** It is off the quay (0265). It takes houses with SKIP LOCKED, and `busy` = 0 in every lap-start run. Its sweep ends by :08-:11.
4. **NOT the stats job directly.** In the stats-tail minutes (:22/:37/:52, no tend, no sweep) the open and wait steps are near normal (168 / 248 ms, late 1.0). The 09:22 early p95 of 12.8 s was carried from :21: it started only 7 laps, its service gap was 1.51 s, and its first lap came at 4.2 s.

**Not proven:**
- **Why the tend phase is 2-2.6× longer when the :06 stats run spills into :07.** It ran 25.6-31.7 s with spill-over (08, 09, 12) and 12.2 s without (10). That is 4 samples, a correlation, not a mechanism. The tend phase's own quay **waits** are what grew (16-18 s vs 5.4 s): tend waits behind beats and opens that run slower.
- **Which tend steps hold ~1 s, and doing what.** `reconcile_runs.receipt.quay.tend` keeps only n / held / longest / waited, with no merchant, no time and no act.

**Root cause (as far as the data goes):** the tend phase of the hourly reconcile. It holds the quay in 836 transactions over the first 12-32 s of :07, some of them ~1-1.4 s long. Each long hold makes the second's beat late. The lap-start open step then waits its full 1.5 s for a gap and queues for the quay. Laps due in that window are served one every 2-3 s instead of ~1.8 s, and the serial queue backs up.

**Fix target: the longest tend-step holds.** But which steps they are is not measured, so no trim is proposed.

### The measurement slice this needs (record only, no behaviour change)

1. **Tend, per step**, kept in the reconcile receipt for steps holding > 100 ms:
   - merchant id;
   - `clock_timestamp()` at the quay request, the grant and the commit;
   - what the step did (sail / tow / lay-up / invest / donate / nothing).
2. **Lap starts, per lap**, in `lap_start_runs.receipt.steps`:
   - fleet, due-at;
   - plan t0 / ms;
   - gap-wait t0 / ms / late;
   - open t0, the open's own quay wait (`clock_timestamp()` around `hold_the_quay()`), open ms.
3. **The :06:30-:08:00 beats kept past the hour:** copy them out of the ring at :09, or widen the ring for :07. Right now only the latest hour's :07 survives.
4. **The stats job's phase times** (`tick_stats` returns them to the cron log as "1 row", so they are not kept). With those, tend's longer phase could be tied to a stats phase, or ruled out.

## 3. Separate incident, 10:16-12:05 UTC: everything ran 3-10× slower (cause NOT on record)

- **Lap-start lag up to 244 s** (p95 > 100 s in most minutes; 56 due left at 11:07).
- **The stats job hit the 120 s statement timeout 7 runs in a row** (10:21 … 11:51; 11:06 failed). Before: 43-101 s. 12:06: 95 s.
- **Compactor:** 3-15 s a house (one batch of 25 held 40.2 s at 11:16), against 0.4-0.7 s.
- **drift:** 23-52 s (3-16 s before). **price-snapshot:** 11-46 s (3-5 s before). **11:07 reconcile:** 110 s, tend 99.4 s (83 s of it waiting).
- Everything recovered ~12:05-12:10: drift 3.8 s and price-snapshot 3.1 s at 12:10, compactor ~0.6 s a house.
- **No deploy:** head 0267 throughout, no cron failure except the stats timeouts, no deadlock (126 unchanged).
- The large `do $$` entries in `pg_stat_statements` are earlier migrations' self-asserts (0257/0258/0260/0265), not this window.
- **Missing:** `track_io_timing` is off. `pg_stat_statements` is cumulative since 10-20 (no time slice). There is no `pg_stat_activity` history. So the cause (disk IO budget, an external client, an autovacuum) cannot be named from SQL. The Supabase dashboard's Disk IO / CPU graphs for 10:15-12:10 UTC are the next reading.
