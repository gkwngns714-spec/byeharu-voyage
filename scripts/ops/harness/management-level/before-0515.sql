-- 0515 MANAGEMENT LEVEL, BEFORE. A PROD CHECK: read-only, ONE statement, the gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/management-level/before-0515.sql
-- Expect: head = the migration before 0515; new_fns 0; the bodies
--   level_perk e2ed74ab, level_benefits 54562cb0, level_arrival 40bc8597, fleet_wage 8b6ff54d, bargain_p1 83b4750e, tax_home_half e4f27883.
-- A different digest: 0515 refuses at the push when its hunk counts differ.
-- ROLLBACK: the switches false (the owner's).
begin transaction read only;
select json_build_object(
  'at', now(),
  'gate', json_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(c.relpages)::numeric * 8192 / 1048576)::int from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knobs', (select coalesce(json_object_agg(c.key, c.value), '{}'::json) from public.world_config c where c.key in ('management_level_enabled', 'trade_benefits_enabled', 'trade_tax_keep', 'level_unlocks_enabled', 'level_perks_on')),
  'new_fns', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('management_on', 'trade_tax_cut', 'job_wait_s', 'job_sail_xp')),
  'client_reach', (select coalesce(bool_or(has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute')), false)
                     from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('management_on', 'trade_tax_cut', 'job_wait_s', 'job_sail_xp')),
  'bodies', (select json_object_agg(p.proname, left(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), 8))
               from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('level_perk', 'level_benefits', 'level_arrival', 'fleet_wage', 'bargain_p1', 'tax_home_half'))
);
rollback;
