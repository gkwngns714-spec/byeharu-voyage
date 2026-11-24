-- 0495 DIVIDENDS ARE PAID EVERY HOUR, BEFORE. A PROD CHECK: read-only, ONE statement (begin read only ... rollback), the gate's three figures.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/dividend-hourly/before-0495.sql
-- Expect: head 20260818000494; switch absent (null); new_fns 0; new_columns 0; the two hunked bodies equal to the chain's world at 0494
--   (so each of 0495's two hunks occurs there exactly once, as its self-assert proved on that world):
--   tick_city e20c2ede1478a164dd694cf56e4bae96, city_coupons 2ae682d14f8a513b5246f9651ff649c2.
--   A different digest: 0495 refuses at the push (its hunk count), nothing changes.
--   sea_places_free >= 1 (the self-assert's scene stands on a SEA_PLACE with no purse, share or flow; 0 = it refuses, nothing changes).
-- THE LOAD THE SWITCH WOULD ADD, read here so the lead can state it before lighting (this file adds none while dark):
--   load.pairs_players = P (player-and-harbour pairs; read 2026-11-24 20:57 UTC: 1) held by load.players = N; pairs_merchants are NOT
--   paid hourly (read: 3,656) and get no new row. Lit, an hour writes P share-row updates + N ledger rows + N purse updates + N + P
--   stats_live_deltas rows: about 3 N + 2 P. P = 1: 5 rows an hour. P = 100: 500 rows an hour (8 a minute, in the :37 run).
--   coupon_hour_max_players = what an hour pays out at most (round(paid x works_coupon_day / 24) a pair, before 0148's multiplier).
-- Reads: arrivals_beats (5 minutes), pg_class, pg_stat_activity, world_config by key, the catalog, city_shares (one pass), players by
--   id for the holders. No function that writes is called. ROLLBACK: nothing (read only).
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
                   where c.table_schema = 'public' and c.table_name = 'city_shares' and c.column_name in ('drip_left', 'drip_hour', 'drip_at')),
  'bodies', (select json_object_agg(p.proname, md5(replace(pg_get_functiondef(p.oid), E'\r', '')))
               from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname in ('tick_city', 'city_coupons')),
  'sea_places_free', (select count(*) from public.ports q
                       where q.kind = 'SEA_PLACE'
                         and not exists (select 1 from public.port_treasury t where t.port_id = q.id)
                         and not exists (select 1 from public.city_shares s where s.port_id = q.id)
                         and not exists (select 1 from public.treasury_flows f where f.port_id = q.id)),
  'load', (select json_build_object(
             'pairs', count(*), 'pairs_players', count(*) filter (where not x.is_npc), 'pairs_merchants', count(*) filter (where x.is_npc),
             'players', count(distinct x.player_id) filter (where not x.is_npc),
             'paid_sum_players', coalesce(sum(x.paid) filter (where not x.is_npc), 0),
             'accrued_sum_players', coalesce(sum(x.accrued) filter (where not x.is_npc), 0),
             'coupon_hour_max_players', coalesce(sum(round(x.paid * (select (c.value #>> '{}')::numeric from public.world_config c where c.key = 'works_coupon_day') / 24)) filter (where not x.is_npc), 0))
             from (select s.port_id, s.player_id, pl.is_npc, sum(s.paid) as paid, sum(s.accrued) as accrued
                     from public.city_shares s join public.players pl on pl.id = s.player_id group by 1, 2, 3) x)
);
rollback;
