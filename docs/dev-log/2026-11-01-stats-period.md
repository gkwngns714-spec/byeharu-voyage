# 2026-11-01 — 0295: the count's `period` is read over the count's real window

**Branch** `stats-period` · migration `supabase/migrations/20260818000295_the_period_is_the_whole_window.sql` · deploys AFTER 0294
(prod head `20260818000294`, 282 migrations, read 2026-11-01 19:02 UTC). Found while measuring the Stats slice of owner rows 256 / 259
(`docs/OWNER_REQUESTS.md`); not a new instruction. The owner's limit on that slice stands — *"DO NOT CHANGE ANYTHING REGARDING TIME - THE SECONDLY
DATA RENEWAL STAYS IN STATS"* — and nothing about time moves: no cron job or schedule, no knob, no switch, no client read, no other line of `tick_stats`.
(This note was first written as "0292 / after 0290-0291"; the numbers are now 0295 / after 0294, and §6 lists what differs from that first design.)

## 1. The defect — measured read-only on prod

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

## 2. The fix — one reader, one hunk

- **`public.stats_recent(p_now timestamptz, p_since timestamptz) returns jsonb`** (new; STABLE, SECURITY DEFINER, `search_path = public, pg_temp`, server-only —
  `revoke … from public, anon, authenticated`, the ACL of its `stats_window_*` siblings). The `{game_day: {kind: ducats}}` map over every game day from
  `least(game_day(p_now), game_day(p_since)) − 2` to p_now's day. It is `tick_stats`' inline query **moved verbatim** (daybook half + flows half, 0243's
  per-(day, kind) sum before the aggregate, `CARRIED` excluded, the flows cut at `p_now`) with one change: the lower bound, computed once in `v_lo`.
- **`tick_stats`: ONE hunk** — the 16 lines `-- THE WORLD: the newest three game days … group by x.gd) d;` (lines 51-66 of the live body) become
  `v_recent := public.stats_recent(p_now, v_prev_at);` (+ a three-line comment). `v_prev_at` is the window start AFTER 0290's cap, so a catch-up count reads at
  most `stats_max_window_minutes`. The `period` statement, `stats_window_founded`, `stats_sides` and every other line are byte for byte (the self-assert
  reverses the hunk to the pre-image). It SUPERSEDES / re-cuts `tick_stats` and says so in its header (`tests/duplication.spec.ts:378`).
- The table comment of `stats_world` (`recent` is no longer "the newest three game days").
- **The pre-image** is the LIVE body 0290 left: md5 `899a09d32771e57aa276547f639829c0`, 12,955 characters — **the same on prod (PG 17.6) and in the chain** (PGlite 18.3,
  restored from the prefix cache at 282 files, names and content digest verified). 0291 mentions `tick_stats` in a header comment only; 0292 / 0293 / 0294 do not
  mention it. Nothing else reads `stats_world.recent` (grep of the chain and of `src/` / `tests/`): `stats_fold` keeps the last slot's, `world.stats_*` read `period`.

## 3. The three points the design left open — decided, and proved in the self-assert

### 3.1 The first row after the deploy (the previous row's `recent` has the OLD shape)
**No new code is needed: the rule already exists.** `tick_stats`' `period` statement walks the NEW map's (game day, kind) pairs and subtracts the previous
row's value for the SAME day and kind, or nothing when the previous row held no such day:

> a day only in the new map counts in full · a day in both counts the difference · a day only in the old map is never read.

