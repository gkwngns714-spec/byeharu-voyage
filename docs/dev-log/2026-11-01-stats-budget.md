# 2026-11-01 — 0290: the count keeps to a budget (Stats cannot snowball again)

**Branch** `stats-budget` · **migration** `supabase/migrations/20260818000290_the_count_keeps_to_a_budget.sql`
(prod head is `20260818000289` — re-read it before the PR; if it moved, renumber to head+1 and say so in the header) ·
**deploy** one migration at a time, `~/bin/bv-deploy.sh <pr>`, by the coordinator (not the author).

## 1. The owner's words

2026-10-31 (`docs/dev-log/2026-10-31-stats-timeout.md` §3b): *"STATS NOT WORKING, THINGS ARE GETTING SLOW... FIND THE ROOT,
FIX IT. BUT DO NOT CHANGE ANYTHING REGARDING TIME - THE SECONDLY DATA RENEWAL STAYS IN STATS, AND SO ON."*
2026-11-01: *"the game has become slow, especially stats which isn't working properly."*

So: the cron schedule, `drift_slot_seconds`, the client's 1-second reads, the journal's one-row-per-change and
`world.stats_now()` do **not** move in this slice.

## 2. What is broken — measured read-only on prod, 2026-11-01 ~13:20–13:40 UTC

- The count (`public.tick_stats`, cron `byeharu-voyage:stats`, `6,21,36,51 * * * *`) has failed on **every run since
  2026-10-30 18:21** — about 170 runs, each `57014 statement timeout` at 120 s. Last good row: `stats_world.at =
  2026-10-30 18:06:00` (slot 29889726). 0287's indexes (live, valid, used) did not revive it.
- `public.stats_live_deltas` (the journal) holds **2,107,636 rows (236 MB)** and grows ~19 rows/s. `world.stats_now()`
  sums all of it on every call (~9 s a read; the Stats tab asks every second).
- Where the 120 s lands (cron `return_message` CONTEXT): since 11-01 00:00 (after 0287) **39 of 50 inside the retention
  fold `public.stats_compact`** (incl. its `stats_bucket` calls) and 11 of 50 in `stats_merchants_window`. Since 10-31 00:00:
  fold 77, merchants 44, `stats_window_trades` 18, city_goods 4, day 1.
- Pre-spiral receipts (`public.stats_runs.receipt.phases`, ms), 10-30 17:06–18:06: merchants 11–13 k, fold 9–10 k
  (**32–34 k on the first run of an hour**), day 4–8 k, recent 2–5 k, city_goods 2–3 k, live 0.7–1.4 k → 34 s a run,
  60–63 s on the hour. That was ALREADY 28–52 % of the 120 s budget.
- **The stats tables have no index on `at` or on `slot` alone** (primary keys only). Every `stats_fold` range
  (`w.at >= lo and w.at < hi`) and `stats_fold_day` (`x.slot > v_from`; `set day = null where slot < p_slot and day is
  not null`) is a sequential scan: stats_city_good 566 k rows / 211 MB, stats_good 220 k / 66 MB, stats_city 92 k / 41 MB.
