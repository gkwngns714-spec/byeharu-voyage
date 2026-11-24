-- 0492 A FLEET BRINGS HER GOODS HOME, BEFORE. A PROD CHECK: read-only, ONE statement (begin read only ... rollback), the gate's three figures.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/assign-bring-home/before-0492.sql
-- Expect: head 20260818000491; assign_home_enabled absent; the three new functions absent; the four hunked bodies equal to the chain's
--   world at 0491 (so each of 0492's ten hunks occurs there exactly once, as its self-assert proved on that world):
--   fleet_job_note cade4e2d7abf8482b89deac6ac629f0c, fleet_job_open f913c466afcad6267e90c8330aee99ec,
--   fleet_job_set_for a42a1906e19da8ba25e200894d0a7450, fleet_job_plan da43b2a3797de52c7b8ca578ebb4b258.
--   A different digest: 0492 refuses at the push (its hunk count), nothing changes.
-- Also: the jobs by kind and whether any carries end / times / left (none can: the door writes only good, buy, sell, stops).
-- Reads: arrivals_beats (5 minutes), pg_class, pg_stat_activity, world_config by key, the catalog, fleet_jobs (one row a job).
--   No function that writes is called. ROLLBACK: nothing to roll back (read only; ends with rollback).
begin transaction read only;
select json_build_object(
  'at', now(),
  'gate', json_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(c.relpages)::numeric * 8192 / 1048576)::int from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'switch', (select c.value from public.world_config c where c.key = 'assign_home_enabled'),
  'fleet_jobs_enabled', (select c.value from public.world_config c where c.key = 'fleet_jobs_enabled'),
  'new_fns', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where n.nspname = 'public' and p.proname in ('assign_home_on', 'fleet_job_end', 'fleet_job_ends')),
  'bodies', (select json_object_agg(p.proname, md5(replace(pg_get_functiondef(p.oid), E'\r', '')))
               from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname in ('fleet_job_set_for', 'fleet_job_plan', 'fleet_job_open', 'fleet_job_note')),
  'jobs', (select coalesce(json_object_agg(x.kind, x.n), '{}'::json)
             from (select j.kind, count(*) as n from public.fleet_jobs j group by j.kind) x),
  'jobs_with_new_keys', (select count(*) from public.fleet_jobs j where j.params ? 'end' or j.params ? 'times' or j.params ? 'left')
);
rollback;
