-- PACE-UP (0421) MEASURE 3 of 3, read-only, ONE statement: every pacing knob as production holds it (world_config: one row a knob, a few
-- hundred rows), by name: anything counted in minutes, seconds or milliseconds, a budget, a batch, a spread, a pace or a cap a run.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/pace-up/measure-knobs.sql
-- No game table. Functions: now(), jsonb builders, the ~ operator (immutable).
begin transaction read only;
select jsonb_build_object(
  'at', now(),
  'knobs', (select jsonb_object_agg(c.key, c.value order by c.key)
              from public.world_config c
             where c.key ~ '(minutes|seconds|_ms$|_every|every_|spread|budget|_runs$|per_run|batch|_max$|pace|per_minute|per_hour|compression|_slot)')
) as r;
commit;
