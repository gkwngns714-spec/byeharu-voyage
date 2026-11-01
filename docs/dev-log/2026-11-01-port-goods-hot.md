# 2026-11-01 — 0291: the market table is rewritten compact, with room for in-page updates

**Branch** `port-goods-hot` · **migration** `supabase/migrations/20260818000291_the_market_table_keeps_room.sql`
(number = prod head + 1 AT THE TIME OF DEPLOY; this file assumes 0290 — `stats-budget`, the Stats count — is live first.
Deploy one migration at a time, `~/bin/bv-deploy.sh <pr>`, by the coordinator. Do NOT open the PR until the coordinator says
0290 is merged and main's snapshot run has finished: the chain law.)

## 1. Why — measured read-only on prod, 2026-11-01 ~13:30–13:55 UTC

The every-minute market (owner-directed, "nothing regarding time") rewrites ~155 k `public.port_goods` rows a minute
(`tick_market_drift`, one UPDATE per row since 0289). The TABLE is the problem, not the cadence:

| fact | measured |
|---|---|
| live rows | 155,344 (~122 B of data a row from `pg_stats` + 24 B header ≈ 23 MB of live data) |
| heap | **293 MB** — ~13× bloat; 3 indexes 36 MB |
| dead tuples | 149 k (≈ the live count) at every look; autovacuum runs on it constantly |
| HOT updates | **34 %** of 35.8 M updates (11.3 M of 33.8 M earlier): two thirds of the updates also write 3 index entries |
| `reloptions` | none (fillfactor 100) |
| the drift job | `shared_blks_dirtied` ≈ 3.95 k and `shared_blks_read` ≈ 3.7 k PER MINUTE (pg_stat_statements, 221 calls) — the biggest dirtier in the database |
| whole-DB WAL | **62 MB/min**, 1.82 M full-page images in 4 h 10 m (≈ the whole 15 GB) — one 8 KB image for every page of this table after every checkpoint |
| compute | Micro-class (shared_buffers 256 MB): a 293 MB table never stays cached |

Why only 34 % are HOT: no indexed column is updated by the drift (the indexes are `(good_id)`, `(port_id, good_id)` and the partial
`(port_id, good_id) WHERE haul_nm = 0`; the drift writes `drift`, `stock`, `drift_slot`, `updated_at`, …), so every update COULD be
HOT, but a HOT update needs free room on the SAME page, and at fillfactor 100 a page that is full of live rows + not-yet-vacuumed
dead versions has none. A non-HOT update leaves a dead version that its index entries pin until a VACUUM, so the room never comes
back between vacuums — a loop that only a rewrite with spare room breaks.

## 2. The design

One small migration, no function re-cut, no new knob, no cron/knob/switch change:

```
alter table public.port_goods set (fillfactor = 40);
cluster public.port_goods using port_goods_pkey;     -- rewrites heap + all 3 indexes, honours the fillfactor, puts a port's rows together
analyze public.port_goods;
```
- **fillfactor 40**: ~21 live rows a page, ~54 slots, so a page holds a whole minute's new versions beside the old ones (21 + 21 ≤ 54)
  and even a second update of some rows (a buy/sell touching `stock`) stays in-page. Expected table ≈ 60 MB (vs 293 MB).
- **CLUSTER is allowed inside a migration transaction** for a single named table (only the no-argument form refuses a transaction
  block). It takes ACCESS EXCLUSIVE on `port_goods` until the migration commits — so keep everything after it light. The coordinator's
  deploy (`bv-deploy.sh`) runs `unwind_the_clock()` first (the crons are stopped), so only player reads can wait; budget for
  roughly 10–60 s of lock on this compute (estimate; measure it in the dev-log from the push log).
- `cluster … using port_goods_pkey` also orders the rows by `(port_id, good_id)`: the per-port drift touches one port's rows together.
- Forward rollback: `alter table public.port_goods reset (fillfactor); cluster public.port_goods using port_goods_pkey;` (a new
  migration, never an edit).

## 3. The self-assert (rolled back where it writes; the rewrite itself is the migration's effect)

Take `lock table public.port_goods in access exclusive mode` FIRST, read `count(*)` and a cheap order-insensitive checksum of the
key set (e.g. `count(*)`, `min`/`max` of `port_id`, `sum(hashtext(port_id::text || good_id::text))`) — `port_goods` is a fixed
catalogue (~155 k rows, no growth by play), so equality across the rewrite is a valid assert once the lock is held. After the rewrite:
(a) same count and checksum; (b) `reloptions` carries `fillfactor=40`; (c) the three indexes exist, valid and ready, same
definitions as before (compare `pg_get_indexdef` text taken before); (d) `pg_class.relfilenode` changed (the rewrite happened);
(e) every function in public/cmd/world/voyage md5-unmoved (0287's technique), the registry/walls as found; (f) one probe UPDATE of a
single real row's `updated_at` inside the transaction followed by a check that `pg_stat_get_xact_tuples_hot_updated` for the table
rose by 1 (a HOT update happened) — then the whole block rolls back. Never assert a size or a timing.

## 4. Gates (lean) and traps

tsc/eslint untouched (SQL only) · `node scripts/db/check-versions.mjs` · `BYEHARU_PREFIX_CACHE=required node scripts/db/proof.mjs standing`
(the chain through the prefix cache, never a from-zero replay) · `tests/duplication.spec.ts`. The CI world's `port_goods` is small, so
the migration runs in a second there; only prod's volume makes the lock long. Do NOT edit `tick_market_drift` or anything that
writes the table; the economy numbers must not move — the rewrite changes no value.

## 5. Prod checks before the PR (read-only, one SELECT per call) and the BEFORE numbers to record

Head; `reloptions` null; the three index definitions; the live row count; `pg_stat_user_tables` for the table (n_tup_upd,
n_tup_hot_upd, n_dead_tup, heap size); `pg_stat_statements` for `call public.tick_market_drift_each_port()` (calls, mean_exec_time,
shared_blks_dirtied, shared_blks_read); `pg_stat_wal` (wal_bytes + stats_reset, to compute MB/min); the hourly mean of the cron
`…:drift` and `…:compact` and `…:price-snapshot` runs. The BEFORE values of 2026-11-01 are in §1; record the exact reading time.

## 6. After-check (the coordinator, 30 min, read-only) — this alters live play's speed, so it gets its own measured window

The push log shows the lock time; the first minutes after the clock is wound: drift mean/max per minute and failures; the table's
heap size and HOT ratio from the deltas of `n_tup_hot_upd`/`n_tup_upd` since the push; dirtied/read blocks per drift call; WAL MB/min;
`price-snapshot` and `compact` durations. Success = HOT share above ~90 %, heap < 100 MB, drift dirtied blocks per call down by a
large factor, WAL/min well below 62. If the HOT share stays low, lower the fillfactor in a follow-up migration (it is one line).

## 7. Bookkeeping

This file completed with the gates and the push log's lock time; one line at the top of `docs/WORK_QUEUE.md`; an owner row for
"the game became slower" (OWNER_REQUESTS rows 256/259) updated with the state only. PR title: `MIGRATION — 0291: the market table
is rewritten compact, with room for in-page updates (deploy AFTER 0290)`. Commit trailer:
`Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