- The database is Micro-class compute (shared_buffers 256 MB, effective_cache_size 768 MB, max_connections 60), so those
  scans are cold-disk reads. (A bigger compute is the owner's decision and not part of this slice.)

## 3. Why it cannot recover by itself — the root

The count is an **unbounded batch at three layers**; a failed run rolls everything back, so no layer ever makes progress,
and each further miss only makes the next run heavier:

1. **window** — `tick_stats` reads `v_prev_at` from the last *successful* row, so every flow window is
   `(last row, now]`: now 43 h and growing.
2. **fold** — `stats_compact` re-scans `[edge − 14 days, edge)` of every stats table on every run and keeps no memory of
   what it already folded. After an outage every fine row has aged past the fine edge at once (stats_city_good: 48 h of
   fine rows ≈ 288 k rows), so the first run must fold the entire backlog in one statement.
3. **journal** — `stats_live_fold` deletes the WHOLE journal in one statement (2.1 M rows).

## 4. The design — every count run does at most a fixed amount of work; what is left carries to the next run

### 4.1 Knobs (`insert into public.world_config (key, value, description) … on conflict (key) do nothing`, as 0246 does)

| key | default | meaning |
|---|---|---|
| `stats_max_window_minutes` | 120 | the most one count reads back: window = (max(last row `at`, p_now − this), p_now] |
| `stats_fold_batch_hours` | 4 | hourly buckets folded per table per run |
| `stats_fold_batch_days` | 1 | daily buckets folded per table per run |
| `stats_live_batch_rows` | 300000 | journal rows compacted per run when the journal is over this size |
| `stats_budget_secs` | 60 | optional work (the fold, the journal compaction) starts only while the run has used less than this |

No existing knob changes value.

### 4.2 The seams (each a small function with ONE job, so each bound is testable on its own)

- `public.stats_window_start(p_prev timestamptz, p_now timestamptz) returns timestamptz`, STABLE:
  `greatest(p_prev, p_now − make_interval(mins => wc_int('stats_max_window_minutes')))`. The one rule for "how far back
  may a count read".
- `public.stats_late() returns boolean`, VOLATILE: `clock_timestamp() − statement_timestamp() >
  make_interval(secs => wc_num('stats_budget_secs'))` — "this run has used its budget". Used by `stats_compact` and by
  the journal drain; nothing else decides lateness.
- `public.stats_live_compact(p_tbl regclass, p_rows bigint) returns bigint`: replaces the first `p_rows` rows of a
  journal-shaped table (by `ctid`) with ONE row — `at` = their max, every figure = their sum — and returns how many it
  replaced. The sum of the table is unchanged by construction. `stats_live_fold` calls it on
  `public.stats_live_deltas`; the self-assert calls it on a TEMP table of the same shape (so it never scans the real
  2.1 M-row journal).
- `public.stats_fold_marks (tbl text, unit text check (unit in ('hour','day')), through timestamptz, primary key (tbl, unit))`:
  how far each stats table is folded per tier. Server-only like every stats table (RLS on, `revoke all … from public,
  anon, authenticated`), comment saying who writes it (`stats_compact` alone).

### 4.3 `public.tick_stats` — hunks only, cut against the LIVE body (pre-image `md5(pg_get_functiondef) =
`d2e72eede1406c36a08dc08b99caf604`), each hunk exactly once and reversible (the 0243/0246/0269 method)

- declare: `v_skip jsonb;` — the span the cap left uncounted.
- right after `v_prev_at := coalesce(v_prev_at, …)`: if `stats_window_start(v_prev_at, p_now) > v_prev_at` then
  `v_skip := {from: v_prev_at, to: stats_window_start}` and `v_prev_at := stats_window_start(...)`.
  (`v_prev_rec` and the `period` difference are untouched.)
- the `v_ret` object gains `'skipped', v_skip` (the receipt in `stats_runs` carries it).
No other hunk: the fold's and the journal's lateness live inside `stats_compact` / `stats_live_fold`.

### 4.4 `public.stats_compact` — re-cut as a whole function (pre-image md5 `6ae5bf23fc0fe2ddb848ce9c693a32e3`; declare the
supersede in the header, as `tests/duplication.spec.ts` "a migration that re-cuts an existing function declares the
supersede" requires)

Same five tables, same tiers, same `stats_fold` calls, same return keys (`removed`, `tables`, `ms`) — plus `late`.

