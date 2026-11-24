-- 0494 A JOB SAILS HARBOUR BY HARBOUR, BEFORE. A PROD CHECK: read-only, ONE statement (begin read only ... rollback), the gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/job-by-harbours/before-0494.sql
-- Expect: head 20260818000493; new_fns 0; the seven hunked bodies equal to the chain's world at 0492 (so each of 0494's ten hunks
--   occurs there exactly once, as its self-assert proved on that world):
--   fleet_job_sails f394486811dc39759858f6b6110b1fb2, fleet_job_plan ce29b861184739a88e7338e943efdb81,
--   fleet_job_set_for 80862433b1f0ad64929d420481947ef0, fleet_jobs_due cb87ce191ea8691ccd9ca792e34365b8,
--   fleet_job_open 734896f692eec81e9770350089e09358, fleet_job_note 070bf65c97c9306e58504976593ee258,
--   tick_fleet_jobs 8c9eb0eb59bad10b0726a85ab71c4109. A different digest: 0494 refuses at the push (its hunk count), nothing changes.
--   The self-assert plays its own scene: harbours ISL and LIS, a new house's reach (nav_leg_nm_base, 1700) shorter than ISL -> LIS, and
--   a chain of harbours between them: `scene_chain` must not be null (local: SOF, CPT, LUA, CAP, SAI, LPA). Null: the push would
--   refuse (nothing changes); tell the builder instead of pushing.
-- Also: `stopped`: the jobs stopped, by code. `retry`: the (at most 3) jobs stopped on E_LEG_TOO_FAR / E_ENDURANCE that 0494's tick will
--   plan again, each with where she lies, where the stopped run was going, and the harbours between as the pathfinder gives them now
--   (`chain` null: she stays stopped, with the new sentence). The owner's reported job is one of them (lies_at ISL, was_going_to LIS).
-- Reads: arrivals_beats (5 minutes), pg_class, pg_stat_activity, world_config by key, the catalog, fleet_jobs (one row a job), fleets,
--   ports. Functions called (all STABLE, provolatile 's'): voyage.reach_passage (at most 4 calls, each one Dijkstra over the kept
--   matrix), public.supply_reach, public.passage_reach_nm. No function that writes is called. ROLLBACK: nothing (read only).
begin transaction read only;
select json_build_object(
  'at', now(),
  'gate', json_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(c.relpages)::numeric * 8192 / 1048576)::int from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knobs', (select json_object_agg(c.key, c.value) from public.world_config c
             where c.key in ('fleet_jobs_enabled', 'sea_courses_enabled', 'land_enabled', 'assign_home_enabled', 'nav_leg_nm_base', 'sea_conditions_bite')),
  'new_fns', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where n.nspname = 'public' and p.proname in ('fleet_job_legs', 'fleet_job_leg_shut')),
  'bodies', (select json_object_agg(p.proname, md5(replace(pg_get_functiondef(p.oid), E'\r', '')))
               from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname in ('fleet_job_sails', 'fleet_job_plan', 'fleet_job_set_for', 'fleet_jobs_due',
                                                           'fleet_job_open', 'fleet_job_note', 'tick_fleet_jobs')),
  'scene_chain', (select to_json(r.stops)
                    from voyage.reach_passage((select pl.id from public.players pl where not pl.is_npc order by pl.created_at limit 1), null,
                                              (select p.id from public.ports p where p.code = 'ISL' and p.kind = 'HARBOUR'),
                                              (select c.value::text::numeric from public.world_config c where c.key = 'nav_leg_nm_base')) r
                   where r.code = 'LIS' and r.nm is not null),
  'stopped', (select coalesce(json_object_agg(x.code, x.n), '{}'::json)
                from (select j.paused_reason as code, count(*) as n from public.fleet_jobs j where j.paused_reason is not null group by 1) x),
  'retry', (select coalesce(json_agg(json_build_object(
                     'fleet', j.fleet_id, 'kind', j.kind, 'params', j.params, 'code', j.paused_reason, 'at', j.last->>'at',
                     'lies_at', p.code, 'fleet_status', f.status, 'was_going_to', j.last->>'to',
                     'reach_nm', public.passage_reach_nm(j.player_id),
                     'chain', (select to_json(r.stops)
                                 from voyage.reach_passage(j.player_id, j.fleet_id, f.port_id, (select sr.cap_nm from public.supply_reach(j.fleet_id) sr)) r
                                where r.code = j.last->>'to' and r.nm is not null))), '[]'::json)
              from (select * from public.fleet_jobs x where x.paused_reason in ('E_LEG_TOO_FAR', 'E_ENDURANCE') order by x.since limit 3) j
              join public.fleets f on f.id = j.fleet_id
              left join public.ports p on p.id = f.port_id)
);
rollback;
