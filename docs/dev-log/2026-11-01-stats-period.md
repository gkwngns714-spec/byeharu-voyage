# 2026-11-01 — 0299: the count's `period` is read over the count's real window

**Branch** `stats-period` · migration `supabase/migrations/20260818000299_the_period_is_the_whole_window.sql` · deploys AFTER 0298 (0297 quiet-disk and 0298
the hourly upkeep go first; prod head `20260818000294`, 282 migrations, read 2026-11-01 19:26 UTC). Found while measuring the Stats slice of owner rows 256 / 259
(`docs/OWNER_REQUESTS.md`); not a new instruction. The owner's limit on that slice stands — *"DO NOT CHANGE ANYTHING REGARDING TIME - THE SECONDLY DATA
RENEWAL STAYS IN STATS"* — and nothing about time moves: no cron job or schedule, no knob, no switch, no client read, no other line of `tick_stats`.

**History of the number.** First written as "0292 / after 0290-0291"; cut as **0295** and pushed to prod once (2026-11-01 19:20 UTC) — it **failed its own self-assert and
kept nothing** (§1); renumbered 0298, then **0299** because the reconcile fix took 0298 (`db push` refuses a file numbered below the prod head).

## 1. The first push to prod (as 0295) failed — what, why, and what changed

The self-assert died on its first comparison, R1: *"the 15-day window is not its 18 days summed over both halves"*, with a 34 KB message. `stats_recent` at the probe's 2004
instant returned the probe's 18 days **and prod's real days** (game days 29,892,607 … today, kinds BUY / TAX / SELL / WAGES / REPAIR / PORT_FEE / INSURANCE / PROVISION /
INSURANCE_PAID). The daybook half has no upper bound (`d.game_day >= v_lo` only — verbatim from the old statement; harmless in operation, where nothing is newer than the real
`p_now`), and prod's daybook holds today's days while CI's and the local proof's world have none. So every assertion that compared a WHOLE map or period (R1, R2's expected map,
R4, T1-T3) was wrong on a populated world and right on an empty one. The migration is atomic, so nothing was kept (prod head still 0294, `stats_recent` absent).

**What changed**
1. **Every map and period compared is cut to the probe's own key space first**: days `[D−130, D+20]` and the probe's kinds (`PROBE_0299`, `PROBE_0299_B`, and `CARRIED` so that a leaked
   CARRIED row still shows) for maps; the probe's two kinds for periods (`pg_temp.probe_0299` / `kinds_0299`). The one whole-map comparison left — the old statement against the
   new reader on the same rows (R2, R3) — runs in **one SELECT, one snapshot** (the old statement is a STABLE scratch function), so the hourly roll cannot move the real days between the two reads.
2. **Failure messages are compact**: every argument goes through `pg_temp.cap_0299` (500 characters, then its length), and only the filtered probe map is printed — never a table.
3. **The audit**: every other comparison in the file is a catalog read, a before/after image taken in the same transaction (functions, registry, owner switches, `world_config`'s md5 —
   which only the four owner-switch functions ever write), a probe-key-space existence check (`game_day` band, 2004 instants) or a kind-limited leftover check. None counts, sums or
   compares a real table without a probe filter.
4. **The rehearsal now has populated worlds** (§4) and the old text, applied to them, reproduces the prod failure.

## 2. The defect — measured read-only on prod

Each `stats_world` row's `period` (-> `minted` / `removed` / `moved`, the Stats money log) is, per kind, this count's `recent` less the previous count's
`recent`, where `recent` = `{game_day: {kind: ducats}}` over the NEWEST THREE game days of `treasury_daybook` + `treasury_flows`. `game_day_seconds` is
**60** (the every-minute market, 10-30) and the count runs every 15 minutes, so `recent` reaches back 2-3 minutes of the row's 15 and two consecutive
`recent` maps never share a day: `period` is the money of the newest ~2 days, not of the window. The window-based figures of the SAME row are right:

