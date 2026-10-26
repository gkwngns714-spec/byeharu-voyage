# 2026-10-26 — A count adds both halves of a day (fixes the :51 jumps) — migration 0243

Server only. `supabase/migrations/20260818000243_the_count_adds_both_halves.sql` (0241/0242 belong to in-flight branches; deploy order renumbers to prod head + 1).

## The bug
`public.tick_stats` writes `stats_world.recent` (newest three game days per kind) from the daybook (rolled) `union all` `treasury_flows` (not yet rolled), then `jsonb_object_agg(x.kind, x.s)`. A (day, kind) present in both halves appears twice; jsonb keeps the LAST, so `recent` held one half. Around each :37 city roll the next count held the whole, and the period (and `stats_world` minted / removed / moved) jumped by the missing half (07:51: minted 443,824 = 851,659 - 407,835 of IMPORT_DEMAND that was pre-switch money).

## The fix
One hunk: sum per (day, kind) (`group by 1, 2`) before `jsonb_object_agg`. Cut against the LIVE body; the old text occurs once on prod (check 2); the new body reverses to its pre-image; ACL, owner, volatility, definer, config checked unchanged.

## Proof (cached-prefix apply, `applyChainCached`, 229 restored + 0243)
Self-assert, rolled back, probe rows only: kind `PROBE_0243` planted at 1000 in the daybook and 250 in the flows of one game day (two hours ahead, so no cron slot clashes; direct inserts, not `treasury_post`, so the closed-economy guard is not asked). The old query shape on those rows keeps 250 (one half); the re-cut `tick_stats` writes `recent` = 1250. Nothing survives the rollback. No hour-of-day dependence; nothing counted over a growing table; no DELETE.

## PROD CHECKS (pure SELECTs; run 2026-10-26)
`pg_get_functiondef` is a catalog read; `world.game_day` is `s`.
### 1_tick_stats_and_head
```sql
select p.provolatile, p.prosecdef, (select max(version) from supabase_migrations.schema_migrations) as head from pg_proc p where p.oid = 'public.tick_stats(timestamptz)'::regprocedure
```
Result: volatile `v` (we do not call it), security definer true, head 20260818000240.
### 2_hunk_once
```sql
select (length(d)-length(replace(d,$h$            from (select d.game_day as gd, d.kind, sum(d.ducats) as s$h$,'')))/length($h$            from (select d.game_day as gd, d.kind, sum(d.ducats) as s$h$) as old_once, (length(d)-length(replace(d,'0243:',''))) as new_marks from (select replace(pg_get_functiondef('public.tick_stats(timestamptz)'::regprocedure),chr(13),'') d) z
```
Result: old_once = 1, new_marks = 0 (not applied yet).
### 3_game_day_volatility
```sql
select provolatile, proname from pg_proc where oid = 'world.game_day(timestamptz)'::regprocedure
```
Result: `s`.
