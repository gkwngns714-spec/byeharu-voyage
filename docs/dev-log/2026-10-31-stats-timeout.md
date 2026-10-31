# 2026-10-31 — 0287: the Stats read touches only the rows it serves

**Branch** `stats-perf` · **migration** `supabase/migrations/20260818000287_stats_reads_fast.sql` ·
**spec** `tests/rpc.stats.spec.ts` (a 1d / 1w overview test added) · **owner row** 255 ·
**deploy** the coordinator, AFTER 0286 (`report-0286`) — one migration at a time, in number order.

## 1. The symptom and the assigned bug

The Stats face shows **"World figures not loaded."** (`src/lib/i18n/dict/stats.ts:22`). The read under
it is `world.stats_overview(24, '1d')` / `(24, '1w')`, 0232's count plus the minutes since it, through
`public.stats_window_totals` → `public.stats_window_trades` (the stack the brief measured:
`57014 canceling statement due to statement timeout`).

Everything below was measured **read-only on prod** (head `20260818000285`), each block in
`begin transaction read only`, the plain-table scans with `EXPLAIN (ANALYZE, BUFFERS)`; the probe SQL
files are in `~/dev/prodcheck-2026-10-31/`.

## 2. The measured state

- **The count is dead and its window grows.** The last successful count is
  `2026-10-30 18:06:00.094397+00`; at 11:58 UTC today it was **64,368 s (17.9 h)** old, at 12:22
  **65,781 s**. The stats cron (`6,21,36,51 * * * *`) has **71 failed runs** in 24 h, every one
  `canceling statement due to statement timeout` at **120.2 s**. The first failure (18:21 on 10-30) is
  inside the merchants insert, `public.stats_merchants_window` — its **24-hour** window of closed laps;
  a later run ran out of time in the city-good insert first.
- **Why the window never shrinks:** `tick_stats` reads `v_prev_at` from the last *successful* row
  (`public.tick_stats`: `select w.at … order by w.slot desc limit 1`), so one miss doubles the next
  window, and the next run is heavier still. The read's `(last count, now()]` window is therefore
  **17.9 h**: **228,565 events** (the whole live events table; **24,953** are SOLD / BOUGHT),
  **183,861 ledger rows** (FOUNDING / NPC_REFOUND: none), **5,648 treasury flows**, 384 stats rows.
- **The journal is un-folded:** `public.stats_live_deltas` holds **1,005,498 rows** (the count has not
  run since 18:06).
- **The tables:** events 234,290 live rows / 359 MB heap; ledger 263,036 / 80 MB; standing_route_laps
  167,359 rows / 238 MB heap (1,196 laps in the last hour, ~28,700 in 24 h); treasury_flows 5,420.

### Measured timings (before)

