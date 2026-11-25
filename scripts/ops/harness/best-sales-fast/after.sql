-- 0536 BEST SALES, FASTER, AFTER; ALSO THE 30-MINUTE CHECK. A PROD CHECK: read-only, ONE statement, the gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/best-sales-fast/after.sql
-- Expect: head 20260818000536; bodies_off []; missing []; reach []; ticks: the last runs of the job tick that asked a job, their plan_ms lower than before
--   the deploy (4,300 to 5,900 at second 0); waiting 'slow' 0 or falling. ROLLBACK: 0536's header (forward).
begin transaction read only;
select json_build_object(
  'at', now(),
  'gate', json_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'bodies_off', (select coalesce(json_agg(json_build_object('fn', w.fn, 'have', h.have)), '[]'::json)
                   from (values ('public.tick_fleet_jobs(boolean)', 'e59efc531e499eb4a9d8b080695630ba'),
                                ('public.fleet_job_note(uuid,jsonb)', '08fb9b21fefe9287af61521b4e1c4e97'),
                                ('public.stores_cost(uuid,numeric,numeric)', '6cd3d8660b6b6ce9f2033def2a7ee0af'),
                                ('public.stores_topup(numeric,numeric,numeric,numeric,numeric,numeric)', '982eccb703db3bb98ab4bb8bcb176ca6'),
                                ('voyage.reach_passage(uuid,uuid,uuid,numeric)', '74095304d1b818ab0edbc3fff84fbdbb'),
                                ('voyage.ship_speed_of(jsonb,numeric)', '5edabca51d62bf2d774c125ea609af9f'),
                                ('voyage.stores_need_days(numeric,numeric)', '00bbf5c2f10a8967990358337577a65b'),
                                ('world.best_sales(uuid,uuid)', '159a0125f0c6047f9bf9d38f00062506'),
                                ('world.board_sell_memo(uuid,uuid,jsonb,jsonb)', '2d4a94e5ad82747f4d76ee114e4d31d3'),
                                ('world.board_trips(uuid,jsonb,jsonb)', '2f2f611951182b030107acd72d6e2508'),
                                ('world.trip_leg(jsonb,jsonb,numeric,boolean,numeric)', 'ba650593e984c11448a1fd346eb4287a')) w(fn, want)
                  cross join lateral (select md5(replace(pg_get_functiondef(to_regprocedure(w.fn)), E'', '')) as have) h
                  where h.have is distinct from w.want),
  'missing', (select coalesce(json_agg(u.s), '[]'::json) from unnest(array['public.job_tick_wait_s(numeric,text)', 'public.stores_cost_of(numeric,numeric,numeric[])', 'public.stores_cost_terms(uuid)', 'public.stores_topup_of(numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric)', 'voyage.ship_speed_fill(numeric,numeric,numeric)', 'voyage.stores_need_days_of(numeric,numeric,numeric)', 'world.legs_rank(jsonb)', 'world.trip_arrays(jsonb,jsonb)', 'world.trip_hulls_at(jsonb,numeric[],numeric[])', 'world.trip_knobs()', 'world.trip_leg_of(numeric[],numeric[],numeric[],numeric[],numeric[],numeric[],numeric[],numeric,numeric,numeric,numeric,numeric[],numeric[],numeric,boolean,numeric)']) u(s) where to_regprocedure(u.s) is null),
  'reach', (select coalesce(json_agg(u.s), '[]'::json) from unnest(array['public.job_tick_wait_s(numeric,text)', 'public.stores_cost_of(numeric,numeric,numeric[])', 'public.stores_cost_terms(uuid)', 'public.stores_topup_of(numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric)', 'voyage.ship_speed_fill(numeric,numeric,numeric)', 'voyage.stores_need_days_of(numeric,numeric,numeric)', 'world.legs_rank(jsonb)', 'world.trip_arrays(jsonb,jsonb)', 'world.trip_hulls_at(jsonb,numeric[],numeric[])', 'world.trip_knobs()', 'world.trip_leg_of(numeric[],numeric[],numeric[],numeric[],numeric[],numeric[],numeric[],numeric,numeric,numeric,numeric,numeric[],numeric[],numeric,boolean,numeric)']) u(s)
             where has_function_privilege('anon', to_regprocedure(u.s), 'execute') or has_function_privilege('authenticated', to_regprocedure(u.s), 'execute')
                or has_function_privilege('service_role', to_regprocedure(u.s), 'execute')),
  'ticks', (select json_agg(json_build_object('at', r.at, 'ms', r.ms, 'steps', r.receipt->'steps') order by r.at desc)
              from (select * from public.fleet_job_runs x where x.at > now() - interval '40 minutes' and jsonb_array_length(x.receipt->'steps') > 0 order by x.at desc limit 8) r),
  'slow_waits', (select count(*) from public.fleet_jobs j where j.last->>'wait' in ('slow', 'unpriced'))) as after_0536;
rollback;
