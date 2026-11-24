-- 0495 DIVIDENDS ARE PAID EVERY HOUR, AFTER; ALSO THE 30-MINUTE LIT CHECK. A PROD CHECK: read-only, ONE statement. The gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/dividend-hourly/after-0495.sql
-- Expect, AS DEPLOYED (dark): head 20260818000495; switch false; new_fns 3, client_reach false (none callable by public, anon,
--   authenticated or service_role); new_columns 3; bodies = the chain's world at 0495: tick_city 38ac4e83a8d409c312610175ffe45efc,
--   city_coupons 5183c250b3e834440ce1d414bd0e9ee5, city_coupon_hour a823439b6062545fccd45a5ba8f226c1,
--   dividend_hourly_on 0de43cb4426162829bce8db689e2a032, real_hour 7e8d066d91d62fe1d266788575ef303c;
--   payout: rows_marked 0, merchants_marked 0 (dark marks nothing); dividend_2h: ledger rows as before (arrivals that collect).
-- LIT (the owner lights dividend_hourly_enabled; nothing is paid out before the next day's coupon, the 00:37 UTC run. Read after
--   that run and again 30 minutes later, and after the 01:37 run):
--   payout.merchants_marked 0 ALWAYS (a merchant is never paid hourly); rows_marked = the player pairs whose city paid a coupon
--   (at most load.pairs_players of before-0495.sql); newest_hour = `hour` after a :37 run; left_sum falls every hour by about
--   hour_sum; over_accrued 0 or falling (a row whose holder collected at an arrival is cleared by its next hour);
--   dividend_2h: about one ledger row a paid player an hour, each <= her hour_sum; city_job: the last runs of the cron job
--   byeharu-voyage:city all succeeded, seconds as before.
-- ROLLBACK if client_reach true, merchants_marked above 0, a city_job run failed or ran over 20 s, dividend_2h.rows_last_hour is
--   above payout.players + the arrivals of that hour, or the gate goes red: dividend_hourly_enabled false (owner). Nothing more is
--   paid out then; what is left waits in `accrued` for an arrival, as before. Full reversal: rollback-0495.sql (a draft).
-- Reads: arrivals_beats (5 minutes), pg_class, pg_stat_activity, world_config by key, the catalog, city_shares (one pass) with
--   players by id, ledger of kind DIVIDEND in the last 2 hours, cron.job_run_details (the last 6 runs of one job). No function that
--   writes is called. ROLLBACK: nothing (read only; ends with rollback).
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
                   where c.table_schema = 'public' and c.table_name = 'city_shares' and c.column_name in ('drip_left', 'drip_hour', 'drip_at')),
  'bodies', (select json_object_agg(p.proname, md5(replace(pg_get_functiondef(p.oid), E'\r', '')))
               from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname in ('tick_city', 'city_coupons', 'city_coupon_hour', 'dividend_hourly_on', 'real_hour')),
  'payout', (select json_build_object(
               'rows_marked', count(*) filter (where s.drip_left > 0),
               'merchants_marked', count(*) filter (where pl.is_npc and (s.drip_left <> 0 or s.drip_hour <> 0 or s.drip_at <> 0)),
               'players', count(distinct s.player_id) filter (where s.drip_left > 0),
               'left_sum', coalesce(sum(s.drip_left), 0),
               'hour_sum', coalesce(sum(least(s.drip_hour, s.drip_left, s.accrued)) filter (where s.drip_left > 0), 0),
               'over_accrued', count(*) filter (where s.drip_left > s.accrued),
               'newest_hour', max(s.drip_at), 'oldest_hour', min(s.drip_at) filter (where s.drip_left > 0))
               from public.city_shares s join public.players pl on pl.id = s.player_id),
  'dividend_2h', (select json_build_object('rows', count(*), 'rows_last_hour', count(*) filter (where l.created_at > now() - interval '1 hour'),
                                           'sum', coalesce(sum(l.ducats_delta), 0), 'max_row', max(l.ducats_delta), 'houses', count(distinct l.player_id))
                    from public.ledger l where l.kind = 'DIVIDEND' and l.created_at > now() - interval '2 hours'),
  'city_job', (select coalesce(json_agg(json_build_object('at', d.start_time, 'status', d.status,
                                                          'seconds', round(extract(epoch from d.end_time - d.start_time)::numeric, 2)) order by d.start_time desc), '[]'::json)
                 from (select r.start_time, r.end_time, r.status from cron.job_run_details r
                        where r.jobid = (select j.jobid from cron.job j where j.jobname = 'byeharu-voyage:city')
                        order by r.start_time desc limit 6) d)
);
rollback;
