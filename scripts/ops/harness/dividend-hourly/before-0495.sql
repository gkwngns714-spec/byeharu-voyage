-- 0495 DIVIDENDS ARE PAID EVERY HOUR, BEFORE. A PROD CHECK: read-only, ONE statement (begin read only ... rollback), the gate's three figures.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/dividend-hourly/before-0495.sql
-- Expect: head 20260818000494; switch absent (null); new_fns 0; new_columns 0; the two hunked bodies equal to the chain's world at 0494
--   (so each of 0495's two hunks occurs there exactly once, as its self-assert proved on that world):
--   tick_city e20c2ede1478a164dd694cf56e4bae96, city_coupons 2ae682d14f8a513b5246f9651ff649c2.
--   A different digest: 0495 refuses at the push (its hunk count), nothing changes.
--   sea_places_free >= 1 (the self-assert's scene stands on a SEA_PLACE with no purse, share or flow; 0 = it refuses, nothing changes).
-- THE LOAD THE SWITCH WOULD ADD, read here so the lead can state it before lighting (this file adds none while dark):
--   harbours = purse rows (H); load.pairs = holder-and-harbour pairs (P), by players and merchants; holders = distinct houses.
--   Lit, one tick an hour writes H purse-row updates + up to P ledger rows + P treasury_flows + 2 P stats_live_deltas + P purse
--   updates: at most (H + 5 P) / 60 rows a minute. coupon_hour_max = what an hour would pay if every city's 24 hours covered it
--   (round(paid x works_coupon_day / 24) a pair, before 0148's multiplier). accrued_sum = old `accrued`, collected as today.
-- Reads: arrivals_beats (5 minutes), pg_class, pg_stat_activity, world_config by key, the catalog, port_treasury (one row a harbour),
--   city_shares (one pass), players by id for the holders. No function that writes is called. ROLLBACK: nothing (read only).
begin transaction read only;
select json_build_object(
  'at', now(),
  'gate', json_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(c.relpages)::numeric * 8192 / 1048576)::int from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'switch', (select c.value from public.world_config c where c.key = 'dividend_hourly_enabled'),
  'works_coupon_day', (select c.value from public.world_config c where c.key = 'works_coupon_day'),
  'city_treasury_enabled', (select c.value from public.world_config c where c.key = 'city_treasury_enabled'),
  'new_fns', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where n.nspname = 'public' and p.proname in ('dividend_hourly_on', 'real_hour', 'city_coupon_hour')),
  'new_columns', (select count(*) from information_schema.columns c
                   where c.table_schema = 'public' and c.table_name = 'port_treasury' and c.column_name in ('profit_hours', 'coupon_hour')),
  'bodies', (select json_object_agg(p.proname, md5(replace(pg_get_functiondef(p.oid), E'\r', '')))
               from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname in ('tick_city', 'city_coupons')),
  'sea_places_free', (select count(*) from public.ports q
                       where q.kind = 'SEA_PLACE'
                         and not exists (select 1 from public.port_treasury t where t.port_id = q.id)
                         and not exists (select 1 from public.city_shares s where s.port_id = q.id)
                         and not exists (select 1 from public.treasury_flows f where f.port_id = q.id)),
  'harbours', (select count(*) from public.port_treasury),
  'load', (select json_build_object(
             'pairs', count(*), 'pairs_players', count(*) filter (where not x.is_npc), 'pairs_merchants', count(*) filter (where x.is_npc),
             'holders', count(distinct x.player_id), 'paid_sum', coalesce(sum(x.paid), 0), 'accrued_sum', coalesce(sum(x.accrued), 0),
             'pairs_under_one_coin', count(*) filter (where round(x.paid * (select (c.value #>> '{}')::numeric from public.world_config c where c.key = 'works_coupon_day') / 24) < 1),
             'coupon_hour_max', coalesce(sum(round(x.paid * (select (c.value #>> '{}')::numeric from public.world_config c where c.key = 'works_coupon_day') / 24)), 0))
             from (select s.port_id, s.player_id, pl.is_npc, sum(s.paid) as paid, sum(s.accrued) as accrued
                     from public.city_shares s join public.players pl on pl.id = s.player_id group by 1, 2, 3) x)
);
rollback;
