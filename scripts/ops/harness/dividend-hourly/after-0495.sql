-- 0495 DIVIDENDS ARE PAID EVERY HOUR, AFTER; ALSO THE 30-MINUTE LIT CHECK. A PROD CHECK: read-only, ONE statement. The gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/dividend-hourly/after-0495.sql
-- Expect, AS DEPLOYED (dark): head 20260818000495; switch false; new_fns 3, client_reach false (none callable by public, anon,
--   authenticated or service_role); new_columns 2; bodies = the chain's world at 0495: tick_city 6c53de13b5b7a60006a34943a14ba01d,
--   city_coupons 6498d838a4f6211157a5124edb8cce7b, city_coupon_hour 800ff4b371e8f44bd45ef21b836e9260,
--   dividend_hourly_on 0de43cb4426162829bce8db689e2a032, real_hour d146b7f9014a5e849fe0aa2383b7ec17;
--   hourly_state: stamped 0, rings 0 (dark writes neither column); dividend_2h: ledger rows as before (arrivals that collect).
-- LIT (read after the first :37 run that follows the owner lighting dividend_hourly_enabled, and again 30 minutes later):
--   hourly_state.stamped = harbours and newest_hour = `hour` (every harbour's hour closed); rings = harbours;
--   dividend_2h: ledger rows about load.pairs of before-0495.sql an hour at most, each <= round(paid x works_coupon_day x 1.5 / 24);
--   flows_waiting: DIVIDEND flows not yet rolled (the last hour's) = -(the ledger's hourly pays of that hour); purses_under_reserve
--   no higher than before the switch; city_job: the last runs of the cron job byeharu-voyage:city, all succeeded, seconds as before
--   plus the hour's pays.
-- ROLLBACK if client_reach true, a city_job run failed or ran over 20 s, purses_under_reserve rose, dividend_2h.max_row is over the
--   bound above, or the gate goes red: dividend_hourly_enabled false (owner). The next tick then pays the daily way again, into
--   `accrued`; what was paid stays paid. Full reversal: rollback-0495.sql (a draft).
-- Reads: arrivals_beats (5 minutes), pg_class, pg_stat_activity, world_config by key, the catalog, port_treasury (one row a harbour),
--   ledger of kind DIVIDEND in the last 2 hours, treasury_flows (the hour's unrolled rows), cron.job_run_details (the last 6 runs of
--   one job). No function that writes is called (public.city_surplus is STABLE). ROLLBACK: nothing (read only; ends with rollback).
begin transaction read only;
select json_build_object(
  'at', now(),
  'hour', floor(extract(epoch from now()) / 3600)::int,
  'gate', json_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(c.relpages)::numeric * 8192 / 1048576)::int from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'switch', (select c.value from public.world_config c where c.key = 'dividend_hourly_enabled'),
  'new_fns', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where n.nspname = 'public' and p.proname in ('dividend_hourly_on', 'real_hour', 'city_coupon_hour')),
  'client_reach', (select coalesce(bool_or(has_function_privilege('public', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute')
                                           or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute')), false)
                     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'public' and p.proname in ('dividend_hourly_on', 'real_hour', 'city_coupon_hour')),
  'new_columns', (select count(*) from information_schema.columns c
                   where c.table_schema = 'public' and c.table_name = 'port_treasury' and c.column_name in ('profit_hours', 'coupon_hour')),
  'bodies', (select json_object_agg(p.proname, md5(replace(pg_get_functiondef(p.oid), E'\r', '')))
               from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname in ('tick_city', 'city_coupons', 'city_coupon_hour', 'dividend_hourly_on', 'real_hour')),
  'harbours', (select count(*) from public.port_treasury),
  'hourly_state', (select json_build_object('stamped', count(*) filter (where t.coupon_hour <> 0), 'newest_hour', max(t.coupon_hour),
                                            'oldest_hour', min(t.coupon_hour) filter (where t.coupon_hour <> 0),
                                            'rings', count(*) filter (where cardinality(t.profit_hours) = 24),
                                            'cities_in_profit_24h', count(*) filter (where (select coalesce(sum(v), 0) from unnest(t.profit_hours) v) >= 24),
                                            'cities_at_a_loss_24h', count(*) filter (where (select coalesce(sum(v), 0) from unnest(t.profit_hours) v) < 0))
                     from public.port_treasury t),
  'purses_under_reserve', (select count(*) from public.port_treasury t where public.city_surplus(t.port_id) < 0),
  'dividend_2h', (select json_build_object('rows', count(*), 'rows_last_hour', count(*) filter (where l.created_at > now() - interval '1 hour'),
                                           'sum', coalesce(sum(l.ducats_delta), 0), 'max_row', max(l.ducats_delta), 'houses', count(distinct l.player_id))
                    from public.ledger l where l.kind = 'DIVIDEND' and l.created_at > now() - interval '2 hours'),
  'flows_waiting', (select json_build_object('rows', count(*), 'sum', coalesce(sum(f.ducats), 0))
                      from public.treasury_flows f where f.kind = 'DIVIDEND'),
  'city_job', (select coalesce(json_agg(json_build_object('at', d.start_time, 'status', d.status,
                                                          'seconds', round(extract(epoch from d.end_time - d.start_time)::numeric, 2)) order by d.start_time desc), '[]'::json)
                 from (select r.start_time, r.end_time, r.status from cron.job_run_details r
                        where r.jobid = (select j.jobid from cron.job j where j.jobname = 'byeharu-voyage:city')
                        order by r.start_time desc limit 6) d)
);
rollback;
