-- BATCH 0499-0502, AFTER. A PROD CHECK: read-only, ONE statement (begin read only ... rollback), the gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/batch-0499-0502/after.sql
-- Gathers the slices' own checks (scripts/ops/harness/<slice>/), which stay the detail of each.
-- Expect: head 20260818000502; bodies_off []; missing []; reach [] (no new function callable by a client role or service_role);
--   knobs_off [] (the three switches false, the guard's share 0.5), since = the deploy; near_rounds 0 and waiting_guard 0 while dark;
--   failed_unfit_1h 0 an hour on; losses_since.rows = with_cost_key, negative 0. RED if not: forward rollback, as each slice's dev log says.
--   The 30-minute check is this file again: 0500 is live play (a fleet that cannot sail waits) and 0501 writes one key a day with a loss.
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
                   from (values ('cmd.do_hire(uuid,jsonb)', '2b720b5b00ae124fd6e8b4e7c88cf9a3'),
                                ('voyage.settle(uuid,timestamp with time zone)', '1809e424046a2dfb321f8345659702cd'),
                                ('cmd.queue(uuid)', 'cd1e52e4493c7315ead68748003f385d'),
                                ('public.fleet_job_note(uuid,jsonb)', '7d7077dd393d3446c9ed77b8dcf01266'),
                                ('public.fleet_job_set_for(uuid,uuid,text,jsonb)', '371fff91841004c1d37ee9eac9b79b2e'),
                                ('voyage.sail_refusal(uuid,uuid,jsonb,numeric,jsonb)', 'cc1b3504b99f8376975edc042b773c07'),
                                ('voyage.forced_home(uuid,integer,uuid)', '99e30283333001752a30dc5a664ee93e'),
                                ('public.fleet_job_plan(uuid)', '9fd27da51a010f8f8d449718af0ff1e4'),
                                ('voyage.navy_meets(uuid,integer,uuid,uuid,timestamp with time zone)', '96e74ac773b2508071c35a64537aadaf'),
                                ('public.fleet_jobs_due()', 'f2d229aed2876f3ae01a8bf84422e60b'),
                                ('public.tick_fleet_jobs(boolean)', '97b92b12ee33e6a793169e20511c1175'),
                                ('public.workers_for(uuid)', '1f5b3cb1daa4dea49b5b6c4a4743c60a'),
                                ('public.sea_actions_for(uuid,uuid)', '29b59df20ec44a70f7a06cd845aa366b'),
                                ('public.fleet_job_open(uuid,jsonb)', 'e954683f9178003d17a15acf550651d6'),
                                ('public.company_rate_for(uuid)', '1891ecfda6170d9a434166e253ea2df3'),
                                ('public.lines_nm(jsonb)', '096ef70b0b9114899c0d87e19b011a71'),
                                ('public.near_round_on()', 'c6e96f8eafb58ee7b7d31907da5bc819'),
                                ('public.near_round_sentence(text)', '8f48b70c2568866854245ac280d8b9e2'),
                                ('public.near_round_action(uuid)', 'c3e20213ca872244a3a5f7367852a0ac'),
                                ('public.run_need(uuid,uuid,uuid,jsonb)', 'eaa3c9c09df55cf2bc39f6527c18a74c'),
                                ('public.run_cut(jsonb,text)', '6d3c4c021e1cdec9ba536583dfc13fc6'),
                                ('public.near_round_params(uuid,jsonb)', '72cf4ca74cd734ecd306ec7e9e89303f'),
                                ('public.fleet_unfit(uuid)', 'fa82c78c4da1f8cde4c6c3e768c62faa'),
                                ('public.port_hires(uuid)', '4ec89e78a40bd2a38d3b9cb3a43108a6'),
                                ('public.cargo_at_cost_on()', '2f735b2d868f929de4604e389ad002b5'),
                                ('public.cargo_rate_for(uuid)', '6ce21b8b509656697a8e7d5e9d86e05c'),
                                ('public.run_guard_on()', '6e9dddd88d8717c9290dbaf6b418401c')) w(fn, want)
                  cross join lateral (select md5(replace(pg_get_functiondef(to_regprocedure(w.fn)), E'', '')) as have) h
                  where h.have is distinct from w.want),
  'missing', (select coalesce(json_agg(u.s), '[]'::json) from unnest(array['public.lines_nm(jsonb)', 'public.near_round_on()', 'public.near_round_sentence(text)', 'public.near_round_action(uuid)', 'public.run_need(uuid,uuid,uuid,jsonb)', 'public.run_cut(jsonb,text)', 'public.near_round_params(uuid,jsonb)', 'public.fleet_unfit(uuid)', 'public.port_hires(uuid)', 'public.cargo_at_cost_on()', 'public.cargo_rate_for(uuid)', 'public.run_guard_on()']) u(s) where to_regprocedure(u.s) is null),
  'reach', (select coalesce(json_agg(u.s), '[]'::json) from unnest(array['public.lines_nm(jsonb)', 'public.near_round_on()', 'public.near_round_sentence(text)', 'public.near_round_action(uuid)', 'public.run_need(uuid,uuid,uuid,jsonb)', 'public.run_cut(jsonb,text)', 'public.near_round_params(uuid,jsonb)', 'public.fleet_unfit(uuid)', 'public.port_hires(uuid)', 'public.cargo_at_cost_on()', 'public.cargo_rate_for(uuid)', 'public.run_guard_on()']) u(s)
             where has_function_privilege('anon', to_regprocedure(u.s), 'execute') or has_function_privilege('service_role', to_regprocedure(u.s), 'execute')
                or (u.s like 'public.%' and has_function_privilege('authenticated', to_regprocedure(u.s), 'execute'))),
  'knobs_off', (select coalesce(json_agg(json_build_object('key', w.key, 'have', c.value)), '[]'::json)
                  from (values ('near_round_enabled', 'false'), ('cargo_at_cost_enabled', 'false'), ('run_guard_enabled', 'false'), ('run_guard_hull_share', '0.5')) w(key, want)
                  left join public.world_config c on c.key = w.key where c.value is distinct from w.want::jsonb),
  'since', (select c.value from public.world_config c where c.key = 'cargo_at_cost_since'),
  'near_rounds', (select count(*) from public.fleet_jobs j where j.params ? 'within'),
  'waiting_guard', (select count(*) from public.fleet_jobs j where j.last->>'wait' in ('purse', 'danger')),
  'waiting_unfit', (select count(*) from public.fleet_jobs j where j.paused_reason is null and j.last->>'wait' in ('E_FLAGSHIP_DISABLED', 'E_CREW_SHORT')),
  'stopped_unfit', (select count(*) from public.fleet_jobs j where j.paused_reason in ('E_FLAGSHIP_DISABLED', 'E_CREW_SHORT')),
  'failed_unfit_1h', (select count(*) from public.fleet_jobs j join public.orders o on o.fleet_id = j.fleet_id
                       where o.status = 'failed' and o.error_code in ('E_FLAGSHIP_DISABLED', 'E_CREW_SHORT') and o.executed_at > now() - interval '1 hour'),
  'ticks_1h', (select json_build_object('runs', count(*), 'max_ms', max(r.ms)) from public.fleet_job_runs r where r.at > now() - interval '1 hour'),
  'losses_since', (select json_build_object('rows', count(*), 'with_cost_key', count(*) filter (where ve.payload ? 'cargo_lost_cost'),
                                            'negative', count(*) filter (where (ve.payload->>'cargo_lost_cost')::numeric < 0))
                     from public.voyage_events ve
                    where ve.resolved_at >= (select (c.value #>> '{}')::timestamptz from public.world_config c where c.key = 'cargo_at_cost_since')
                      and ve.payload ? 'cargo_lost')
);
rollback;
