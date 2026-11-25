-- BATCH 0499-0502, BEFORE. A PROD CHECK: read-only, ONE statement (begin read only ... rollback), the gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/batch-0499-0502/before.sql
-- Gathers the slices' own checks (scripts/ops/harness/<slice>/), which stay the detail of each.
-- Expect: head 20260818000498; bodies_off [] (each body this batch cuts is the one the hunks were written against: anything listed is
--   refused at the push by its own hunk count); new_there []; knobs_there []; sea_conditions_bite false (LIT, 0500's self-assert refuses:
--   its scene's Cadiz plan has no lines); payers >= 1 (one new company a file is founded and rolled back, by a city with 40,000 above its
--   reserve); long_tx 0 (an open transaction over 4 s may hold a lock the push waits 5 s for). The other figures are for the record:
--   stopped_unfit = jobs that stay stopped until her repair or hire; days_with_loss_24h.with_cost_key 0.
-- Reads: arrivals_beats (5 minutes), pg_class, pg_stat_activity, the catalog, world_config by key, small tables by count. Only STABLE functions are
--   called, none writes. The digests are of the local chain's world (PGlite, migrations to 0502).
begin transaction read only;
select json_build_object(
  'at', now(),
  'gate', json_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(k.relpages)::numeric * 8192 / 1048576)::int from pg_class k where k.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'bodies_off', (select coalesce(json_agg(json_build_object('fn', w.fn, 'have', h.have)), '[]'::json)
                   from (values ('cmd.do_hire(uuid,jsonb)', '6d5b7597b774324ddf6cce55c63d9ec6'),
                                ('voyage.settle(uuid,timestamp with time zone)', '2c355ceab0dcbeeea9c16b9f068290bf'),
                                ('cmd.queue(uuid)', '2c6f47f5fad07a2bd5a5dee007a3446a'),
                                ('public.fleet_job_note(uuid,jsonb)', '2c839e389ae260d91e8f36efa7c0bcee'),
                                ('public.fleet_job_set_for(uuid,uuid,text,jsonb)', '2e7e57044367984e12c391cb7ac60f87'),
                                ('voyage.sail_refusal(uuid,uuid,jsonb,numeric,jsonb)', '93165e5c990ff77fcd11bea3e65f1f2d'),
                                ('voyage.forced_home(uuid,integer,uuid)', 'db19e356d987657236f0047de3e9d4c1'),
                                ('public.fleet_job_plan(uuid)', '4d2005b521b67c65402d3583bd3ebe71'),
                                ('voyage.navy_meets(uuid,integer,uuid,uuid,timestamp with time zone)', '54ca2ed731ba0126e08b38bec418287d'),
                                ('public.fleet_jobs_due()', 'f471e46c71a83975ff3835c3cc1fd0d8'),
                                ('public.tick_fleet_jobs(boolean)', 'dc01d64892573005bd41fb6d41b6efd4'),
                                ('public.workers_for(uuid)', '92e967064bb7f430f1a26236e74342b7'),
                                ('public.sea_actions_for(uuid,uuid)', 'd106595a5cfe9d40073d543cc734880e'),
                                ('public.fleet_job_open(uuid,jsonb)', 'fc3fe1f07ad8806475f8949ba4812097'),
                                ('public.company_rate_for(uuid)', 'ab4eae880c37d9eb3042980e718f96f3')) w(fn, want)
                  cross join lateral (select md5(replace(pg_get_functiondef(to_regprocedure(w.fn)), E'', '')) as have) h
                  where h.have is distinct from w.want),
  'new_there', (select coalesce(json_agg(u.s), '[]'::json) from unnest(array['public.lines_nm(jsonb)', 'public.near_round_on()', 'public.near_round_sentence(text)', 'public.near_round_action(uuid)', 'public.run_need(uuid,uuid,uuid,jsonb)', 'public.run_cut(jsonb,text)', 'public.near_round_params(uuid,jsonb)', 'public.fleet_unfit(uuid)', 'public.port_hires(uuid)', 'public.cargo_at_cost_on()', 'public.cargo_rate_for(uuid)', 'public.run_guard_on()']) u(s) where to_regprocedure(u.s) is not null),
  'knobs_there', (select coalesce(json_agg(c.key), '[]'::json) from public.world_config c where c.key in ('near_round_enabled', 'cargo_at_cost_enabled', 'cargo_at_cost_since', 'run_guard_enabled', 'run_guard_hull_share')),
  'switches', (select json_object_agg(c.key, c.value) from public.world_config c where c.key in ('economy_closed', 'city_treasury_enabled', 'jobs_wait_enabled', 'wreck_sells_enabled', 'fleet_jobs_enabled', 'influence_enabled')),
  'payers', (select count(*) from public.port_treasury t where t.ducats - t.reserve >= 40000),
  'founding_room', (select coalesce(sum(floor((t.ducats - t.reserve) / 40000)), 0) from public.port_treasury t where t.ducats - t.reserve >= 40000),
  'long_tx', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.state <> 'idle' and a.xact_start < now() - interval '4 seconds' and a.backend_type = 'client backend'),
  'sea_conditions_bite', (select c.value from public.world_config c where c.key = 'sea_conditions_bite'),
  'stopped_unfit', (select count(*) from public.fleet_jobs j where j.paused_reason in ('E_FLAGSHIP_DISABLED', 'E_CREW_SHORT')),
  'days_with_loss_24h', (select json_build_object('rows', count(*), 'with_cost_key', count(*) filter (where ve.payload ? 'cargo_lost_cost'))
                           from public.voyage_events ve where ve.resolved_at > now() - interval '24 hours' and ve.payload ? 'cargo_lost')
);
rollback;