| piece | measured |
|---|---|
| `world.stats_now()` | **17.5 s** (Σ 1,005,498 journal rows — the count backlog, not this read's plan) |
| `public.stats_window_kinds` | 4.7 s |
| `public.stats_window_founded` | **26.4 s** (Bitmap Heap Scan on ledger: 183,861 rows read, 0 kept) |
| `public.stats_window_flows` | 2.0 s |
| `public.stats_window_totals` | 4.3 s warm / **84.7 s cold** / the events half alone **>110 s (57014)** |
| the 24 h trades SELECT | 28.9 s through `events_trades_port_good` (Bitmap Index Scan itself 24.9 s) |
| `world.stats_overview(24, '1d')` | **17.1 s** (12:23:14 → 12:23:31 UTC, answered) |
| `world.stats_overview(24, '1w')` | **>110 s → 57014** in `stats_window_trades` minutes later |
| the stats cron | 71 failures, 120.2 s each, first in `stats_merchants_window` |

## 3. The single most expensive step, and why

**`public.stats_window_trades`' events scan.** `public.events` carries `events_created_at
(created_at)` only, so the read heap-reads **every** event in the window and throws the non-trades
away: the measured plan removed **203,762 of 228,754** rows. The goods join is not the cost (a 629-row
Hash, 0.5 ms). The existing `events_trades_port_good` cannot help a `created_at` range — its leading
columns are `payload->>'port'`, `payload->>'good'` (the 24 h attempt was a bitmap scan over itself,
24.9 s). The count's own killer is the same shape on the laps table: `standing_route_laps_closed_at`
(closed_at only) heap-fetches `route_id`, `net` for ~28,700 laps from a 238 MB heap.

## 4. The fix, and why an index rather than a re-cut

**Three covering indexes; no function body is re-cut.** The same SQL reads the same rows; every served
figure is identical by construction (no arithmetic moves), which is the strongest form of "keeps every
served figure identical" available. A re-cut onto the existing count/quarter-hour tables cannot serve
the minutes *since* the count (those are exactly what is not yet rolled up) without changing figures,
and the rollup tables were themselves stale (the count is what is dead).

```sql
create index events_trades_window on public.events (created_at)
  include (id, kind, player_id, payload) where kind in ('SOLD', 'BOUGHT');
create index ledger_founded_window on public.ledger (created_at)
  where kind in ('FOUNDING', 'NPC_REFOUND');
create index standing_route_laps_window on public.standing_route_laps (closed_at)
  include (route_id, net, lap_no) where lap_no >= 2;
```

- `events_trades_window` — the read's window (and every `stats_window_*` that shares it, and
  `stats_live_fold`'s trade query) scans ~25.4k covering entries instead of 228k heap rows. All 25,360
  live trade payloads were measured on prod: the newest 5,000 average 372 bytes, the maximum is 460 —
  the index is a few MB, not a copy of the heap.
- `ledger_founded_window` — the founded window holds only founding rows, where the old plan read
  183,861 ledger rows to keep none.
- `standing_route_laps_window` — the count's 24 h merchants window is an index-only scan of the laps
  it sums instead of ~28,700 heap fetches; **this is the step that revives the count**. With the count
  current the read's window returns to minutes and `stats_live_deltas` folds to its one-slot size,
  which is what makes `stats_now` cheap again.

**Said plainly:** the one-time backlog (1.0 M journal rows, 17.9 h of events) is folded by the next
successful count. This file makes every other step cheap and lets the count complete; see §7 for the
one write that clears the backlog under a longer statement_timeout if the cron's 2 minutes cannot.

## 5. What the migration proves (self-assert, rolled back)

- **(a)** the read path exists; **every function in `public/cmd/world/voyage` is md5-unmoved** (663
  functions), each read-path function's ACL / volatility / definer / config as found; the registry
  (81 entry points) and the walls (0 client write grants / 0 executable writers / 0 caller-evaluated
  functions) as found; both owner switches (`economy_closed`, `city_treasury_enabled`) read back as
  found.
- **(b) without the indexes:** probe rows at fixed instants on **2004-06-01** (no real row is ever
  there) — four trades (2 SOLD, 2 BOUGHT), five city flows, two ledger mints — read through
  `stats_window_trades / _totals / _goods / _city_trades / _city_goods / _cities / _flows / _founded /
  _kinds`, every figure asserted against its hand-computed amount (sold 1600, bought 500, units 25,
  trades 4; the good 15 / 10; the city income 530, spending 1600, taxes 30, sold 15, bought 10; kinds
  SELL -1600, BUY 500, TAX 30, FOUNDING 500, NPC_REFOUND 300). Rolled back and asserted gone.
- **(c)** the three indexes exist, valid, partial, with their key and INCLUDE columns.
- **(d) with the indexes:** the same probe answers **byte-identically** to (b); the read's events
  query, the founded query and the merchants query plan (seq scans discouraged) through
  `events_trades_window` / `ledger_founded_window` / `standing_route_laps_window`.
- **(e)** `world.stats_overview(24, '1d')` and `(24, '1w')` over probe count rows planted ten days
  ahead answer with every section — holders adding to their four parts, period, day, a series ending
  at the read's own `now()` — and the measured ms are printed. On the probe world: **1d 6 ms, 1w
  2 ms** (prod before this file: 17.1 s and >110 s / 57014).

## 6. The before / after table

| step | before (prod, 2026-10-31) | with 0287 |
|---|---|---|
| the read's events window | 228,565 heap rows read, 24,953 trades kept, 203,762 discarded; 4.3 s warm / 84.7 s cold / the events half >110 s | partial covering index: ~25.4k entries, payload max 460 B |
| the founded window | 183,861 ledger rows read, 0 kept; 26.4 s | partial index: founding rows only |
| the flows window | 5,648 rows, 2.0 s | unchanged (`treasury_flows_created_at`) |
| the 24 h series | 0.19 s | unchanged (stats_world, 384 rows) |
| `stats_now` | 17.5 s over 1,005,498 journal rows | the count's fold empties the journal; then 0224's one-row read |
| `stats_overview(24, '1d')` | 17.1 s (answered), 57014 when cold | 6 ms on the probe world |
| `stats_overview(24, '1w')` | >110 s, 57014 | 2 ms on the probe world |
| the count (every 15 min) | 71 failures, 120.2 s, first in `stats_merchants_window` | the 24 h laps window is index-only; the next run recovers the count |

The probe-world ms are PGlite numbers; prod's after values are the after-check's (§7). The strict
recovered budget (< 3 s) is `stats_now` (milliseconds once the journal folds) + the window functions
(index scans) + the 384-row series; the calls answer inside the API's own 120 s wall at deploy time
even with the backlog, which is the property (e) asserts.

## 7. Deployment and the after-check

Deploy **after 0286** with `~/bin/bv-deploy.sh <pr>` (the script pushes, then merges). The three
`CREATE INDEX` statements take SHARE locks on events / ledger / standing_route_laps until the commit;
the build scans the events heap once (359 MB) — the deploy's own cost, 0264's shape. No body, row,
column, grant, knob or switch moves.

**After-check (30 min, read-only):**

1. The next `:06/:21/:36/:51` stats run: `cron.job_run_details` status `succeeded` and
   `public.stats_world`'s newest `at` advances; `public.stats_runs.receipt.phases` names the phases.
2. `public.stats_live_deltas` falls from 1,005,498 to a slot's worth (the fold).
3. `world.stats_overview(24, '1d')` and `(24, '1w')` answer; time them (`clock_timestamp()` around the
   call in a read-only transaction); the recovered budget is < 3 s.
4. The indexes: `pg_index` shows the three valid; `pg_stat_user_indexes` shows the read using them.

**If the first post-deploy stats run still times out** (the 1.0 M-row journal fold is a one-time cost
the cron's 2-minute statement_timeout may not carry), the coordinator runs the one write below after
the deploy has finished (the clock wound). It is the count's own job, once, with a longer budget:

```sql
begin;
set local statement_timeout = '10min';
select public.tick_stats();
commit;
```

`public.tick_stats()` writes the catch-up row (18:06 → now), folds the journal and the day; the cron
then continues from a current count. No figure is skipped: the row covers the whole gap.

**Forward rollback:** `drop index public.events_trades_window, public.ledger_founded_window,
public.standing_route_laps_window;` — nothing else was written (a new migration, never an edit).

## 8. The gates

- `node scripts/db/check-versions.mjs` — **274 migrations, 274 distinct versions, no collisions.**
- `BYEHARU_PREFIX_CACHE=required node scripts/db/proof.mjs standing` — **274/274 migrations with a
  self-assert receipt (281 receipt lines), world-guard ok, 11_standing 5/5.**
- `npx playwright test tests/duplication.spec.ts` — **11/11.**
- `npx tsc -b` / `npx eslint tests/rpc.stats.spec.ts` / `npm run build` (which emits the world image
  from the prefix cache: 273/274 restored, 1 applied, certified) — **clean**.
- `tests/rpc.stats.spec.ts` — the new test `a 1d and a 1w overview answer with the sections and
  holders intact` (both spans, span echoed, holders adding up, period/day present with every figure,
  the series ending at the read's own `now()`): **7/7 PASS in 26.3 s** against the built world image
  (`world-a810220af1b75733-274-12de99a.tar.gz`). CI selects the spec by rule C on the changed file;
  main's own Acceptance after the merge is the full-suite net.

## 9. PROD CHECKS (read-only, before the push; the SQL files are in `~/dev/prodcheck-2026-10-31/`)

Head `20260818000285`; the count's age, the cron failure count and the first failure above; the row
counts above; the indexes the read touches today: `events_created_at (created_at)`,
`events_trades_port_good ((payload->>'port'), (payload->>'good'), created_at desc) WHERE kind SOLD/BOUGHT`,
`ledger_created_at (created_at)`, `standing_route_laps_closed_at (closed_at) WHERE closed_at IS NOT NULL`,
`treasury_flows_created_at (created_at)`; **no `goods(name)` index** (the goods join is a Hash, not the
cost).

The read-path functions are all `provolatile = 's'` and are **not touched** by this file; live md5s:

| function | md5 |
|---|---|
| `public.stats_window_trades` | `d3ebbc0d34cc2dc791f0fadeecbcbb1b` |
| `public.stats_window_totals` | `c7430ee2e823725dea55dffcb6d2e2ff` |
| `public.stats_window_goods` | `1c0dec1293487dc99d404505852458a2` |
| `public.stats_window_city_trades` | `bb04c5b2326546c863aa4dc389ff0a37` |
| `public.stats_window_city_goods` | `122877da70695024500aa036df741e78` |
| `public.stats_window_flows` | `ebe33fb32bc25d91e3ed356ffc4b286c` |
| `public.stats_window_cities` | `390bf30b9d6b3e4d81d4d5bf8b897be4` |
| `public.stats_window_founded` | `71f490e4df115a0a11bbedf94f4940a2` |
| `public.stats_window_kinds` | `8cb058f19420448d1e0f11bf0e44f9c2` |
| `public.stats_merchants_window` | `f97b5919010fe8fc001d88e8c633644d` |
| `world.stats_overview(int, text)` | `efc9be0bc59bed0c44ec9258d30b5bfe` |
| `world.stats_now()` | `00b70324f22fd246657281acdabf18a4` |
| `public.stats_live_fold` (volatile, untouched) | `baa36db2387718e4173c6d8cfcebcc7f` |

After the push (the coordinator's step): `pg_index` has the three new indexes valid and
`pg_stat_user_indexes` shows them scanned; the count recovers at the next quarter hour; the read
answers in seconds, then under the recovered budget once the journal folds.

## 10. Files

- `supabase/migrations/20260818000287_stats_reads_fast.sql` — the three indexes + the self-assert.
- `tests/rpc.stats.spec.ts` — the 1d / 1w overview test.
- `docs/OWNER_REQUESTS.md` — row 250.
- `docs/WORK_QUEUE.md` — one line at the top.
- This file.
