-- 0506 TEN BARGAINS, FIVE PER CENT EACH, AFTER; ALSO THE 30-MINUTE LIT CHECK. A PROD CHECK: read-only, ONE statement, the gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/bargain-ten/after-0506.sql
-- Expect, as deployed: head 0506; bargain_total_enabled false; new_fns 15; client_reach false; the bodies:
--   cmd.do_buy 6772cad2c8ef4c3d9ef7ffb6dcdb5e72, cmd.do_sell 18fff22b5f80d5d649cad174c624a55f, cmd.haggle f6a2d7a58bcf825c6e8def8e350e5880, public.bargain_actor 5ce5243869ff8a8cce5cabc00d4b6c4b, public.bargain_factor 96c243d94ad7c034a06c0f5fd6b6e1eb, public.bargain_first a485db15053c3830b9c7728019746f16, public.bargain_odds f1e7ab41f400d36e6047ea75497fdedd, public.bargain_on e4e1bb1114c7a315770f3dc2aee5c321, public.bargain_p1 83b4750eec39ae7f9d28f9046dc91eca, public.bargain_side_refusal 6eb294c62c20017a7aefcc7ac571bc63, public.bargain_state c3a18b417d2cac7bedf7ca7086d2a2a0, public.bargain_xp 74491ae1cc349838fdb0867deae284bc, public.fleet_job_set_for fa5a2959baf4773bc235e619ef104432, public.haggle_attempts_max fbff182611eacb843033922a93c8cc75, public.haggle_cap ad1200df66d6269eb815a3ef1dca8951, public.haggle_odds 8fcf384d9b7815fdf4a3560c8b755241, public.haggle_step ceb212c336ae47ac557ed7a4ccef16a3, public.job_bargain 7e6a6e1aa64eb6d74cb00b6c3e40e101, public.job_bargain_param 4c7a2eb943436dd994487570641b37a3, public.job_bargain_tries 964a3026d236e5c22245915777e114a8, public.level_skills_card 49b1006b9163ba8fad5cd59376b2af88, public.run_day 9a6e97028bdf70a13868c3368017c194, world.haggle_state 1d73a68e9e25c55c073323c87ba30009, world.quote_priced 39d796cf0a340226096a3f375b8aaf37, world.spread_pair_from 8657099742301c76a50d9a99d125b69a.
-- ROLLBACK: bargain_total_enabled false (the owner's switch).
begin transaction read only;
select json_build_object(
  'at', now(),
  'gate', json_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(c.relpages)::numeric * 8192 / 1048576)::int from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knobs', (select coalesce(json_object_agg(c.key, c.value), '{}'::json) from public.world_config c where c.key in ('bargain_total_enabled', 'bargain_attempts', 'bargain_step', 'bargain_p1_base', 'bargain_p1_max', 'bargain_decay')),
  'new_fns', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where n.nspname = 'public' and p.proname in ('bargain_on', 'haggle_attempts_max', 'haggle_step', 'haggle_cap', 'bargain_p1', 'bargain_odds', 'bargain_actor', 'bargain_side_refusal', 'bargain_xp', 'job_bargain_tries', 'job_bargain', 'job_bargain_param', 'bargain_factor', 'bargain_state', 'bargain_first')),
  'client_reach', (select coalesce(bool_or(has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute')
                                           or has_function_privilege('service_role', p.oid, 'execute')), false)
                     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'public' and p.proname in ('bargain_on', 'haggle_attempts_max', 'haggle_step', 'haggle_cap', 'bargain_p1', 'bargain_odds', 'bargain_actor', 'bargain_side_refusal', 'bargain_xp', 'job_bargain_tries', 'job_bargain', 'job_bargain_param', 'bargain_factor', 'bargain_state', 'bargain_first')),
  'bodies', (select json_object_agg(n.nspname || '.' || p.proname, md5(replace(pg_get_functiondef(p.oid), E'\r', '')))
               from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('public', 'world', 'cmd') and p.proname in ('do_buy', 'do_sell', 'haggle', 'fleet_job_set_for', 'haggle_odds', 'level_skills_card', 'run_day', 'haggle_state', 'quote_priced', 'spread_pair_from', 'bargain_on', 'haggle_attempts_max', 'haggle_step', 'haggle_cap', 'bargain_p1', 'bargain_odds', 'bargain_actor', 'bargain_side_refusal', 'bargain_xp', 'job_bargain_tries', 'job_bargain', 'job_bargain_param', 'bargain_factor', 'bargain_state', 'bargain_first')),
  'haggle_daily', (select json_build_object('rows', c.reltuples::bigint, 'mb', round(c.relpages * 8 / 1024.0, 1)) from pg_class c where c.oid = 'public.haggle_daily'::regclass)
);
rollback;
