-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0412 - THE SWEEPER COMES A FEW TIMES A DAY  (per-table autovacuum thresholds and pace on the churn tables; no row is touched)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none
--
-- WHY (prod, read-only by the lead, 2026-11-14 11:05 UTC, head 0409; docs/dev-log/2026-11-14-slim-autovac.md):
--   Twelve minutes after 0409 the beat still takes about 12 s. pg_stat_io since 11-01: the AUTOVACUUM WORKERS have read 574,410,244 blocks and
--   written 67,271,408; every client backend together read 506,247,081. The sweeper is the largest reader of the disk, larger than the game.
--   It is asked to be: the chain gave the churn tables thresholds of 500 to 2,000 dead rows (scale factor 0), sized when the world was a tenth
--   of this. events passes 2,000 dead rows in under two minutes, so it is vacuumed 337 times a day; standing_route_laps 714 times (and analysed
--   every 2,000 changes: about 265 times a day, each a sample of up to 30,000 pages); orders 578; voyages 432; voyage_events 294; ledger 272.
--   Each pass reads the whole heap and every index (events 555 MB, laps 372 MB) from a disk that holds none of it in memory, at the default
--   pace, which is no pace: about 100 page reads every 2 ms.
--
-- WHAT THIS FILE DOES: ALTER TABLE ... SET (...) on fourteen tables. Storage parameters only: no data, no function, no index.
--   1. HOW OFTEN: autovacuum_vacuum_threshold sized from each table's own churn (pg_stat_user_tables, 11-01 to 11-14) so that it is vacuumed
--      a few times a day at that churn, a dozen or two at the worst (the table below). The scale factors stay 0: a fixed number of dead rows,
--      whatever the table's size. The dead rows a table may hold between two passes are bounded by that number; their room is in the table.
--   2. THE INSERT-TRIGGERED PASS (it exists to keep the visibility map and the freeze up on tables nobody deletes from) is spaced the same
--      way; on these tables the delete-triggered passes do that work anyway.
--   3. ANALYZE a few times a day too (autovacuum_analyze_threshold, scale factor 0). No plan here turns on a fresh histogram: every hot read
--      of these tables is by key or by a time window on an index that is the only sensible path.
--   4. THE PACE: autovacuum_vacuum_cost_delay 20 ms, autovacuum_vacuum_cost_limit 25 on each of them. With the server's own page costs
--      (a page read from disk 2, a page dirtied 20; PostgreSQL 14 and later) a pass reads at most about 625 pages a second, 5 MB/s, and
--      dirties at most about 60, 0.5 MB/s. A pass over a 250 MB table then takes a minute or more and leaves the beat most of the disk.
--   WRAPAROUND: nothing here turns autovacuum off for any table. The age-driven pass (autovacuum_freeze_max_age) is untouched and ignores
--   these thresholds; it also ignores the cost delay once a table is in danger.
--   5. THE OLD SETTINGS ARE WRITTEN DOWN, exactly as this server holds them at the moment of the change: public.autovacuum_was (new, one row
--      a table: its reloptions before). The rollback restores from it.
--
--   table                 dead rows a day (13-day mean)   old threshold -> passes a day   new threshold -> passes a day   room for the dead
--   events                790,000 (2,300,000 today)       2,000 -> 337 measured            200,000 -> 4 (12 today)         70 MB
--   ledger                620,000                         2,000 -> 272                     150,000 -> 4                    22 MB
--   voyage_events         664,000                         2,000 -> 294                     150,000 -> 4                    15 MB
--   voyages               1,060,000 (rows of 1.1 KB)      2,000 -> 432                     60,000 -> 18                    66 MB
--   standing_route_laps   535,000                         500 -> 714                       50,000 -> 11                    22 MB
--   orders                1,840,000                       default (about 2,250) -> 578     50,000 -> 37                    20 MB
--   stats_city_good       195,000                         1,000 -> 25                      100,000 -> 2                    14 MB
--   stats_good            214,000                         1,000 -> 98                      50,000 -> 4                     20 MB
--   stats_city            76,000                          1,000 -> 47                      25,000 -> 3                     5 MB
--   price_history         213,000                         1,000 -> 151                     50,000 -> 4                     5 MB
--   treasury_flows        615,000                         1,000 -> 196                     100,000 -> 6                    10 MB
--   city_wants            27,000 (0409's trim)            default -> about 26              20,000 -> 1 to 2                2 MB
--   trade_daily           not read (its rows live a minute) 2,000                           50,000                          5 MB
--   insured_voyages       about 250,000                   default (about 5,900) -> 42      50,000 -> 5                     10 MB
--   public.port_goods is NOT touched (0289 tuned it on purpose; 0409 cut its writes by ten).
--
-- LOCKS: ALTER TABLE SET (storage parameters) takes SHARE UPDATE EXCLUSIVE on its table: it does not wait for, or block, any read or write.
--   It conflicts with a VACUUM or ANALYZE of the same table; an autovacuum in its way is cancelled by the server after deadlock_timeout (1 s)
--   and starts again later under the new settings. lock_timeout 8 s: if a table cannot be had (a wraparound vacuum is never cancelled; a
--   manual VACUUM is running) the file fails with that table's name and changes nothing. Run it again later.
-- TIME: milliseconds a table. BUDGET: fails above 60 s.
-- ROLLBACK (forward, owner only): scripts/ops/harness/slim-autovac/rollback-0412.sql, a draft: every table gets back the reloptions
--   public.autovacuum_was holds for it.
-- SELF-ASSERT: the catalog only. Every setting reads back; every option a table carried that this file does not set (a fillfactor) is still there.
-- VERSION: 0412 = 0409 + the two open files before it. It touches no function.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0   timestamptz := clock_timestamp();
  t      record;
  v_old  text[];
  v_new  text[];
  v_want text[];
  v_o    text;
  v_done int := 0;
  v_pg   text[] := (select c.reloptions from pg_class c where c.oid = 'public.port_goods'::regclass);
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '8s', true);

  -- ── 0. GUARD ──
  if to_regclass('public.autovacuum_was') is not null then
    raise exception '0412 refuses: it has been applied once';
  end if;

  -- ── 1. WHERE THE OLD SETTINGS ARE WRITTEN DOWN ──
  create table public.autovacuum_was (
    tbl        text primary key,
    reloptions text[],
    at         timestamptz not null default now(),
    by_file    text not null
  );
  alter table public.autovacuum_was enable row level security;
  revoke all on table public.autovacuum_was from public, anon, authenticated;
  comment on table public.autovacuum_was is
    '0412: the storage parameters (pg_class.reloptions) each table carried at the moment 0412 changed its autovacuum settings: null = none. Written once, by 0412; read by its rollback (scripts/ops/harness/slim-autovac/rollback-0412.sql).';

  -- ── 2. THE SETTINGS ──
  create temp table set_0412 (tbl text primary key, vac int, ins int, ana int) on commit drop;
  insert into set_0412 values
    ('events',              200000, 1000000, 500000),
    ('ledger',              150000, 1000000, 300000),
    ('voyage_events',       150000, 1000000, 300000),
    ('voyages',              60000,  200000, 250000),
    ('standing_route_laps',  50000,  200000, 100000),
    ('orders',               50000,  500000, 400000),
    ('stats_city_good',     100000,  200000, 100000),
    ('stats_good',           50000,  200000,  50000),
    ('stats_city',           25000,  100000,  25000),
    ('price_history',        50000,  200000, 100000),
    ('treasury_flows',      100000,  500000, 200000),
    ('city_wants',           20000,  100000,  20000),
    ('trade_daily',          50000,  200000, 100000),
    ('insured_voyages',      50000,  200000,  50000);
  for t in select * from set_0412 order by tbl loop
    if to_regclass('public.' || t.tbl) is null then
      raise exception '0412 refuses: public.% is not in this world', t.tbl;
    end if;
    select c.reloptions into v_old from pg_class c where c.oid = ('public.' || t.tbl)::regclass;
    insert into public.autovacuum_was (tbl, reloptions, by_file) values (t.tbl, v_old, '0412');
    begin
      execute format(
        'alter table public.%I set (autovacuum_vacuum_scale_factor = 0, autovacuum_vacuum_threshold = %s, '
        || 'autovacuum_vacuum_insert_scale_factor = 0, autovacuum_vacuum_insert_threshold = %s, '
        || 'autovacuum_analyze_scale_factor = 0, autovacuum_analyze_threshold = %s, '
        || 'autovacuum_vacuum_cost_delay = 20, autovacuum_vacuum_cost_limit = 25)', t.tbl, t.vac, t.ins, t.ana);
    exception when lock_not_available then
      raise exception '0412 could not have public.% within 8 s (SHARE UPDATE EXCLUSIVE): a VACUUM that cannot be cancelled, or a schema change, holds it. Nothing was changed. Run the deploy again in a few minutes.', t.tbl;
    end;
    -- ── 3. THE SELF-ASSERT, on the catalog: this table reads back what was set, and kept every option this file does not set ──
    select c.reloptions into v_new from pg_class c where c.oid = ('public.' || t.tbl)::regclass;
    v_want := array['autovacuum_vacuum_scale_factor=0', 'autovacuum_vacuum_threshold=' || t.vac,
                    'autovacuum_vacuum_insert_scale_factor=0', 'autovacuum_vacuum_insert_threshold=' || t.ins,
                    'autovacuum_analyze_scale_factor=0', 'autovacuum_analyze_threshold=' || t.ana,
                    'autovacuum_vacuum_cost_delay=20', 'autovacuum_vacuum_cost_limit=25'];
    if not (v_new @> v_want) then
      raise exception '0412 self-assert FAIL: public.% reads % and not %', t.tbl, v_new, v_want;
    end if;
    foreach v_o in array coalesce(v_old, '{}'::text[]) loop
      if split_part(v_o, '=', 1) not in ('autovacuum_vacuum_scale_factor', 'autovacuum_vacuum_threshold', 'autovacuum_vacuum_insert_scale_factor',
                                         'autovacuum_vacuum_insert_threshold', 'autovacuum_analyze_scale_factor', 'autovacuum_analyze_threshold',
                                         'autovacuum_vacuum_cost_delay', 'autovacuum_vacuum_cost_limit')
         and not (v_o = any(v_new)) then
        raise exception '0412 self-assert FAIL: public.% lost its option %', t.tbl, v_o;
      end if;
    end loop;
    if exists (select 1 from unnest(v_new) o where o like 'autovacuum_enabled=%') then
      raise exception '0412 self-assert FAIL: public.% carries autovacuum_enabled: this file never turns the sweeper off', t.tbl;
    end if;
    v_done := v_done + 1;
  end loop;
  if v_done <> 14 or (select count(*) from public.autovacuum_was) <> 14 then
    raise exception '0412 self-assert FAIL: % table(s) set, % written down; 14 are wanted', v_done, (select count(*) from public.autovacuum_was);
  end if;
  if (select c.reloptions from pg_class c where c.oid = 'public.port_goods'::regclass) is distinct from v_pg
     or exists (select 1 from public.autovacuum_was w where w.tbl = 'port_goods') then
    raise exception '0412 self-assert FAIL: public.port_goods was touched';
  end if;
  if clock_timestamp() - v_t0 > interval '60 seconds' then
    raise exception '0412 self-assert FAIL: the file took % (budget 60 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0412 self-assert ok: THE SWEEPER COMES A FEW TIMES A DAY. Fourteen tables carry their new autovacuum thresholds (vacuum, insert-vacuum, analyze; scale factors 0) and pace (cost delay 20 ms, cost limit 25); every other option they carried is still there; none has autovacuum off; their old reloptions are in public.autovacuum_was; no function, no row; % ms.',
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