| row (UTC) | bought (window) | period.BUY | × | sold (window) | period.SELL | × |
|---|---|---|---|---|---|---|
| 11-01 18:21 | 22,381,382 | 2,605,863 | 8.59 | 21,686,528 | −4,733,320 | 4.58 |
| 11-01 18:06 | 25,310,348 | 2,996,731 | 8.45 | 27,997,554 | −4,516,147 | 6.20 |
| 10-30 18:06 | 6,565,278 | 659,505 | 9.95 | 6,087,608 | −449,600 | 13.54 |
| 10-30 17:51 | 6,859,463 | 1,382,795 | 4.96 | 5,910,157 | −895,512 | 6.60 |
| 10-30 17:36 | 7,728,137 | 759,903 | 10.17 | 7,499,340 | −914,231 | 8.20 |
| 10-30 17:21 | 8,652,564 | 1,414,376 | 6.12 | 9,534,434 | −963,572 | 9.89 |
| 10-30 17:06 | 10,666,400 | 1,594,850 | 6.69 | 8,012,942 | −998,198 | 8.03 |

**And the flows themselves agree with the window figures to the ducat** (summed from `treasury_flows` over each row's own window `(previous at, at]`, taken
while those flows were still un-rolled): 18:21 → Σ `BUY` 22,381,382 = `bought`, Σ `SELL` −21,686,528 = −`sold`; 18:06 → Σ `BUY` 25,310,348 = `bought`,
Σ `SELL` −27,997,554 = −`sold`. So a `period` read over the whole window will equal `bought` / `sold`; today the money log is 4.6-13.5 times short.
`world.stats_overview` serves the completed rows' `period` PLUS the minutes since the last count read over a real window, so the log mixes an understated
past with a correct tail.

## 3. The fix — one reader, one hunk

- **`public.stats_recent(p_now timestamptz, p_since timestamptz) returns jsonb`** (new; STABLE, SECURITY DEFINER, `search_path = public, pg_temp`, server-only —
  `revoke … from public, anon, authenticated`, the ACL of its `stats_window_*` siblings). The `{game_day: {kind: ducats}}` map over every game day from
  `least(game_day(p_now), game_day(p_since)) − 2` to p_now's day. It is `tick_stats`' inline query **moved verbatim** (daybook half + flows half, 0243's
  per-(day, kind) sum before the aggregate, `CARRIED` excluded, the flows cut at `p_now`) with one change: the lower bound, computed once in `v_lo`.
- **`tick_stats`: ONE hunk** — the 16 lines `-- THE WORLD: the newest three game days … group by x.gd) d;` (lines 51-66 of the live body) become
  `v_recent := public.stats_recent(p_now, v_prev_at);` (+ a three-line comment). `v_prev_at` is the window start AFTER 0290's cap, so a catch-up count reads at
  most `stats_max_window_minutes`. The `period` statement, `stats_window_founded`, `stats_sides` and every other line are byte for byte (the self-assert
  reverses the hunk to the pre-image). It SUPERSEDES / re-cuts `tick_stats` and says so in its header (`tests/duplication.spec.ts:378`).
- The table comment of `stats_world` (`recent` is no longer "the newest three game days"), written last so its lock is held only to the commit.
- **The pre-image** is the LIVE body 0290 left: md5 `899a09d32771e57aa276547f639829c0`, 12,955 characters — **the same on prod (PG 17.6) and in the chain** (PGlite 18.3,
  restored from the prefix cache at 282 files, names and content digest verified); re-read on prod 2026-11-01 19:26 UTC, unchanged. 0291 mentions `tick_stats` in a header comment
  only; 0292 / 0293 / 0294 do not; the open 0297 / 0298 migrations do not mention it either. Nothing else reads `stats_world.recent`: live catalog (of the 7 functions whose source
  mentions `stats_world`, only `tick_stats` mentions `recent`), the chain, `src/` and `tests/`; `stats_fold` keeps the last slot's, `world.stats_*` read `period`.

## 4. The points the design left open — decided, and proved in the self-assert

### 4.1 The first row after the deploy (the previous row's `recent` has the OLD shape)
**No new code is needed: the rule already exists.** `tick_stats`' `period` statement walks the NEW map's (game day, kind) pairs and subtracts the previous
row's value for the SAME day and kind, or nothing when the previous row held no such day:

> a day only in the new map counts in full · a day in both counts the difference · a day only in the old map is never read.