- First line: `if public.stats_late() then return {removed: 0, tables: {}, late: true, ms: 0}`.
- Per table, **day tier first**: `lo = coalesce(mark(tbl,'day'), bucket(v_last − hour_window, 'day') − 24 h)`,
  `hi = least(v_d_hi, lo + 24 h × stats_fold_batch_days)`; if `hi > lo`: `stats_fold(tbl,'day',lo,hi)`, mark := hi.
  **Then hour tier**: `lo = greatest(coalesce(mark(tbl,'hour'), bucket(v_last − fine, 'hour') − 1 h), v_d_hi if the table has a
  day tier)`, `hi = least(v_h_hi, lo + stats_fold_batch_hours h)`; if `hi > lo`: `stats_fold(tbl,'hour',lo,hi)`, mark := hi.
- `v_last` = the newest `stats_world.at` (null on an empty world → use `p_now`). **Why that is the right first mark:** at the
  instant of the newest count the old unbounded fold had finished everything before `bucket(v_last − fine)`, so the oldest
  possibly-unfolded bucket starts there; the one-bucket slack is harmless because `stats_fold` is idempotent. A mark, once
  written, is never recomputed from `v_back` again (`stats_fold_back_days` stays as a knob but is no longer read — say so in
  the header; do not delete the knob row).
- Edges stay exact: all arithmetic in HOURS (`make_interval(hours => …)`), as 0246 does, never `interval '1 day'`.
- The mark write is in the same transaction as the fold: a failed run rolls both back.

### 4.5 `public.stats_live_fold` — one hunk at the top of the body (pre-image md5 `baa36db2387718e4173c6d8cfcebcc7f`)

If the journal holds MORE than `stats_live_batch_rows` rows (test with `select count(*) from (select 1 from
public.stats_live_deltas limit batch + 1)` — it stops after batch+1 rows, never counts 2 M), then **do not run the full
fold**: if `not stats_late()` call `stats_live_compact('public.stats_live_deltas', batch)`; return the usual keys
(`drift`, `folded` = 0, `through`, `at`, read from `stats_live`) plus `draining: true, compacted: <n>`; the reconcile waits.
Otherwise the body is the existing one, byte for byte. `world.stats_now()` stays correct throughout (base + Σ journal, and the
compaction preserves Σ). At 300 k rows a run the 2.1 M backlog takes 7 runs (~1.75 h).

### 4.6 Indexes (plain `CREATE INDEX`: only the count writes these tables; the cron's own `lock_timeout 2s` makes the one run
that overlaps the build fail fast)

```
create index stats_good_at      on public.stats_good (at);
create index stats_good_slot    on public.stats_good (slot);
create index stats_good_day     on public.stats_good (slot) where day is not null;
create index stats_city_at      on public.stats_city (at);
create index stats_city_slot    on public.stats_city (slot);
create index stats_city_day     on public.stats_city (slot) where day is not null;
create index stats_city_good_at on public.stats_city_good (at);
```
(`stats_fold_day`'s three `update … set day = null where slot < p_slot and day is not null` then touch ~565 rows through the
partial indexes instead of scanning the tables. If you find a read that wants another index, add it WITH its measurement; if
one of these turns out unused by the folds and by `stats_fold_day`, drop it from the file before the PR.)

### 4.7 Not changed

The cron job and its schedule; `drift_slot_seconds`; `STATS_LIVE_MS`; `world.stats_now()`; `world.stats_overview` and every
`stats_window_*` function; `stats_merchants_window` (its phase stays ~12 s, now index-only); the journal's writers; the
client. No existing knob changes value. No function outside the five named above is touched (md5-unmoved, as 0287 asserts).

## 5. The self-assert (rolled back) — what must be proved, and the traps

