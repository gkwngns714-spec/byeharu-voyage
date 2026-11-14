-- 0421 PROD CHECK, BEFORE the deploy, read-only, ONE statement:
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/pace-up/before.sql
-- Then read the gate itself once (scripts/ops/harness/db-health/gate.sql): gate_ok true, or do not deploy.
-- WANTED: head 20260818000420 (0419 and 0420 deployed first; if either is not, 0421 waits or is renumbered by the lead); applied false;
--   stats_schedule "6,36 * * * *" and stats_active true; pirate_add_minutes 10; contract_wind_retry_minutes 60; jobs: the 23 with their
--   cadences (keep this read: the after-check compares). 0421 REFUSES (nothing changed) if either knob is not its old value.
-- It reads cron.job (23 rows), world_config (two rows) and schema_migrations. No game table; no function but jsonb builders and now().
begin transaction read only;
select jsonb_build_object(
  'at', now(),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'applied', exists (select 1 from public.world_config wc where wc.key = 'pirate_add_minutes' and wc.description like '0421:%'),
  'stats_schedule', (select j.schedule from cron.job j where j.jobname = 'byeharu-voyage:stats'),
  'stats_active', (select j.active from cron.job j where j.jobname = 'byeharu-voyage:stats'),
  'pirate_add_minutes', (select wc.value from public.world_config wc where wc.key = 'pirate_add_minutes'),
  'contract_wind_retry_minutes', (select wc.value from public.world_config wc where wc.key = 'contract_wind_retry_minutes'),
  'jobs', (select jsonb_object_agg(j.jobname, j.schedule || case when j.active then '' else ' (inactive)' end) from cron.job j)
) as r;
commit;