It is not a difference of totals (that WOULD spike — it subtracts the old map's days the new one no longer holds). The statement stays byte for byte.
Rolling back to the old body later is as safe: it walks the three-day map against a wider previous map by the same key rule.
With §4.3 every day of an old-shape previous row is also in the new map, so on the very first row even a difference of totals would read right; the rule
matters from the second row on. Proof (probe rows dated 2004, the REAL `tick_stats` body cut right after the `period` statement; the periods and maps below are the probe's own kinds and days):

| probe | previous row | result |
|---|---|---|
| **T1** first row | OLD shape: days D−17, D−16, D−15 (D−15 held 100 at its instant) | `period` = the window's flows to the ducat: a **46,551** (D−15: 140 − 100 = 40, D−14 … D: 46,511), b **120** |
| **T2** steady state | NEW shape (T1's 18-day map) one window (15 days) later; 99,999 more on D after it, 100 … 1,500 on D+1 … D+15 | `period` = the new flows only, a **111,999**; the 15 old-only days D−17 … D−3 are ignored. A **plain difference of totals on the same two maps reads 71,348** (the positive control: the probe can tell the rules apart) |
| **T3** five hours old | `{}` | the 0290 cap decides the bound: `since` = p_now − 120 min, `skipped` = {previous, cap}, `recent` = D−122 … D−120 only (D−123, inside the five hours but below the capped bound, is absent). A call that passed the raw previous instant would read it |

### 4.2 Cost (the count's wall is 120 s; `recent` is 1.1-23 s of it: 1.9 / 10.6 / 8.6 s in the last three counts)
Read-only on prod, 2026-11-01 ~18:20-19:00:

| | rows | pages |
|---|---|---|
| `treasury_flows` | 12,042 | 215 (1.7 MB); indexes `treasury_flows_created_at`, `_port_at`, `_pkey` |
| `treasury_daybook` | 5,963 (30 game days kept) | 615 (4.9 MB); only `treasury_daybook_pkey (port_id, game_day, kind)` |

- The flows half filters `world.game_day(created_at) >= …`, which no index can serve: at a real `p_now` a **seq scan that evaluates every flows row whatever the range**.
  The daybook half is a scan of its primary key whose second column carries the bound (`EXPLAIN`, no `ANALYZE`: identical plan for 3 and for 18 days).
  **Neither half reads one more row or page for a wider range.** Only the rows that PASS grow: flows 205 (3 days) → 4,330 (18 days); daybook 0 → 0 right
  now (everything older than the last roll is in it, the window is not).
- Timed server-side on prod (`clock_timestamp` inside one SELECT), the same query: **3 days 0.88 s → 18 days 1.04 s** (first series), and **0.53 s → 0.70 s**
  (medians of four and three; second series): **+0.16 s, +18-33 %**. Computing the bound once (as here) against inline: no difference. At 18:55, with the
  disk busy, the same 18-day SELECT took 7.3 s — the receipts' spread is load, not range.
- The width is bounded above twice: by the **120-minute window cap** (at most 122 days at 60 s a day) and by the **two tables' size**, which a range cannot
  grow. **No further cap is added.** A sargable lower bound on `created_at` (tried read-only) saved ~0.07 s of the 0.17 s; not worth a second change in the reader.
- `stats_world.recent` grows from ~0.9 KB to **~3.6 KB** a row (17 days × 10 kinds measured: 2,472 characters, 3,560 bytes as jsonb, before compression).
  The hourly tier keeps one row an hour for ever (the fold keeps the last slot's `recent`): ~30 MB a year. Trimming it belongs to the fold; not touched.

### 4.3 Two days below the window (a deliberate difference from the first design — confirmed by the coordinator)
The first design read from `least(game_day(p_now) − 2, game_day(p_since))`. The migration reads from `least(game_day(p_now), game_day(p_since)) − 2`:
the window's first day **less two**. The count fires at hh:mm:00 + 0.06-3 s (`stats_runs`: 18:06:00.059, 17:36:00.082, 17:51:01.37), i.e. just after a game-day
boundary, so a flow created in the last moments of the previous day and committed after the previous count's snapshot sits in the day BEFORE the window's
first day: outside a bound that starts at the window's first day no row would ever count it; inside this one it is in the previous row's map too and the
per-key difference picks it up. This is the slack the old three-day shape always had (the current day and two before it), applied to the window; with a
window inside one game day the bound is today's three days exactly (probe R2: equal to the old statement on the same rows). How many flows this saves was not
measured (the daybook collapses those days at the next roll). Mutation M03 shows the self-assert holds the slack; reverting is one token.

### 4.4 The run time (the runner's push pauses EVERY cron job for as long as it runs)
Rule from the coordinator after the reconcile fix froze the game clock for 10 minutes: the guard sets `statement_timeout` to **90 s** (not 10 minutes) and `lock_timeout` to
5 s, and the self-assert must run in **≤ 45 s** on prod. The first estimate here (about 8 reads of `treasury_flows`, 15-60 s) was wrong: **every probe instant is in 2004, so the
flows half (`created_at <= p_now`) is an index scan of an empty range** (`EXPLAIN`: `Index Scan using treasury_flows_created_at … Index Cond: created_at <= '2004-06-01 …'`) and the
real flows are never read; the daybook half, which has no upper bound, returns the real daybook once per call (~3,700 rows from 615 pages). Measured read-only on prod, server-side, calm
(19:38-19:40 UTC, `clock_timestamp` inside one SELECT):

| read | time |
|---|---|
| `stats_recent`'s statement at a 2004 instant (what R1-R4 and the cut call), 4 runs | 19, 5, 5, 5 ms |
| the md5 pass over all 676 functions (done twice: before and after) | 0.38 s cold, 0.027 s warm |
| the cut's `price_history` max / `stats_window_founded` / previous-row reads | 5-16 / 6 / 3 ms |
| the key-space guards (daybook band, flows band, `stats_world` 2004) and the leftover checks | 4-5 ms |
| the knobs' md5 / the registry count | 1 / 8 ms |

Well under a second of reading in all, plus the DDL and ~65 planted rows. The whole file: **84-163 ms** on the local worlds (clean, noisy, prod-data), **~0.3 s** on CI's real Postgres
(`supabase migration up`), and it **prints its own elapsed time** (printed, never asserted). Not measured as a whole on prod (a push is the only way); the ceiling is the 90 s timeout.

## 5. The proof (self-assert, ONE atomic `DO` block: a failed assert keeps none of the file)

The deploy runner is not a transaction block (`docs/OPS_HEALTH.md` §4), so the two functions, the table comment and every assert share one `DO` block (one
transaction): nothing of the file is kept if an assert fails. No top-level `LOCK`, no `ON COMMIT DROP`, no `ANALYZE`; the guard sets `statement_timeout` 90 s and `lock_timeout` 5 s for the
session, and the file resets them at the end. Probe rows are dated 2004 (the guard asserts that no daybook day `[D−130, D+20]`, no flow in that span and no
`stats_world` row of 2004 exists), planted in rolled-back sub-transactions, with `game_day_seconds` pinned to 60 and `stats_max_window_minutes` to 120 INSIDE the probe.

- **(a) as found**: the hunk occurs once in the live body and reverses to the pre-image; `tick_stats` keeps ACL / volatility / definer / config and no longer
  reads `treasury_daybook`; `stats_recent` is STABLE, SECURITY DEFINER, no anon / authenticated / PUBLIC execute, `search_path` set, and its body holds the old
  statement text with only the bound renamed; **every other function in public / cmd / world / voyage md5-unmoved (676 on prod: exactly `tick_stats` differs,
  exactly `stats_recent` is new)**; registry (84), walls (0 / 0 / 0), both owner switches and every knob as found.
- **(b) the reader** on planted rows (both halves, a day in BOTH halves, `CARRIED`, a flow after `p_now`, days below the bound), each answer cut to the probe's days and kinds: **R1** a 15-day window → exactly its
  18 days; **R2** `p_since = p_now` → the old three-day shape, equal to the old statement run on the same rows (whole maps, one snapshot); **R3** `p_since` after `p_now` → the same three days;
  **R4** `p_since` 30 days back → every planted day (nothing caps it inside the reader).
- **(c) the count**: T1 / T2 / T3 above.
- **(d)** no probe row, no knob moved, scratch functions dropped.

### The rehearsal worlds (the proof the way prod will see it — never a from-zero replay)
The local harness restores the chain's 282 files from the prefix cache (candidate excluded; nothing written to the shared cache), sets a WORLD up, then applies the file with the applier's own `db.exec`:

| world | what it holds | the old text (0295 as pushed) | this file |
|---|---|---|---|
| **clean** (= CI's) | the chain's tiny world | passes | passes, 120 ms |
| **noise** | `game_day_seconds` and `drift_slot_seconds` 60 (prod's regime); the daybook holds today's real days (20 harbours × 6 days × BUY / SELL / TAX), days just above the probe's band (D+21, D+25, D+500, D+100000), 800 recent flows at now() − k minutes, 4 counts already written | **FAILS at R1** (1,239-character message) | passes, 97 ms — R1's raw answer carried **10** real days besides the probe's, ignored |
| **prod** | prod's own tables imported read-only on 2026-11-01 19:28 UTC: `world_config` (291 keys), `treasury_daybook` (5,769 rows, game days 29,892,607 … 29,892,636), `treasury_flows` (12,300), `stats_world` (275); ports mapped by code | **FAILS at R1** (5,051 characters) | passes, 115 ms — R1's raw answer carried **30** real days, ignored |

**Mutation controls (the asserts can fail): 39 in-memory mutations of the file, each applied to each of the three worlds** (117 runs). **29 are caught by the assert meant for them in all three worlds** (the bound, each half, CARRIED, the 0243 sum, the call's argument, the cap, the ACL / volatility / definer, another function moved, an owner switch, a knob, the pre-image, probe rows surviving, a real row in the probe's key space, the period statement rewritten as a difference of totals). **The 8 "remove a probe filter" mutations** (R1, R2, R4, T1 recent and period, T2 recent, T3 recent and period — M30-M35, M37, M38; M30 is the one the coordinator asked for) **apply on the clean world, as they must (it holds nothing but the probe's own rows), and are CAUGHT on both populated worlds.** Two controls apply everywhere by design: M36 (T2 reads the previous row's whole map, so the real days net to zero and drop out of the period; its kind filter stays as belt and braces) and M39 (a probe filter that forgot CARRIED hides a CARRIED leak — which is why the filter keeps CARRIED). The longest failure message in the whole run was **666 characters** (the first prod failure was 34 KB). (Scratch harness, not in the repo.)

### Gates (local, lean; CI is the full proof)

| gate | result |
|---|---|
| `node scripts/db/check-versions.mjs` | 284 migrations (0297 is on main), 284 distinct versions, positive control fired |
| `BYEHARU_PREFIX_CACHE=required node scripts/db/proof.mjs standing` | 283 restored from the prefix cache (2.1 s), 1 applied (mine); **284 / 284 with a self-assert receipt (296 receipt lines)**; world-guard ok; `11_standing_route` 5 / 5 PASS; never a from-zero replay |
| `BYEHARU_PREFIX_CACHE=required npm run build` | clean (`tsc -b` + `vite build`); world image from the prefix cache (282 restored, 2 applied), certified, 18.46 MB gz |
| `npx playwright test tests/duplication.spec.ts tests/rpc.stats.spec.ts` | **18 passed** (11 + 7), 0 failed, 0 skipped |
| the three rehearsal worlds | clean 120 ms, noise 97 ms, prod-data 115 ms; the old text fails R1 on the last two |
| 39 mutations × 3 worlds | as above |

## 6. PROD CHECKS (read-only, one pure SELECT per call, 2026-11-01 18:20-19:40 UTC, before the PR; the first four re-read 19:26)

| check | result |
|---|---|
| head | `20260818000294` (282 migrations) |
| `tick_stats` | md5 `899a09d32771e57aa276547f639829c0`, 12,955 chars, volatile, SECURITY DEFINER, ACL `{postgres=X/postgres,service_role=X/postgres}`, `search_path = public, pg_temp` — equal to the chain's body (PGlite, prefix cache p0282) |
| `stats_recent` | absent (`to_regprocedure` null) |
| the hunk / the cut anchor | each occurs exactly once in the live body (fetched with `pg_get_functiondef`, checked offline) |
| the 2004 probe key space | `treasury_daybook` game_day 18,101,400-18,101,600: 0 rows · `treasury_flows` in 2004: 0 · `stats_world` before 2005: 0 |
| walls and switches | `client_rpc_entry_points` 84 · `client_write_grants` 0 · `client_executable_writers` 0 · `caller_evaluated_functions` 0 · `economy_closed` true · `city_treasury_enabled` true |
| functions | 676 in public / cmd / world / voyage; callees: `world.game_day` `50aa4dac…`, `stats_window_start` `71df0bbe…`, `stats_window_founded` `71f490e4…`, `stats_sides` `a246a9da…`, `stats_compact` `afc04c87…`, `tick_city` `a0e8c4d6…` |
| table locks | no function that touches `treasury_flows` / `treasury_daybook` takes an explicit table lock (catalog scan): the probe's inserts never wait on one |
| `world_config` writers | only the four owner-switch functions (`city_treasury_switch`, `economy_close_switch`, `influence_switch`, `npc_traders_switch`) write it at run time |
| knobs | `game_day_seconds` 60 · `drift_slot_seconds` 60 · `stats_max_window_minutes` 120 · `treasury_days_kept` 30 |
| volatility of everything the measurements called | `world.game_day`, `wc_num`, `wc_int`, `drift_slot_of`, `stats_window_start`, `stats_window_founded` are all `s` (no `EXPLAIN ANALYZE`, no volatile call) |
| the count today | `cron.job_run_details`: 7 of the last 8 runs succeeded in 55-112 s; the **18:51 run FAILED at 120.8 s** (`canceling statement due to statement timeout` inside `insert into public.stats_city_good`) — the city_goods phase, not `recent` |

## 7. Where this differs from the first design (this file's first version)

1. Renumbered 0292 → 0295 → 0299; the pre-image is 0290's output, verified by md5 on prod and in the chain (0291-0294 do not touch it).
2. The lower bound has two days of slack below the window (§4.3).
3. The first-row question needed no code: the live `period` statement already compares per (game day, kind) (§4.1); it is proved, not changed.
4. No cost cap was added: the widening is +0.16 s, bounded by the window cap and the table size (§4.2).
5. One atomic `DO` block instead of several statements (the runner is not a transaction block), the table comment moved last (its lock is held only to the commit).
6. The probe looks only at its own key space, prints compactly, and has been rehearsed on populated worlds (§1, §5); the guard's `statement_timeout` is 90 s and the run time is measured (§4.4).

## 8. After-check (coordinator, read-only, after `bv-deploy.sh`)

```sql
-- the first three rows written by the new body: period read over the whole window equals the window's bought / sold
select w.at, w.bought, (w.period->>'BUY')::bigint as period_buy,
       round(w.bought::numeric / nullif((w.period->>'BUY')::numeric, 0), 4) as buy_ratio,
       w.sold, -(w.period->>'SELL')::bigint as period_sell,
       round(w.sold::numeric / nullif(-(w.period->>'SELL')::numeric, 0), 4) as sell_ratio,
       (select count(*) from jsonb_object_keys(w.recent)) as recent_keys
  from public.stats_world w order by w.slot desc limit 6;
-- phases and outcome of the same counts
select r.at, r.ms, r.receipt->'phases'->>'recent' as recent_ms, r.receipt->'phases'->>'period' as period_ms, r.receipt->'skipped' as skipped
  from public.stats_runs r order by r.at desc limit 6;
```
Expect, on the rows written after the deploy: `buy_ratio` and `sell_ratio` **1.0000** (the two pre-fix rows of §2 agree to the ducat when summed from the flows; a row after a
missed run, whose oldest days were already collapsed into `CARRIED`, can read a little under); `recent_keys` **14-18** (a game day with no flows has no key; 17 of 18 in the
measured sample); the older rows keep their 4.6-13.5×. `recent_ms` in the band it was in (1-11 s, +~0.2 s); `ms` under 120,000; the cron job `succeeded`. The new bodies' md5
(computed on the PGlite chain; the old body's md5 was identical there and on prod): `tick_stats` `a4f65a9d635da3f4863cbd903423dc99` (12,404 chars), `stats_recent`
`c3eb848339c337cbcfc5224ab6b4606d` (2,131 chars). Forward rollback: re-create `tick_stats` from the OLD hunk text in the migration header, drop `stats_recent`.

## 9. Said plainly / not in this slice

- **Old rows keep their understated `period`.** History is not rewritten, and cannot be: their `recent` kept three days and the daybook keeps 30 game days (30
  minutes). The money log steps up at the first new row; the hourly fold sums `period`, so an hour mixing old and new rows is understated once.
- A gap longer than the daybook's memory (`treasury_days_kept` 30 game days = 30 minutes) cannot be recovered by any reader; a day that vanished that way is "only
  in the old map" and is ignored — no negative spike.
- A catch-up count (the 0290 cap) now also counts the two game days before its capped start — the span `skipped` records: at most two minutes of money more in that one row.
- The 0293 dev-log (§4) mentions a follow-up "with the period fix": the drain first in the count, and the journal's size in the receipt. That is NOT in this file
  (one hunk, no other line of `tick_stats` changes); it would be its own migration.
- The count is still fragile (the 18:51 run, above). This slice adds ~0.2 s to a phase and removes none of the other phases' time.

## 10. Bookkeeping
Owner row 256 state line (`docs/OWNER_REQUESTS.md`); `docs/WORK_QUEUE.md` is not edited (coordinator's instruction). PR title `MIGRATION — 0299: the period is the whole window
(deploy AFTER 0298)`; commit trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