Prove each bound with the seam that owns it:
(a) catalog: knobs with their defaults, the marks table (RLS on, no client grant), the seven indexes valid/ready/live with the
exact columns and predicates (read from `pg_index`, never a planner choice), the new functions' ACL (server-only) and
volatility; every other function in public/cmd/world/voyage md5-unmoved (0287's technique); the registry and walls as found.
(b) `stats_window_start`: gap under the cap → unchanged; gap over → capped; `tick_stats` end to end: `since` = the cap,
`skipped` = `{from, to}`; under the cap `skipped` is null.
(c) `stats_compact` on probe rows dated 2004 (no real row is ever there), marks planted in 2004: with K+3 hourly buckets of
two rows each, one call folds exactly `stats_fold_batch_hours` buckets and moves the mark by exactly that; the next call the
next batch; a last call folds nothing; the same for the day tier; with `stats_budget_secs` set to 0 inside the probe it returns
`late: true`, removes nothing and leaves the marks. The ABSENT-mark rule: plant a probe `stats_world` row with a slot above
every real one and an `at` in 2004, no marks → the first fold range starts at `bucket(that at − fine, 'hour') − 1 h`.
(d) `stats_live_compact` on a TEMP table of the journal's shape: Σ of every column unchanged, row count = n − p_rows + 1,
the returned count right, `p_rows` ≥ n leaves one row. `stats_live_fold`: with `stats_live_batch_rows` set to 1 inside the
probe it returns `draining: true`, `folded: 0`, and `public.stats_live` is unchanged.

**Traps (each has bitten this chain):**
- The real journal has ~2.1 M rows and gains ~19 a second WHILE the push runs: never scan, count, sum or lock it in a probe,
  and never run the full `stats_live_fold` on it. (A `limit batch+1` probe and a 1-row compaction are cheap.)
- Real stats rows exist (stats_city_good 566 k): probes use 2004 dates and bounded ranges only; no assert that counts or sums
  a growing table or compares a rollup against live.
- A full `tick_stats` on prod volume inside the push is a minute of work. Test the cap through `stats_window_start` and keep
  the end-to-end tick probe to what is cheap (measure it; if it is more than ~20 s on a prod-sized world, drop it).
- Timing is never asserted (the repo's rule); the lateness test sets `stats_budget_secs` itself.
- Nothing is deleted from append-only tables; clean-up is by rollback.

## 6. Gates (lean, local; CI is the full proof)

`npx tsc -b`, `npx eslint` on touched files, `npm run build` (local-mode, `.env.local` is not in a worktree anyway),
`node scripts/db/check-versions.mjs`, `BYEHARU_PREFIX_CACHE=required node scripts/db/proof.mjs standing` (the chain
through the prefix cache — NOT a from-zero replay), `npx playwright test tests/duplication.spec.ts tests/rpc.stats.spec.ts`
against the built world image. Run each ONCE. Then push once and open the PR; watch `gh pr checks` (ALL checks).

## 7. Prod checks (read-only, one pure SELECT per file, run BEFORE the PR; put the results in the PR body)

Head = `20260818000289`; the live md5s above for `tick_stats`, `stats_compact`, `stats_live_fold` (re-read them: they are the
pre-images) and for the untouched `stats_fold` `fd5cbeb86419b50512426819505a14f8`, `stats_fold_day`
`d148c7e5529853daabd3e68382a25061`, `world.stats_now` `00b70324f22fd246657281acdabf18a4`; the five knob keys, the marks table,
the seven index names and the new function names are all absent; the 2004 probe keys are absent from every stats table.

## 8. After-check (the coordinator, 30 min, read-only)

1. The next `:06/:21/:36/:51` run: `cron.job_run_details.status = succeeded`; `stats_world`'s newest `at` advances;
   `stats_runs.receipt` shows `skipped` (the 43 h span), `phases`, and `fold.late` absent.
2. The journal falls by ~300 k rows a run (`stats_live_compact` working) until it is one slot's worth; then
   `world.stats_now()` answers in well under a second.
3. `stats_fold_marks` rows advance by 4 hours / 1 day a run until they reach the edges.
4. Every later run: < 60 s, no failure for 24 h. The other crons' durations (drift, compact) do not rise.
Forward rollback: `drop index` the seven indexes and re-create the three functions from their pre-images (md5-asserted).

## 9. Not in this slice (queued — do not touch)

- **main is RED** on the full suite since `fe610dd0` (#440): `consistency.spec.ts:379` (`desk/City: sideways scroller
  desk-city (367/358)` at 390), `consistency.spec.ts:568` (HQ at 320: expanded book scrolls 35 px, floor 12),
  `market.desk.spec.ts:34` (a disabled button's figure blocks the first trade-row click at 390). A separate slice.
- `public.port_goods`: heap 293 MB for ~157 k live rows (≈12× bloat), HOT-update ratio 33 %, no `fillfactor`; its drift
  rewrite is the biggest dirtier (37 s a minute). A separate slice (rewrite + `fillfactor`), after this one.
- Compute size (Micro): the owner's decision.

## 10. Bookkeeping

Update this file with the gates and measurements; the matching row in `docs/OWNER_REQUESTS.md` (state only; find the Stats
rows 250/255); one line at the top of `docs/WORK_QUEUE.md`. PR title: `MIGRATION — 0290: the count keeps to a budget (deploy
AFTER 0289)`; body = PROD CHECKS + the before/after table; ends with the Claude Code line. Commit trailer:
`Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.

---

# Built (2026-11-01, `stats-budget`) — what shipped, what differs from the design, the gates, the prod checks

## 11. What the file is

`supabase/migrations/20260818000290_the_count_keeps_to_a_budget.sql` (prod head `20260818000289` re-read before writing; no renumber).
As §4, in this order: guard · as-found (the three pre-images, **every** function's md5 in public/cmd/world/voyage, the knobs' md5) · the five
knobs · `stats_window_start` / `stats_late` / `stats_live_compact` · `stats_fold_marks` (RLS on, `revoke all` from public/anon/authenticated,
comment naming its one writer) · the seven indexes (§4.6, each with a comment) · the hunks (`tick_stats` ×3, `stats_live_fold` ×1, each asserted
to occur once in the live body) · `stats_compact` re-cut whole (`create or replace`, the supersede declared in the header) · the self-assert.

**Self-assert, all in rolled-back sub-transactions, every probe row in 2004 or 40 days ahead (nothing real is read by value):**
- **(a) as found:** the five knobs read 120 / 4 / 1 / 300000 / 60 and are described; every other knob unmoved (md5 of the rest of `world_config`);
  the marks table is server-only (RLS, no anon/authenticated privilege), keyed `(tbl, unit)`, its unit check bites; the seven indexes read from
  `pg_index` (table, key column, predicate, valid/ready/live, one btree key, no INCLUDE, not unique); the three seams are server-only with the
  intended volatility; the four hunks reverse to the pre-images; the three re-cuts keep ACL/volatility/definer/config; **every other function
  md5-unmoved: the set of functions that differ is exactly the three re-cuts plus the three new seams** (670 functions locally); registry and
  both owner switches as found; walls 0 / 0 / 0.
- **(b) the cap:** `stats_window_start` at 30 / 120 / 43-hour gaps and with the knob at 60; then **one real `tick_stats`** at `now() + 40 days`
  (so its flow window, its 24 h laps window and its fold are empty/the probe's; what is left is the count's fixed phases) five hours after a
  planted previous count: `since` = p_now − 120 min, `skipped` = `{from: p_now − 5 h, to: p_now − 120 min}`, `stats_runs.receipt.skipped` equals
  it, `fold` not late, the planted marks moved by exactly one batch; and the **live `tick_stats` body cut right after the cap**, asked 15 minutes
  after that count: `skipped` is JSON null and `since` is that count's `at`.
- **(c) the fold:** *no marks*: the first range is `[bucket(last count BEFORE this one − window) − 1 h, +4 h)` — a probe count's own row at P and
  the previous count at P − 9 days; rows in the hour before and the hour after the range are untouched; all eight first marks asserted
  (including the day edge lifting the hour tier of `stats_city_good`). *marks planted*: budget 0 → `late: true`, nothing removed, every row and
  mark as planted; then five calls: the first folds exactly 4 world hours (05–08 of seven) and 1 of 4 good days, marks move by exactly the batch
  and never past an edge (all eight marks asserted), the good's hour mark (planted below the day edge) lifts above it; calls 2–4 fold the rest
  (3 hours, then a day each); call 5 folds nothing; Σ minted and Σ n unchanged.
- **(d) the journal:** `stats_live_compact` on a TEMP table of the journal's shape — 4 of 10 rows become one (newest `at`, every figure the sum),
  Σ of every column unchanged, count = n − p_rows + 1, returned number right; p_rows ≥ n leaves one row; 1 row / 0 / null change nothing; an empty
  table invents no row. `stats_live_fold` with `stats_live_batch_rows` = 1 on the **real** journal (three planted rows so any world is "over"; a
  limit-2 test and a ONE-row compaction, rolled back): `draining`, `folded` 0, `compacted` 1, `public.stats_live` untouched; at budget 0
  `compacted` 0.

**Mutation controls (the asserts can fail):** 24 in-memory mutations of the file, each applied to the chain and each caught by the assert meant
for it — the count's own row taken as "the last count"; no batch bound on the hour tier; no day-edge lift; a day tier that may pass its edge;
`stats_late` never late; the fold ignoring lateness; a batch one hour too long; a compaction that loses a column / does not insert / replaces a
fixed 1 row; a drain that compacts nothing / reports `draining: false` / counts the whole journal; the cap gone / ignoring its knob / `skipped`
not returned / `skipped` set under the cap; an unrelated function moved; the marks table readable by a client; a seam open to `anon`; an index on
the wrong column / without its predicate; a day tier that does not write its mark. (Scratch harness, not in the repo.)

## 12. Where this differs from §4–§5, and why

1. **"The last count" is the newest `stats_world` row BEFORE `p_now`, not the newest row.** `tick_stats` inserts this run's own `stats_world`
   row long before it calls `stats_compact`; "the newest `at`" is therefore `p_now`, which would set the first marks to the CURRENT edge − 1 h and
   the 44-hour backlog would never be folded (a mark only moves forward). `stats_compact` reads `max(at) where at < p_now` (null → `p_now`).
   The (c) probe plants both a previous count and the count's own row and proves the range follows the former. (§5(c) said "a probe row with a
   slot above every real one": not needed once the rule is by `at`.)
2. **`stats_late()` is `>=` the budget, not `>`.** A budget of 0 is then late at any clock resolution (PGlite's clock is not a microsecond one);
   otherwise identical.
3. **`tick_stats` hunk 1 declares two locals** (`v_start`, `v_skip`), so the cap calls `stats_window_start` once.
4. **(b) runs ONE real count, not two.** A real count even at `now() + 40 days` still pays its fixed phases (pre-spiral prod receipts:
   `recent` 1.9–5.0 s, `city_goods` 1.7–2.8 s, `world` 0.7–1.5 s, `goods` 0.6–0.9 s, `cities` 0.3–0.4 s ≈ 7–11 s on prod volume, an estimate: a
   VOLATILE count cannot be run on prod to measure it); a second would double it, so "under the cap → null" is proven on the live body cut after the
   cap. Locally the real count takes 370 ms (PGlite, tiny world). If the coordinator wants it gone from the push, drop the `tick_stats(v_p1)`
   block in `$probe_b$` and keep the cut-body case.
5. **Prod check "2004 probe keys absent":** `stats_world` / `stats_merchants` by `at`; for the three big tables (no index on `at`: that is
   this slice) by the **slot windows a 2004 probe row would carry** (`drift_slot_of` of a 2004 instant is `[1,192,128, 1,227,264)` at 900 s a slot
   and `[17,881,920, 18,408,960)` at 60 s), one primary-key range probe per good/port. A first version OR-ed the two windows in one statement, ran
   past 120 s on the saturated database and was stopped from the client; `pg_stat_activity` afterwards showed it no longer running. Nothing was
   written.
6. **`docs/WORK_QUEUE.md` is not edited** (coordinator's instruction while several PRs are in flight); row 256 of `docs/OWNER_REQUESTS.md` is.

**A fact worth knowing, found on the way:** the slot numbering changed on 2026-10-30 ~00:35 when the every-minute market went live: before it a
slot is 15 minutes (`stats_world.slot` 1,991,711 at 2026-10-20 23:51), after it a minute (29,889,726 at 2026-10-30 18:06), because
`drift_slot_seconds` went 900 → 60. Everything in this file is keyed on `at`, never on slot arithmetic across that line; `max(slot)` of a bucket is
still its latest row because the new slots are larger.

## 13. Gates (local, each run once on the final file; the migration was not touched after the proof run)

| gate | result |
|---|---|
| `npx tsc -b` | clean (6.4 s) |
| `npx eslint` on touched files | no `.ts` / `.tsx` / `.js` / `.mjs` file is touched (SQL and markdown only): nothing to lint |
| `node scripts/db/check-versions.mjs` | 278 migrations, 278 distinct versions, no collisions, positive control fired |
| `BYEHARU_PREFIX_CACHE=required node scripts/db/proof.mjs standing` | 277 restored from the prefix cache (2.9 s), 1 applied (mine); **278 / 278 with a self-assert receipt (289 receipt lines)**; world-guard ok; `11_standing_route` 5/5 PASS; never a from-zero replay |
| `npm run build` | clean; world image built from the prefix cache (277 restored, 1 applied, certified, 17.86 MB, chain `9284ab4027060e90-278-130530a`) |
| `npx playwright test tests/duplication.spec.ts tests/rpc.stats.spec.ts` | **18 passed, 0 skipped, 0 failed** (11 + 7) in 9.4 s against the built world image; `vite preview` on port 4417 at `localhost`, trailing slash, stopped afterwards |

Local measurements (PGlite 18, tiny world): the whole self-assert 509 ms; the real end-to-end count 370 ms; the migration applied on the
277-file snapshot in 2.9 s + 0.5 s.

**Are all seven indexes used?** (the brief: drop any that is not.) Checked in a scratch PGlite with the migration applied and prod-shaped tables
(`stats_good` 199 k rows, `stats_city` 127 k, `stats_city_good` 504 k; minute-numbered slots; `day` on the newest slot only; `analyze`; plans only,
`explain (costs off)`, nothing run on prod): `stats_good_at` / `stats_city_at` / `stats_city_good_at` — the Bitmap Index Scan under `stats_fold`'s
group read and its delete (a 4-hour range); `stats_good_slot` / `stats_city_slot` — `stats_fold_day`'s 24 h range read and its `n.slot = p_slot`
update; `stats_good_day` / `stats_city_day` — the `set day = null where slot < p_slot and day is not null` update, which reads the ~565 / ~246 rows
that carry `day` instead of the table. **All seven are chosen; none dropped.**

## 14. PROD CHECKS (read-only, 2026-11-01 ~14:00 UTC, before the PR; the SQL files are in `~/dev/prodcheck-2026-11-01-0290/`)

| check | result |
|---|---|
| head | `20260818000289` (277 migrations) |
| the six md5s (LF-normalised `pg_get_functiondef`) | `tick_stats` `d2e72eede1406c36a08dc08b99caf604` · `stats_compact` `6ae5bf23fc0fe2ddb848ce9c693a32e3` · `stats_live_fold` `baa36db2387718e4173c6d8cfcebcc7f` · `stats_fold` `fd5cbeb86419b50512426819505a14f8` · `stats_fold_day` `d148c7e5529853daabd3e68382a25061` · `world.stats_now` `00b70324f22fd246657281acdabf18a4` — **all six equal §7**; the first five VOLATILE definers with `{postgres, service_role}` EXECUTE, `stats_now` STABLE with `authenticated` |
| absent | all 16: the five knobs, `stats_fold_marks`, `stats_window_start`, `stats_late`, `stats_live_compact`, the seven index names |
| existing knobs | `stats_fine_hours` 72 · `stats_city_good_fine_hours` 48 · `stats_hour_days` 30 · `stats_city_good_hour_days` 7 · `stats_fold_back_days` 14 · `drift_slot_seconds` 60 · `game_day_seconds` 60 |
| existing indexes | the five stats tables, `stats_live`, `stats_runs`: primary keys only; none on `stats_live_deltas` |
| 2004 probe keys | `stats_world` 0, `stats_merchants` 0 (by `at`); `stats_good` 0 / `stats_city` 0 / `stats_city_good` 0 in both slot windows (see §12.5) |
| the count | cron `byeharu-voyage:stats` `6,21,36,51 * * * *` active; last 24 h: **92 failed, avg 118.7 s, 0 succeeded**, one running; `stats_world` 384 rows, newest slot 29,889,726 at `2026-10-30 18:06:00.094397+00` |
| sizes (estimates) | `stats_live_deltas` 1,895,801 rows / 250 MB · `stats_city_good` 565,223 / 221 MB · `stats_good` 218,488 / 69 MB · `stats_city` 92,518 / 43 MB · `stats_runs` 168 rows |
| the last good runs (`stats_runs`, 10-30 16:51–18:06) | `merchants` 11.1–13.2 s · `fold` 8.8–9.8 s (32.6–34.0 s on the hour) · `day` 4.2–7.9 s · `recent` 1.9–5.0 s · `city_goods` 1.7–2.8 s · `world` 0.7–1.5 s · `live` 0.6–1.4 s · `goods` 0.6–0.9 s · `cities` 0.3–0.4 s; totals 34–35 s (61–63 s on the hour) |
| the database right now | `pg_stat_activity` showed `tick_market_drift_each_port` active 107 s waiting on `WALWrite`, `tick_arrivals_each_second` 33 s on `WalSync`, `tick_lap_starts` 41 s on an advisory lock, `tick_compact` 14 s on `DataFileWrite`: write-I/O saturated, which is why this file adds no write the count did not already make and the push's own probe is one count at an empty window |

## 15. What the first runs after the deploy should show (for the §8 after-check)

- **First run (the first `:06/:21/:36/:51` after the deploy):** `stats_runs.receipt.skipped` = `{from: 2026-10-30 18:06:00.094397+00, to: p_now − 120 min}`
  and `since` = `to`; `fold` without `late`; `phases` whose `merchants` is the one remaining long phase (~12 s, index-only since 0287).
- **Marks after run 1** (eight rows in `stats_fold_marks`): hour — `stats_world`, `stats_merchants`, `stats_good`, `stats_city` `2026-10-27 21:00`,
  `stats_city_good` `2026-10-28 21:00`; day — `stats_good`, `stats_city` `2026-09-30`, `stats_city_good` `2026-10-23`. Each later run moves each
  hour mark by 4 hours (to the edge, where it then moves an hour per hour) and each day mark by 1 day (to its edge).
- **The journal:** `stats_live_deltas` (estimate from `pg_class` / `pg_stat_user_tables`, never a count) falls by ~300,000 a run; at ≤ 300,000
  the next run runs the full reconcile (`live.folded` > 0, `draining` absent) and `world.stats_now()` answers in milliseconds.
- **Forward rollback** (unchanged from §8): `drop index` the seven, re-create the three functions from their pre-images (the hunks' OLD text is in the
  file; `stats_compact` is 0246's), drop the marks table and the five knobs.
