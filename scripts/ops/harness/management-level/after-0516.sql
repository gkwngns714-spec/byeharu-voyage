-- 0516 PASSIVE SETTINGS, AFTER. A PROD CHECK: read-only, ONE statement, the gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/management-level/after-0516.sql
-- Expect: head 0516; passive_settings_enabled false; new_fns 7; client_reach false; with_settings, range_waits and stops 0 while dark.
-- LIT, 30 minutes on: `stopped` grows by `stops` alone.
-- ROLLBACK: the switches false (the owner's).
begin transaction read only;
select json_build_object(
  'at', now(),
  'gate', json_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(c.relpages)::numeric * 8192 / 1048576)::int from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knobs', (select coalesce(json_object_agg(c.key, c.value), '{}'::json) from public.world_config c where c.key in ('passive_settings_enabled', 'level_unlocks_enabled', 'level_perks_on')),
  'new_fns', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('passive_settings_on', 'job_settings_param', 'job_settings_judge', 'job_settings_lines', 'fleet_damage_pct', 'job_damage_mended', 'job_settings_room')),
  'client_reach', (select coalesce(bool_or(has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute')), false)
                     from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('passive_settings_on', 'job_settings_param', 'job_settings_judge', 'job_settings_lines', 'fleet_damage_pct', 'job_damage_mended', 'job_settings_room')),
  'bodies', (select json_object_agg(p.proname, left(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), 8))
               from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('job_settings_judge')),
  'jobs', (select json_build_object('all', count(*), 'with_settings', count(*) filter (where j.params ?| array['under', 'over', 'crew', 'days', 'stop_profit', 'stop_damage']),
             'range_waits', count(*) filter (where j.last->>'wait' = 'range'), 'stops', count(*) filter (where j.paused_reason in ('E_STOP_PROFIT', 'E_STOP_DAMAGE')),
             'stopped', count(*) filter (where j.paused_reason is not null)) from public.fleet_jobs j)
);
rollback;