It is not a difference of totals (that WOULD spike — it subtracts the old map's days the new one no longer holds). The statement stays byte for byte.
Rolling back to the old body later is as safe: it walks the three-day map against a wider previous map by the same key rule.
With §3.3 every day of an old-shape previous row is also in the new map, so on the very first row even a difference of totals would read right; the rule
matters from the second row on. Proof (probe rows dated 2004, the REAL `tick_stats` body cut right after the `period` statement):

| probe | previous row | result |
|---|---|---|
| **T1** first row | OLD shape: days D−17, D−16, D−15 (D−15 held 100 at its instant) | `period` = the window's flows to the ducat: a **46,551** (D−15: 140 − 100 = 40, D−14 … D: 46,511), b **120** |
| **T2** steady state | NEW shape (T1's 18-day map) one window (15 days) later; 99,999 more on D after it, 100 … 1,500 on D+1 … D+15 | `period` = the new flows only, a **111,999**; the 15 old-only days D−17 … D−3 are ignored. A **plain difference of totals on the same two maps reads 71,348** (the positive control: the probe can tell the rules apart) |
| **T3** five hours old | `{}` | the 0290 cap decides the bound: `since` = p_now − 120 min, `skipped` = {previous, cap}, `recent` = D−122 … D−120 only (D−123, inside the five hours but below the capped bound, is absent). A call that passed the raw previous instant would read it |

### 3.2 Cost (the count's wall is 120 s; `recent` is 1.1-23 s of it: 1.9 / 10.6 / 8.6 s in the last three counts)
Read-only on prod, 2026-11-01 ~18:20-19:00:

| | rows | pages |
|---|---|---|
| `treasury_flows` | 12,042 | 215 (1.7 MB); indexes `treasury_flows_created_at`, `_port_at`, `_pkey` |
| `treasury_daybook` | 5,963 (30 game days kept) | 615 (4.9 MB); only `treasury_daybook_pkey (port_id, game_day, kind)` |

- The flows half filters `world.game_day(created_at) >= …`, which no index can serve: a **seq scan that evaluates every flows row whatever the range**.
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

### 3.3 Two days below the window (a deliberate difference from the first design)
The first design read from `least(game_day(p_now) − 2, game_day(p_since))`. The migration reads from `least(game_day(p_now), game_day(p_since)) − 2`:
the window's first day **less two**. The count fires at hh:mm:00 + 0.06-3 s (`stats_runs`: 18:06:00.059, 17:36:00.082, 17:51:01.37), i.e. just after a game-day
boundary, so a flow created in the last moments of the previous day and committed after the previous count's snapshot sits in the day BEFORE the window's
first day: outside a bound that starts at the window's first day no row would ever count it; inside this one it is in the previous row's map too and the
per-key difference picks it up. This is the slack the old three-day shape always had (the current day and two before it), applied to the window; with a
window inside one game day the bound is today's three days exactly (probe R2: equal to the old statement on the same rows). How many flows this saves was not
measured (the daybook collapses those days at the next roll). Mutation M03 shows the self-assert holds the slack; reverting is one token.

## 4. The proof (self-assert, ONE atomic `DO` block: a failed assert keeps none of the file)

The deploy runner is not a transaction block (`docs/OPS_HEALTH.md` §4), so the two functions, the table comment and every assert share one `DO` block (one
transaction): nothing of the file is kept if an assert fails. No top-level `LOCK`, no `ON COMMIT DROP`, no `ANALYZE`; `statement_timeout` raised for the
session in the guard and reset at the end. Probe rows are dated 2004 (the guard asserts that no daybook day `[D−130, D+20]`, no flow in that span and no
`stats_world` row of 2004 exists), planted in rolled-back sub-transactions, with `game_day_seconds` pinned to 60 and `stats_max_window_minutes` to 120 INSIDE the probe.

- **(a) as found**: the hunk occurs once in the live body and reverses to the pre-image; `tick_stats` keeps ACL / volatility / definer / config and no longer
  reads `treasury_daybook`; `stats_recent` is STABLE, SECURITY DEFINER, no anon / authenticated / PUBLIC execute, `search_path` set, and its body holds the old
  statement text with only the bound renamed; **every other function in public / cmd / world / voyage md5-unmoved (676 on prod: exactly `tick_stats` differs,
  exactly `stats_recent` is new)**; registry (84), walls (0 / 0 / 0), both owner switches and every knob as found.
- **(b) the reader** on planted rows (both halves, a day in BOTH halves, `CARRIED`, a flow after `p_now`, days below the bound): **R1** a 15-day window → exactly its
  18 days; **R2** `p_since = p_now` → the old three-day shape, equal to the old statement run on the same rows; **R3** `p_since` after `p_now` → the same three days;
  **R4** `p_since` 30 days back → every planted day (nothing caps it inside the reader).
- **(c) the count**: T1 / T2 / T3 above.
- **(d)** no probe row, no knob moved, scratch functions dropped.

**Mutation controls (the asserts can fail): 29 in-memory mutations of the file, each applied to the chain and each caught by the assert meant for it** —
bound ignoring `p_since` / `greatest` for `least` / no slack / one slack too many; the flows half uncut, CARRIED kept, a half dropped, the 0243 sum undone (each with the
text check off, so the probe itself is what catches it, and once with it on); `tick_stats` passing `p_now`, the raw previous instant, or a sub-selected one; the
period statement rewritten as a difference of totals (caught by T2 only, as designed); `stats_recent` VOLATILE / invoker / open to anon / open to PUBLIC; another
function moved; an owner switch moved; a knob left moved; the pre-image drifted; `tick_stats` still reading the daybook; a probe not rolled back (twice); a real row
in the probe's key space (daybook, and a count). (Scratch harness, not in the repo.)

### Gates (local, lean; CI is the full proof)

| gate | result |
|---|---|
| `node scripts/db/check-versions.mjs` | 283 migrations, 283 distinct versions, positive control fired |
| `BYEHARU_PREFIX_CACHE=required node scripts/db/proof.mjs standing` | 282 restored from the prefix cache (2.4 s), 1 applied (mine, ~0.1 s on the tiny local world); **283 / 283 with a self-assert receipt (295 receipt lines)**; world-guard ok; `11_standing_route` 5 / 5 PASS; never a from-zero replay |
| `BYEHARU_PREFIX_CACHE=required npm run build` | clean (`tsc -b` + `vite build`); world image from the prefix cache, certified, 18.55 MB gz |
| `npx playwright test tests/duplication.spec.ts tests/rpc.stats.spec.ts` | **18 passed** (11 + 7), 0 failed, 0 skipped. (A first run failed `duplication.spec.ts:378`: a migration that re-cuts a function must say "supersede" / "re-cut" in its header; the header now does.) |

## 5. PROD CHECKS (read-only, one pure SELECT per call, 2026-11-01 18:20-19:02 UTC, before the PR)

| check | result |
|---|---|
| head | `20260818000294` (282 migrations) |
| `tick_stats` | md5 `899a09d32771e57aa276547f639829c0`, 12,955 chars, volatile, SECURITY DEFINER, ACL `{postgres=X/postgres,service_role=X/postgres}`, `search_path = public, pg_temp` — equal to the chain's body (PGlite, prefix cache p0282) |
| the hunk / the cut anchor | each occurs exactly once in the live body (fetched with `pg_get_functiondef`, checked offline) |
| `stats_recent` | absent (`to_regprocedure` null) |
| the 2004 probe key space | `treasury_daybook` game_day 18,101,400-18,101,600: 0 rows · `treasury_flows` in 2004: 0 · `stats_world` before 2005: 0 |
| walls and switches | `client_rpc_entry_points` 84 · `client_write_grants` 0 · `client_executable_writers` 0 · `caller_evaluated_functions` 0 · `economy_closed` true · `city_treasury_enabled` true |
| functions | 676 in public / cmd / world / voyage; callees: `world.game_day` `50aa4dac…`, `stats_window_start` `71df0bbe…`, `stats_window_founded` `71f490e4…`, `stats_sides` `a246a9da…`, `stats_compact` `afc04c87…`, `tick_city` `a0e8c4d6…` |
| knobs | `game_day_seconds` 60 · `drift_slot_seconds` 60 · `stats_max_window_minutes` 120 · `treasury_days_kept` 30 |
| volatility of everything the measurements called | `world.game_day`, `wc_num`, `wc_int`, `drift_slot_of`, `stats_window_start`, `stats_window_founded` are all `s` (no `EXPLAIN ANALYZE`, no volatile call) |
| the count today | `cron.job_run_details`: 7 of the last 8 runs succeeded in 55-112 s; the **18:51 run FAILED at 120.8 s** (`canceling statement due to statement timeout` inside `insert into public.stats_city_good`) — the city_goods phase, not `recent` |

## 6. Where this differs from the first design (this file's first version)

1. Renumbered 0292 → 0295; the pre-image is 0290's output, verified by md5 on prod and in the chain (0291-0294 do not touch it).
2. The lower bound has two days of slack below the window (§3.3).
3. The first-row question needed no code: the live `period` statement already compares per (game day, kind) (§3.1); it is proved, not changed.
4. No cost cap was added: the widening is +0.16 s, bounded by the window cap and the table size (§3.2).
5. One atomic `DO` block instead of several statements (the runner is not a transaction block), the table comment moved last (its lock is held only to the commit).

## 7. After-check (coordinator, read-only, after `bv-deploy.sh`)

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
Expect, on the rows written after the deploy: `buy_ratio` and `sell_ratio` **1.0000** (the two pre-fix rows of §1 agree to the ducat when summed from the flows; a row after a
missed run, whose oldest days were already collapsed into `CARRIED`, can read a little under); `recent_keys` **14-18** (a game day with no flows has no key; 17 of 18 in the
measured sample); the older rows keep their 4.6-13.5×. `recent_ms` in the band it was in (1-11 s, +~0.2 s); `ms` under 120,000; the cron job `succeeded`. The new bodies' md5
(computed on the PGlite chain; the old body's md5 was identical there and on prod): `tick_stats` `fa3b1e4cd3d0c67fadbd2f1e2c2024a1` (12,404 chars), `stats_recent`
`871652fc959b0809ac99b8526fd58fb1` (2,131 chars). Forward rollback: re-create `tick_stats` from the OLD hunk text in the migration header, drop `stats_recent`.

## 8. Said plainly / not in this slice

- **Old rows keep their understated `period`.** History is not rewritten, and cannot be: their `recent` kept three days and the daybook keeps 30 game days (30
  minutes). The money log steps up at the first new row; the hourly fold sums `period`, so an hour mixing old and new rows is understated once.
- A gap longer than the daybook's memory (`treasury_days_kept` 30 game days = 30 minutes) cannot be recovered by any reader; a day that vanished that way is "only
  in the old map" and is ignored — no negative spike.
- A catch-up count (the 0290 cap) now also counts the two game days before its capped start — the span `skipped` records: at most two minutes of money more in that one row.
- The 0293 dev-log (§4) mentions a follow-up "with the period fix": the drain first in the count, and the journal's size in the receipt. That is NOT in this file
  (one hunk, no other line of `tick_stats` changes); it would be its own migration.
- The count is still fragile (the 18:51 run, above). This slice adds ~0.2 s to a phase and removes none of the other phases' time.

## 9. Bookkeeping
Owner row 256 state line (`docs/OWNER_REQUESTS.md`); `docs/WORK_QUEUE.md` is not edited (coordinator's instruction). PR title `MIGRATION — 0295: the period is the whole window
(deploy AFTER 0294)`; commit trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
