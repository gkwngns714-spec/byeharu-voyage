-- 0518 / 0519 ROUNDS, BEFORE AND AFTER. A PROD CHECK: read-only, ONE statement, the gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/rounds/after.sql
-- Expect before 0518: tables 0, fns 0. After 0518: tables 2, fns 9. After 0519: fns 18 (13 more names: the doors and the read among them), client_reach 3 (the two doors
--   and the read), rounds_enabled false, on_rounds 0. LIT, 30 minutes on: on_rounds and runs grow with the Sends; the jobs' tick (job_ms) within 20 ms of before.
-- ROLLBACK: rounds_enabled false (the owner's switch).
begin transaction read only;
select json_build_object(
  'at', now(),
  'gate', json_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'switch', (select c.value from public.world_config c where c.key = 'rounds_enabled'),
  'tables', (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname in ('round_works', 'round_runs')),
  'fns', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('public', 'cmd', 'world') and (p.proname like 'round\_%' or p.proname in ('rounds_on', 'rounds'))),
  'client_reach', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('public', 'cmd', 'world') and (p.proname like 'round\_%' or p.proname in ('rounds_on', 'rounds'))
                      and has_function_privilege('authenticated', p.oid, 'execute')),
  'on_rounds', (select count(*) from public.fleets f where f.status = 'ROUNDS'),
  'job_ms', (select round(avg(r.ms), 1) from public.fleet_job_runs r where r.at > now() - interval '30 minutes')
);
rollback;
