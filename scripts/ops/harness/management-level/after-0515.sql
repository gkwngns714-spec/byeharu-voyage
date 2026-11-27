-- 0515 MANAGEMENT LEVEL, AFTER. A PROD CHECK: read-only, ONE statement, the gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/management-level/after-0515.sql
-- Expect: head 0515; both switches false, trade_tax_keep 0.5; new_fns 4; client_reach false; the bodies
--   level_perk b41abac9, level_benefits 29aa89fd, level_arrival e2295b17, fleet_wage 29c4f0d1, bargain_p1 9b0bb19f, tax_home_half c92c593c;
-- management companies 0 while dark. LIT, 30 minutes on: companies grow with the jobs, top_xp at most 300 a day; the beat as before.
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
               from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('level_perk', 'level_benefits', 'level_arrival', 'fleet_wage', 'bargain_p1', 'tax_home_half')),
  'management', (select json_build_object('companies', count(*), 'top_xp', max(x.xp)) from public.level_xp x where x.skill = 'management')
);
rollback;
