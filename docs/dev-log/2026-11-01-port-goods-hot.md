# 2026-11-01 — 0291: the market table is rewritten compact, with room for in-page updates

**Branch** `port-goods-hot` · **migration** `supabase/migrations/20260818000291_the_market_table_keeps_room.sql`
(number = prod head + 1 AT THE TIME OF DEPLOY; this file assumes 0290 — `stats-budget`, the Stats count — is live first.
Deploy one migration at a time, `~/bin/bv-deploy.sh <pr>`, by the coordinator. Do NOT open the PR until the coordinator says
0290 is merged and main's snapshot run has finished: the chain law.)

**Status, 2026-11-01 14:45 UTC — the migration is written and gated locally (§8); prod was re-read (§5); the PR is NOT opened.**
**Fillfactor is 30, not the 40 of the first design** (the coordinator's decision, 2026-11-01, by default: the extra ~22 MB of heap buys
100 % HOT updates even while a long snapshot pins a second generation of versions — §8). Corrections to the first design (a different
row count, two settings the design lacked, the clock order) are marked **CORRECTED** below and listed in §8.

## 1. Why — measured read-only on prod (first reading 2026-11-01 ~13:30–13:55 UTC; RE-READ 14:13–14:30 UTC, §5)

The every-minute market (owner-directed, "nothing regarding time") rewrites ~155 k `public.port_goods` rows a minute
(`tick_market_drift`, one UPDATE per row since 0289). The TABLE is the problem, not the cadence:

| fact | measured (the re-read; the first reading's figure in brackets where it differed) |
|---|---|
| live rows | **154,734 exactly** (246 ports × 629 goods; no insert or delete since the server started at 09:34 UTC). **CORRECTED** [the first design said 155,344, an estimate; `pg_class.reltuples` and `n_live_tup` say 155,155]. ~123 B of data a row (`pg_stats` average widths) + 24 B header ≈ 22.6 MB of live data |
| heap | **293 MB** (307,044,352 B = 37,481 pages) — ~13× bloat; 3 indexes 36.2 MB (37,961,728 B) |
| dead tuples | 84,638 at 14:14:19 [149 k at the first look]; autovacuum has run 162 times on it, the last at 14:13:19 |
| HOT updates | **33.4 %** of 39.1 M updates since 09:34 (13.06 M HOT; every other update, 26.06 M, went to a NEW page); 33.1 % of 41.2 M at 14:29:52. Two thirds of the updates also write 3 index entries |
| `reloptions` | none (fillfactor 100) |
| the drift job | `pg_stat_statements`, 260 calls since 09:44: mean **37.6 s**, max 118.9 s (the 120 s wall); per call 3,928 blocks dirtied, 3,558 read, 50.9 MiB of WAL (1,775 full-page images) — the biggest dirtier in the database [221 calls: 3.95 k / 3.7 k] |
| whole-DB WAL | **61.8 MiB/min** over 283 min (17,495 MiB, 2,058,184 full-page images) — one 8 KB image for every page of this table after every checkpoint |
| cron, hourly means (UTC) | drift 17.8 s (08:00) → 42.6, 38.4, 39.1, 41.5, 43.1, 51.3 s (14:00), max 120.4 s, 13 timeouts since 10:00; compact 3.2 → 23.5 s (max 92.4); price-snapshot 3.8 → 35.3 s |
| compute | PG 17.6; shared_buffers **256 MB** (32768 × 8 kB), effective_cache_size 768 MB, max_connections 60, maintenance_work_mem 64 MB, **statement_timeout 120 s** (not in the first design), wal_level logical: a 293 MB table plus 36 MB of indexes never stays cached |

Why only 34 % are HOT: no indexed column is updated by the drift (the indexes are `(good_id)`, `(port_id, good_id)` and the partial
`(port_id, good_id) WHERE haul_nm = 0`; the drift writes `drift`, `stock`, `drift_slot`, `updated_at`, …), so every update COULD be
HOT, but a HOT update needs free room on the SAME page, and at fillfactor 100 a page that is full of live rows + not-yet-vacuumed
dead versions has none. A non-HOT update leaves a dead version that its index entries pin until a VACUUM, so the room never
comes back between vacuums — a loop that only a rewrite with spare room breaks.

## 2. The design

One small migration, no function re-cut, no new knob, no cron/knob/switch change:

```
alter table public.port_goods set (fillfactor = 30);
cluster public.port_goods using port_goods_pkey;     -- rewrites heap + all 3 indexes, honours the fillfactor, puts a port's rows together
analyze public.port_goods;
```
- **fillfactor 30** (the first design said 40; decided 2026-11-01 by the coordinator, by default): 70 % of every page stays empty. That is
  ~15–16 live rows a page (15.0 measured on the chain world: 154,734 rows in 10,315 pages; 16 by prod's average widths) on a page that
  holds ~52 tuples (measured, §8). So a page takes a whole minute's new versions beside the old ones (16 + 16 ≤ 52) AND a second minute
  while a long snapshot (the Stats count, a minute-long statement) still pins the first: three versions of every row fit
  (3 × 16 = 48 ≤ 52; 3 × 15 = 45), and a buy/sell touching `stock` stays in-page too. At 40 only two versions fit (2 × 21 = 42 ≤ 52,
  3 × 21 = 63 > 52). Expected table ≈ 80 MB (vs 293 MB); the local rewrite gave 10,315 pages = 80.6 MB for the same 154,734 rows (§8).
- **CLUSTER is allowed inside a migration transaction** for a single named table (only the no-argument form refuses a transaction
  block). It takes ACCESS EXCLUSIVE on `port_goods` until the migration commits — so keep everything after it light. The coordinator's
  deploy (`bv-deploy.sh`) runs `unwind_the_clock()` first (the crons are stopped), so only player reads can wait; budget for
  roughly 10–60 s of lock on this compute (estimate; measure it, §6).
- **CORRECTED — two settings the first design did not have.** (1) The session default read on prod is `statement_timeout = 120 s`, which a
  rewrite on a saturated disk could pass: the migration sets `statement_timeout = 20min` for its own transaction (`set_config(…, true)`,
  0287's idiom). (2) The lock wait is bounded: `lock_timeout = 10s` — an unbounded wait for ACCESS EXCLUSIVE queues every reader of the
  market behind it; a refused lock rolls back clean and the deploy is simply run again (autovacuum, which runs on this table about
  every minute, is cancelled by the deadlock detector after `deadlock_timeout` = 1 s, so it does not cost the lock).
- `cluster … using port_goods_pkey` also orders the rows by `(port_id, good_id)`: the per-port drift touches one port's rows together,
  and it marks the primary key as the table's clustered index (`pg_index.indisclustered`).
**Verified before this was written** (PGlite 18.3, a scratch table; prod is PG 17.6, same code path): `begin; alter table t set (fillfactor = 30); cluster t using t_pkey; analyze t; commit;` (the first scratch check used 40; the mechanism is the same) runs inside one transaction block; `relfilenode` changes; `reloptions` = `{fillfactor=30}`; one update on the rewritten table counts as HOT in `pg_stat_get_xact_tuples_hot_updated` (1 of 1). Script: the session scratchpad `pglite-check.cjs`. **Verified again on the real chain world at 30, and as a whole-table loop (§8).**
- Forward rollback: `alter table public.port_goods reset (fillfactor); cluster public.port_goods using port_goods_pkey;` (a new
  migration, never an edit).

## 3. The self-assert (rolled back where it writes; the rewrite itself is the migration's effect)

Take `lock table public.port_goods in access exclusive mode` FIRST, read `count(*)` and a cheap order-insensitive checksum of the
key set (`count(*)`, `min`/`max` of `port_id`, `sum(hashtext(port_id::text || good_id::text))`) — `port_goods` is a fixed
catalogue (154,734 rows, no growth by play), so equality across the rewrite is a valid assert once the lock is held. After the rewrite:
(a) same count and checksum (and never empty); (b) `reloptions` carries `fillfactor=30`; (c) the three indexes exist, valid, ready and live,
same definitions as before (compare `pg_get_indexdef` text taken before), each REBUILT (a new `relfilenode`), the primary key marked
clustered; (d) `pg_class.relfilenode` of the table changed (the rewrite happened); (e) one probe UPDATE of a single real row's
`updated_at` inside a rolled-back sub-transaction: `pg_stat_get_xact_tuples_hot_updated` for the table rose by exactly 1 (a HOT update
happened), and the row is back as it was; (f) every function in public/cmd/world/voyage md5-unmoved (0287's technique), the registry
count, the walls (0/0/0) and the two owner switches as found. Never assert a size or a timing — the receipt prints them.
**CORRECTED order:** the "as found" function sweep, registry and switches are read BEFORE the lock (catalog reads only, nothing
touches the table); the count and checksum are read after it. On prod the catalog-only parts were timed read-only at 14:20:24 UTC:
registry 449 ms, write grants 27 ms, executable writers 70 ms, caller-evaluated 405 ms, the md5 sweep of 670 functions 121 ms
(≈ 1.1 s a pass; the after-pass is inside the lock window).

## 4. Gates (lean) and traps

tsc/eslint untouched (SQL only) · `node scripts/db/check-versions.mjs` · `BYEHARU_PREFIX_CACHE=required node scripts/db/proof.mjs standing`
(the chain through the prefix cache, never a from-zero replay) · `tests/duplication.spec.ts`. Results in §8. The CI world's `port_goods`
is NOT small (the chain generates the world: 154,734 rows, the same as prod); locally the whole file applied in 1.3 s (§8), in memory — only
prod's disk and load make the lock long. Do NOT edit `tick_market_drift` or anything that writes the table; the economy numbers must not
move — the rewrite changes no value.

## 5. Prod checks before the PR (read-only, one SELECT per call) — RECORDED 2026-11-01 14:13–14:41 UTC

Every call below is a pure SELECT (the registry/wall functions were checked `provolatile = 's'` first), one per `supabase db query
--linked`. **Head `20260818000289`, PG 17.6** (14:13:44; still 0289 at 14:29:52 — 0290 not yet deployed).

| UTC | what | reading |
|---|---|---|
| 14:13:56 | `pg_class` | `reloptions` NULL; relfilenode 19159; relkind r, permanent; 18 columns; no triggers, no inheritance, no publication; RLS on; owner `postgres` (= the deploy role); heap 307,044,352 B (37,481 pages); indexes 37,961,728 B; reltuples 155,155 |
| 14:13:56 | the three indexes (all valid/ready/live, none clustered) | `port_goods_good_id_idx` `CREATE INDEX … USING btree (good_id)` 13,819,904 B · `port_goods_makes_0264` `CREATE INDEX … USING btree (port_id, good_id) WHERE (haul_nm = (0)::numeric)` 262,144 B · `port_goods_pkey` `CREATE UNIQUE INDEX … USING btree (port_id, good_id)` 23,855,104 B |
| 14:14:19 | `pg_stat_user_tables` | n_tup_upd 39,123,759 · n_tup_hot_upd 13,064,570 (33.39 %) · n_tup_newpage_upd 26,059,189 · n_tup_ins 0 · n_tup_del 0 · n_live_tup 155,155 · n_dead_tup 84,638 · autovacuum_count 162 (last 14:13:19) · autoanalyze 130 |
| 14:16:57 | exact count and the migration's own key checksum | **154,734 rows**, 246 ports, 629 goods, `sum(hashtext(port_id::text \|\| good_id::text))` = 136,191,653,682 (for the record; the migration recomputes it under its lock) |
| 14:17:04 | `pg_stat_statements` `call public.tick_market_drift_each_port()` | 260 calls (stats_since 09:44:02) · mean 37,598 ms · max 118,931 ms · shared_blks_dirtied 1,021,257 (3,927.9/call) · shared_blks_read 925,115 (3,558.1/call) · wal_bytes 13,879,341,781 (50.9 MiB/call) · wal_fpi 461,590 |
| 14:17:22 | `pg_stat_wal` | wal_bytes 18,344,596,729 (17,495 MiB) since stats_reset 09:34:04.9 = **61.8 MiB/min** · wal_fpi 2,058,184 · 130,853,049 records |
| 14:17:26 | `cron.job` | 12 active jobs; drift/compact/lap-starts/arrivals `* * * * *`, price-snapshot `*/10`, stats `6,21,36,51` |
| 14:17:43 | hourly mean/max of the three cron jobs, 08:00–14:00 UTC | §1 |
| 14:17:55, re-read 14:40:44 | settings | statement_timeout 120 s · lock_timeout 0 · maintenance_work_mem 64 MB · work_mem 3.5 MB · **shared_buffers 256 MB** (`pg_settings`: setting 32768, unit 8kB) · effective_cache_size 768 MB · max_connections 60 · wal_level logical · max_wal_size 4 GB · autovacuum_naptime 60 s · I am `postgres`, not a superuser |
| 14:17:58 | functions in public/cmd/world/voyage | 670 (1.25 MB of source); md5 of all `cb9c7ef8…` (moves when 0290 lands, as it should) |
| 14:20:24 | the catalog-only asserts, timed in-query | §3 |
| 14:29:52 | postmaster start / counters | server up since 09:34:04.7 UTC; n_tup_upd 41,208,370, n_tup_hot_upd 13,632,993 (33.1 %) |
| 14:36 | `pg_roles` | `anon` statement_timeout 3 s · `authenticated` 8 s · `authenticator` 8 s + lock_timeout 8 s · `postgres` none |

**What differed from the design, and the fix:** the live rows are 154,734 (the design's 155,344 was an estimate); the design had no
`statement_timeout`/`lock_timeout` — prod's 120 s session default makes the first one necessary; the drift's calls are 260, not 221;
everything else (293 MB, `reloptions` null, the three index definitions, HOT 33–34 %, WAL 62, dirtied/read per call, shared_buffers
256 MB) reproduced. *An earlier draft of this file said shared_buffers was 320 MB — my misread of the first settings query, which
printed `setting` and `unit` glued together (`32768` + `8kB` = "327688kB"); re-read 14:40:44 UTC: 32768 × 8 kB = 256 MB.*

## 6. After-check (the coordinator, 30 min, read-only) — this alters live play's speed, so it gets its own measured window

**How to read the lock window:** `supabase db push` prints no notices, so the migration's receipt (it prints the seconds) is for the
chain logs only. On prod read the durations of this transaction's own statements from `pg_stat_statements` (utility statements are
tracked — the drift's `call …` row is one): the `cluster public.port_goods using port_goods_pkey` row (the rewrite), `alter table
public.port_goods set …`, `analyze public.port_goods`, the `create temp table table_before_0291 …` row (the count and checksum before) and the
last `do $assert$ …` row (the asserts after). Their sum is, to within milliseconds, the time ACCESS EXCLUSIVE was held (the catalog read
before the lock, `create temp table before_0291 …`, is outside it). Or sample `pg_locks` for the granted AccessExclusiveLock on
`public.port_goods` once a second during the push. Players' reads of `port_goods` wait for that time (prod's `anon` role cancels a query at
3 s and `authenticated` / `authenticator` at 8 s — read from `pg_roles` at 14:36 UTC — so a window longer than that shows as failed
market reads, with the clock unwound).

The push log shows the lock time; the first minutes after the clock is wound: drift mean/max per minute and failures; the table's
heap size and HOT ratio from the deltas of `n_tup_hot_upd`/`n_tup_upd` since the push; dirtied/read blocks per drift call; WAL MB/min;
`price-snapshot` and `compact` durations. Success = HOT share above ~90 %, heap < 100 MB (expect ~80 MB), drift mean well under its
current 37.6 s, WAL/min well below 62. If the HOT share stays low, lower the fillfactor in a follow-up migration (it is one line).
*Expectation, not measured:* the table plus its indexes (~89 MB) now fit shared_buffers (256 MB), so blocks READ per drift call should
fall towards 0; blocks DIRTIED per call may fall by only about half (every heap page is still updated each minute, in place), so judge the
slice by HOT share, heap size, drift duration and WAL, not by dirtied blocks.
**What to expect from a pin (local experiment, §8):** at fillfactor 30 a page absorbs TWO generations of not-yet-prunable versions at
100 % HOT (three versions of every row on the page); a THIRD generation pinned by a long snapshot (a Stats read of 60–120 s, the stats
count) drops to ~48 % HOT, and the next minute, once the pin is gone, is back to 100 %. So the HOT share stays high unless a snapshot
outlives about two minutes of market passes — which is what 0290 (the count's 60 s budget) is for; deploy it first, as planned.

## 7. Bookkeeping

This file completed with the gates and the local timings; one line at the top of `docs/WORK_QUEUE.md` (**the coordinator's — not edited
here**); the owner row for "the game became slower" (OWNER_REQUESTS row 259, the nearest to 256/259) has a state line added. PR title: `MIGRATION — 0291: the market table
is rewritten compact, with room for in-page updates (deploy AFTER 0290)`. Commit trailer:
`Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.

## 8. Build record — 2026-11-01, worktree `~/dev/wt-port-goods`, branch `port-goods-hot`

**Gates (each run once on the final bytes of the migration, fillfactor 30; log files in the session scratchpad `pg0291/`):**
- `node scripts/db/check-versions.mjs` — OK: 278 migrations, no collisions, all names well-formed.
- `BYEHARU_PREFIX_CACHE=required node scripts/db/proof.mjs standing` — exit 0. The chain came through the prefix cache: restored
  277/278 from `preamble-p0277` in 2.9 s, applied 1 here (0291), snapshot after 278 files (39.2 MB, round trip verified), 278 of 278
  with a `self-assert ok:` receipt (285 receipt lines), 8.5 s for the whole chain step; world-guard ok (246 harbours, 629 goods,
  154,734 market rows); `11_standing_route.sql` 5/5 PASS.
- `npx playwright test tests/duplication.spec.ts` — 11 passed (1.1 s) (it reads the migrations off disk: the DO block, the
  `0291 self-assert FAIL` raise, the `0291 … self-assert ok` receipt).
- tsc / eslint — not run: no TypeScript touched.
- Not run locally, left to CI / the coordinator by design: `db.chain.spec`, `db.image.spec` (selected for any added migration),
  the full suite on main.
- *The first fillfactor-40 build of this file passed the same three gates (check-versions OK 278, standing 5/5 with 278 receipts,
  duplication 11/11); it was superseded by the decision for 30, and the gates above were run again on the new bytes.*

**The local self-assert wall time (PGlite 18.3, in memory, the real chain world, 154,734 rows, fillfactor 30):** 0291 applied to a
private copy of the p0277 world twice — the whole file in 1,321 ms and 1,295 ms. Under the ACCESS EXCLUSIVE lock: the read before
0.13 / 0.12 s, the rewrite (alter + cluster + analyze) 0.98 / 0.96 s, the asserts after it 0.12 / 0.13 s — **1.23 / 1.21 s in all; the
self-assert's own share (both reads, the md5 sweep of 670 functions, registry, walls, the probe) is 0.25 s** (at fillfactor 40: 0.95 s in
all, 0.19 s). Prod is native Postgres on a loaded disk: the catalog-only part of the asserts was ≈ 1.1 s there (§3); the rewrite is the
unknown (§6). (The standing-proof run's own receipt was pruned from the shared cache seconds after it was written, by another branch's
chain run, so the receipt and the timings above come from the private apply of the same file; the proof run itself exited 0.)

**The receipt (local):** same 154,734 rows and key checksum; `reloptions {fillfactor=30}`; 3 indexes valid and rebuilt; relfilenode
16832 → 163864; HOT counter 0 → 1; 670 functions unmoved, 84 entry points, walls 0/0/0; **heap 252,493,824 → 84,500,480 B (30,822 → 10,315
pages, 15.00 live rows a page, 80.6 MB), indexes 29,171,712 → 8,978,432 B.**

**Side effect on every test world (good):** the chain's own world carries bloat too (its heap was 241 MB for 154,734 rows: the chain's
own updates and no vacuum). The migration compacts it: the prefix snapshot after 0291 is 39.2 MB against
94.5 MB before it (`p0278` vs `p0277`, gzip level 1), so every restore of a world is smaller and quicker.

**Local experiment — does a whole-table update, once a "minute", stay in the page?** (scratch scripts `hot-sim.mjs` / `hot-gen.mjs`
in the session scratchpad, not in the repo; PGlite 18.3 on the p0277 world, each pass its own transaction, no concurrent snapshot —
the ideal case.) Every row updated per pass (`drift_slot`, `updated_at`, …):

| table | HOT share per pass (5 passes) | heap after 5 passes | pass time |
|---|---|---|---|
| **rewritten at fillfactor 30 (the decision)** | **100 %, 100 %, 100 %, 100 %, 100 %** | 80.6 MB (flat), indexes 8.6 MB | 0.5–0.6 s |
| rewritten at fillfactor 40 (the first design) | 100 %, 100 %, 100 %, 100 %, 100 % | 58.4 MB (flat), indexes 8.6 MB | 0.3–0.4 s |
| rewritten at fillfactor 100 (a plain CLUSTER) | 0.1, 0.2, 0.3, 0.4, 0.5 % | 138.9 MB (+23 MB a pass), indexes 9 → 17.8 MB | 1.4–1.9 s |
| as it is today (241 MB, no rewrite) | 13.5, 13.0, 12.6, 12.3, 12.0 % | 341.6 MB (+20 MB a pass) | 1.6–1.8 s |

So the fillfactor, not the CLUSTER alone, is what breaks the loop — and the probe's HOT assert has teeth: on the fillfactor-100
rewrite the same single-row probe is **not** HOT (counter 0), on the fillfactor-30 (and 40) rewrite it is.

Generations pinned by a long snapshot (G full-table updates in ONE transaction; HOT share of each generation; the minute after the
pin ends):

| fillfactor | heap at rewrite | gen 1 | gen 2 | gen 3 | gen 4 | next minute, pin gone |
|---|---|---|---|---|---|---|
| **30 (the decision)** | **80.6 MB** | **100 %** | **100 %** | **48 %** | **52 %** | **100 %** |
| 40 (the first design) | 58.4 MB | 100 % | 52 % | 48 % | 77 % | 100 % |
| 50 | 46.5 MB | 100 % | 1 % | 99 % | 2 % | 100 % |
| 60 | 39.0 MB | 68 % | 22 % | 54 % | 32 % | 78 % |

Reading: 30 absorbs two pinned generations (three versions of every row on a page: 3 × 15 = 45 ≤ ~52, the third generation then fits
about 7 of the 15 rows a page), 40 absorbs one, for +22 MB of heap (80.6 vs 58.4 MB). Whichever it is, the table heals the minute the
pin ends. **Decided by the coordinator, 2026-11-01 (by default): fillfactor 30**, which is what the migration now says (the migration
is not applied anywhere yet).

**Shared prefix cache:** the cache keeps one tail snapshot per running chain, and two branches' chain runs overwrite each other's
`p0278` (the proof run's snapshot for this chain, key `0dd7a367…`, was pruned within seconds by a concurrent run of another branch's
chain, a 0293 migration; earlier my runs did the same to the `stats-budget` branch's). Main's `p0275–p0277` are untouched and kept; the
losing branch re-applies its one migration on its next run (seconds, not a replay).

**Deviations from the design, and why:** (1) 154,734 rows, not 155,344 — measured. (2) `statement_timeout = 20min` and
`lock_timeout = 10s` set for the transaction — prod's session default of 120 s would cancel the rewrite on a slow disk, and an unbounded
lock wait queues every market read. (3) The function sweep / registry / switches are taken before the lock and compared after it. (4) Asserts
added beyond §3's list: the indexes were REBUILT (new relfilenodes), the primary key is marked clustered, and there are exactly three.
(5) The receipt prints sizes and four timings; since `supabase db push` shows no notices, §6 says where to read the prod times.
(6) Fillfactor 30, not 40 — the coordinator's decision after §8's pinned-generation experiment.
