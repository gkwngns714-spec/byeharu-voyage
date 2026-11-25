-- 0506 TEN BARGAINS, FIVE PER CENT EACH, BEFORE. A PROD CHECK: read-only, ONE statement, the gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/bargain-ten/before-0506.sql
-- Expect: head = the migration before 0506; knobs {}; new_fns 0; the hunked bodies as the chain's world before 0506:
--   cmd.do_buy c729d43130979aac20ce60e08c26ecdd, cmd.do_sell 0abb37cf1eccd82fa4aa0a7e0b42236b, cmd.haggle cc1ed1dbd1f1c02e6575efc1d6030bf8, public.fleet_job_set_for 2e7e57044367984e12c391cb7ac60f87, public.haggle_odds c57a1ca2f096afdf8a56a47abaaa63dc, public.level_skills_card a06aa6775ffbfa92facc3728a7807fec, public.run_day 8481b18743c6ff2773a56c93d96f9dcb, world.haggle_state a6900eb8f9e063aa375b70dcffcd9f47, world.quote_priced 32f186adde3bb64d0f50491958a18783, world.spread_pair_from 2d46f503a190ac65b798f968e0e28c49.
--   A different digest: 0506 refuses at the push (its hunk count), nothing changes.
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
