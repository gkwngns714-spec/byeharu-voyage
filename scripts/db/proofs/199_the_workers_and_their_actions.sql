-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 199 - THE WORKERS AND THEIR ACTIONS  (migration 0496; docs/design/hq-corp-2026-11-24.md A2.1, A2.2, A2.5, B3;
--             docs/dev-log/2026-11-24-workers-read.md)
--
--   world.workers() is HQ's one list of who does what; world.actions(worker) is the Assign sheet's options, in one shape, only what
--   the server would take. The migration's self-assert checks each figure against the quote it came from and sets every option
--   through the doors without starting a voyage. This proof plays a run through the real tick, shortens her reach, and stops a party
--   at the away cap. Rolled back by proof.mjs. (199: 198 is left free for 0495.)
--
-- @pass WR_SHAPE   every option of a fleet and of a party carries the whole shape (A2.1), its ids are distinct, per hour = net over the interval (a repeating run: its day's coin over its day's seconds; the Best run: none)
-- @pass WR_DOOR    every option served, at home and in a second harbour, is taken by cmd.set_fleet_job; a party's by cmd.land_send
-- @pass WR_CYCLE   a run there and back lasts longer than the same card one way (the Best run), by its sail back and a dock turn, and earns less by the sail back's cost
-- @pass WR_RANGE   with her reach shortened no run is offered past it: the far trip is shut by the leg judge, and what is still offered is still taken
-- @pass WR_TICK    a run set from an option is started by the tick: her row is working, its stamps are the voyage's, its leg is out; her BUY's ledger row carries her fleet
-- @pass WR_RUNS    her own runs (three BUYs since the job was set) replace the quote: basis runs, two whole runs, coin and experience an hour from her rows
-- @pass WR_AWAY    a party past the away cap is stopped (cap) on her row and in world.away_report's parties, with its turns come home; the report's old keys stand
-- @pass WR_COST    world.workers() and world.actions() timed here (printed, never judged: a proof must not depend on the machine's speed); no option is left out by the clock
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_a     constant uuid := '00000000-0496-4000-8000-0000000001a1';
  c_keys  constant text[] := array['id', 'kind', 'skill', 'level', 'interval_s', 'inputs', 'outputs', 'xp', 'cost', 'net', 'per_hour',
                                   'xp_per_hour', 'items_per_hour', 'basis'];
  v_lis   uuid;
  v_home  text;
  v_a     uuid;
  v_fa    uuid;
  v_x     uuid;
  v_xc    text;
  v_w     jsonb;
  v_o     jsonb;
  v_o2    jsonb;
  v_l     jsonb;
  v_e     jsonb;
  v_b     jsonb;
  v_f     jsonb;
  v_r     jsonb;
  v_rep   jsonb;
  v_base  jsonb;
  v_far   text;
  v_n     int := 0;
  v_n0    int;
  v_t     timestamptz;
  v_ms_w  numeric;
  v_ms_a  numeric;
  v_ms_p  numeric;
  v_turn  numeric := world.trip_stop_seconds();
begin
  v_a := public.new_house(c_a, 'Casa dos Obreiros 199', 'PRT');
  select f.id, f.port_id into v_fa, v_lis from public.fleets f where f.player_id = v_a;
  v_home := (select p.code from public.ports p where p.id = v_lis);
  update public.players p set ducats = 5000000 where p.id = v_a;
  update public.world_config set value = 'true'::jsonb where key in ('fleet_jobs_enabled', 'sea_courses_enabled', 'land_enabled', 'assign_home_enabled');
  perform cmd.assume_identity(c_a);

  -- ── WR_COST (measured first, on a quiet scene) ──
  v_t := clock_timestamp();
  v_w := world.workers();
  v_ms_w := round(extract(epoch from clock_timestamp() - v_t)::numeric * 1000, 1);
  v_t := clock_timestamp();
  v_o := world.actions('fleet:' || v_fa);
  v_ms_a := round(extract(epoch from clock_timestamp() - v_t)::numeric * 1000, 1);
  v_t := clock_timestamp();
  v_l := world.actions('party:1');
  v_ms_p := round(extract(epoch from clock_timestamp() - v_t)::numeric * 1000, 1);
  -- the times are printed at the end and never judged. What is judged: the read was not closed for slowness, and `cut` is the count's
  -- alone (true exactly when more than eight single runs could be offered)
  if jsonb_typeof(v_o->'closed') <> 'null' or jsonb_typeof(v_l->'closed') <> 'null' or (v_l->>'cut')::boolean
     or ((v_o->>'cut')::boolean and (select count(*) from jsonb_array_elements(v_o->'options') e where e->>'id' like 'sea:fixed:%:sell') < 8) then
    raise exception 'WR_COST: an option was left out other than by the count of eight runs: fleet cut % closed %, party cut % closed %', v_o->'cut', v_o->'closed', v_l->'cut', v_l->'closed';
  end if;

  -- ── WR_SHAPE ──
  if jsonb_array_length(v_o->'options') < 2 or jsonb_array_length(v_l->'options') < 1
     or exists (select 1 from jsonb_array_elements((v_o->'options') || (v_l->'options')) e, unnest(c_keys) k where not (e ? k))
     or (select count(distinct e->>'id') from jsonb_array_elements((v_o->'options') || (v_l->'options')) e)
          <> jsonb_array_length(v_o->'options') + jsonb_array_length(v_l->'options')
     or exists (select 1 from jsonb_array_elements((v_o->'options') || (v_l->'options')) e
                 where e->>'basis' <> 'quote' or jsonb_typeof(e->'interval_s') <> 'number' or (e->>'interval_s')::numeric <= 0
                    -- a run that repeats (`day`): its day's coin over its day's seconds, never above its first run repeated; the Best
                    -- run: no rate; any other: net over the interval
                    or case when e ? 'day' then (e->>'per_hour')::numeric <> round((e #>> '{day,coin}')::numeric * 3600 / (e #>> '{day,seconds}')::numeric)
                                                or (e #>> '{day,runs}')::numeric < 1
                                                or (e #>> '{day,coin}')::numeric > (e #>> '{day,runs}')::numeric * (e->>'net')::numeric + 1
                            when e->>'id' = 'sea:best' then jsonb_typeof(e->'per_hour') <> 'null'
                            else abs((e->>'per_hour')::numeric - (e->>'net')::numeric * 3600 / (e->>'interval_s')::numeric) > 2 + abs((e->>'per_hour')::numeric) * 0.02 end
                    or jsonb_typeof(e->'xp') <> 'array' or jsonb_typeof(e #> '{inputs,items}') <> 'array' or jsonb_typeof(e #> '{outputs,items}') <> 'array')
     or exists (select 1 from jsonb_array_elements(v_o->'options') e where e->>'kind' <> 'sea' or not (e ? 'job'))
     or exists (select 1 from jsonb_array_elements(v_l->'options') e where e->>'kind' not in ('gather', 'make') or not (e ? 'action')
                                                                         or (e #>> '{outputs,items,0,units}')::numeric < 1) then
    raise exception 'WR_SHAPE: an option is not in the one shape: % / %', left(v_o::text, 1200), left(v_l::text, 600);
  end if;
  raise notice 'PASS: WR_SHAPE — % sea options at % and % land jobs, each with the % keys of the shape, distinct ids, per hour = net over the interval (a repeating run: its day; the Best run: none)',
    jsonb_array_length(v_o->'options'), v_home, jsonb_array_length(v_l->'options'), cardinality(c_keys);

  -- ── WR_CYCLE: the Best run's card, one way, against the same card there and back ──
  v_b := v_o #> '{options,0}';
  select e into v_f from jsonb_array_elements(v_o->'options') e
   where e->>'id' = format('sea:fixed:%s:%s:%s:sell', v_b->>'good', v_b->>'buy', v_b->>'sell');
  if v_b->>'id' <> 'sea:best' or (v_b->>'returns')::boolean or v_f is null or (v_f->>'returns')::boolean is not true
     or (v_f->>'interval_s')::numeric <= (v_b->>'interval_s')::numeric
     or (v_f->>'net')::numeric > (v_b->>'net')::numeric
     or (v_f #>> '{inputs,coin}')::numeric <> (v_b #>> '{inputs,coin}')::numeric or (v_f #>> '{outputs,coin}')::numeric <> (v_b #>> '{outputs,coin}')::numeric
     or (v_b->>'net')::numeric - (v_f->>'net')::numeric
          <> (v_f #>> '{cost,back,wages}')::numeric + (v_f #>> '{cost,back,stores}')::numeric + (v_f #>> '{cost,back,dock_fee}')::numeric
     or (v_f #>> '{outputs,coin}')::numeric - (v_f #>> '{inputs,coin}')::numeric - (v_f #>> '{cost,total}')::numeric <> (v_f->>'net')::numeric then
    raise exception 'WR_CYCLE: a run there and back is not its card and its sail back: best % / fixed %', v_b, v_f;
  end if;
  raise notice 'PASS: WR_CYCLE — % % -> %: one way % s and % net; there and back % s and % net (the sail back and a dock turn of % s; its wages, stores and dock fees %)',
    v_b->>'good', v_b->>'buy', v_b->>'sell', v_b->>'interval_s', v_b->>'net', v_f->>'interval_s', v_f->>'net', v_turn, v_f #> '{cost,back}';

  -- ── WR_DOOR: every option, at home and in a second harbour (bring home among them), and a party's first job ──
  for v_e in select e from jsonb_array_elements(v_o->'options') e loop
    v_r := cmd.set_fleet_job(v_fa, v_e #>> '{job,kind}', v_e #> '{job,params}');
    if (v_r->>'ok')::boolean is not true or world.workers() #>> '{workers,0,action,id}' is distinct from v_e->>'id' then
      raise exception 'WR_DOOR: the door refused an option it was served at home: % / %', v_e, v_r;
    end if;
    v_n := v_n + 1;
  end loop;
  select k2.to_port, k2.code into v_x, v_xc from public.npc_known_legs(v_lis) k2 join public.ports p on p.id = k2.to_port
   where p.kind = 'HARBOUR' and public.fleet_job_course(v_fa, k2.to_port, v_lis) is not null order by k2.nm, k2.code limit 1;
  delete from public.fleet_jobs where fleet_id = v_fa;
  update public.fleets set port_id = v_x where id = v_fa;
  v_o2 := world.actions('fleet:' || v_fa);
  if not exists (select 1 from jsonb_array_elements(v_o2->'options') e where e->>'end' = 'store' and e->>'sell' = v_home
                                                                           and (e->>'items_per_hour')::numeric > 0 and (e->>'net')::numeric < 0)
     or exists (select 1 from jsonb_array_elements(v_o->'options') e where e->>'end' = 'store') then
    raise exception 'WR_DOOR: bring home is not offered away from home, or is offered at home: %', left(v_o2::text, 1500);
  end if;
  for v_e in select e from jsonb_array_elements(v_o2->'options') e loop
    v_r := cmd.set_fleet_job(v_fa, v_e #>> '{job,kind}', v_e #> '{job,params}');
    if (v_r->>'ok')::boolean is not true or world.workers() #>> '{workers,0,action,id}' is distinct from v_e->>'id' then
      raise exception 'WR_DOOR: the door refused an option it was served at %: % / %', v_xc, v_e, v_r;
    end if;
    v_n := v_n + 1;
  end loop;
  v_r := cmd.land_send(v_l #>> '{options,0,action}');
  if (v_r->>'ok')::boolean is not true or world.actions('party:1') #>> '{closed,code}' <> 'E_LAND_OUT'
     or world.workers() #>> '{workers,1,action,id}' <> v_l #>> '{options,0,id}' or world.workers() #>> '{workers,1,action,basis}' <> 'terms' then
    raise exception 'WR_DOOR: the land door refused a job it was served, or the party''s row is not that job: % / %', v_r, world.workers() #> '{workers,1}';
  end if;
  raise notice 'PASS: WR_DOOR — % sea options set through cmd.set_fleet_job (% at %, % at % with bring home), none refused; % sent through cmd.land_send, then closed E_LAND_OUT',
    v_n, jsonb_array_length(v_o->'options'), v_home, jsonb_array_length(v_o2->'options'), v_xc, v_l #>> '{options,0,action}';

  -- ── WR_RANGE: back at home, her reach shortened to 100 nm (this proof's alone) ──
  delete from public.fleet_jobs where fleet_id = v_fa;
  update public.fleets set port_id = v_lis where id = v_fa;
  select e->>'sell' into v_far from jsonb_array_elements(v_o->'options') e
   where e->>'id' like 'sea:fixed:%'
     and (select r.nm from voyage.reach_from(v_lis) r join public.ports p on p.id = r.port_id where p.code = e->>'sell') > 100
   order by e->>'id' limit 1;
  v_base := (select c.value from public.world_config c where c.key = 'nav_leg_nm_base');
  update public.world_config set value = to_jsonb(100) where key = 'nav_leg_nm_base';
  v_o2 := world.actions('fleet:' || v_fa);
  v_n0 := 0;
  if v_far is null or public.job_trip(v_fa, v_lis, array[v_far], false) #>> '{shut,code}' is distinct from 'E_LEG_TOO_FAR'
     or exists (select 1 from jsonb_array_elements(v_o2->'options') e where e->>'sell' = v_far)
     or jsonb_array_length(v_o2->'options') >= jsonb_array_length(v_o->'options') or v_o2 #>> '{options,0,id}' <> 'sea:best' then
    raise exception 'WR_RANGE: with a reach of 100 nm a run to % is still offered, or its trip is not shut: % / %', v_far,
      public.job_trip(v_fa, v_lis, array[v_far], false), left(v_o2::text, 1200);
  end if;
  for v_e in select e from jsonb_array_elements(v_o2->'options') e loop
    v_r := cmd.set_fleet_job(v_fa, v_e #>> '{job,kind}', v_e #> '{job,params}');
    if (v_r->>'ok')::boolean is not true then
      raise exception 'WR_RANGE: with a short reach the door refused an option it was served: % / %', v_e, v_r;
    end if;
    v_n0 := v_n0 + 1;
  end loop;
  update public.world_config set value = v_base where key = 'nav_leg_nm_base';
  raise notice 'PASS: WR_RANGE — reach 100 nm: the trip to % is shut (E_LEG_TOO_FAR) and no run there is offered; % of % options remain, each taken by the door',
    v_far, v_n0, jsonb_array_length(v_o->'options');

  -- ── WR_TICK: the run there and back from WR_CYCLE, started by the real tick ──
  v_r := cmd.set_fleet_job(v_fa, v_f #>> '{job,kind}', v_f #> '{job,params}');
  call public.tick_fleet_jobs(false);
  v_w := world.workers() #> '{workers,0}';
  if (select f.status from public.fleets f where f.id = v_fa) <> 'SAILING' or v_w->>'state' <> 'working' or v_w->>'worker_state' <> 'sea'
     or v_w #>> '{action,id}' <> v_f->>'id' or v_w #>> '{progress,leg}' <> 'out' or v_w #>> '{progress,to_port}' <> v_f->>'sell'
     or v_w #>> '{progress,from_port}' <> v_home
     or (v_w #>> '{progress,from}')::timestamptz <> (select v.departed_at from public.voyages v where v.fleet_id = v_fa and v.status = 'SAILING')
     or (v_w #>> '{progress,to}')::timestamptz <> (select coalesce(v.due_at, v.eta) from public.voyages v where v.fleet_id = v_fa and v.status = 'SAILING')
     or (v_w->>'runs')::int <> 1 or v_w #>> '{action,basis}' <> 'none'
     or not exists (select 1 from public.ledger l where l.player_id = v_a and l.kind = 'BUY' and l.fleet_id = v_fa) then
    raise exception 'WR_TICK: the run was not started, her row is not the voyage''s stamps, or her BUY carries no fleet: % (job %)', v_w,
      (select to_jsonb(j) from public.fleet_jobs j where j.fleet_id = v_fa);
  end if;
  raise notice 'PASS: WR_TICK — % is working: leg out to %, from % to %; her BUY''s ledger row carries her fleet', v_w->>'name', v_w #>> '{progress,to_port}',
    v_w #>> '{progress,from}', v_w #>> '{progress,to}';

  -- ── WR_RUNS: two earlier BUYs of hers, planted hours apart (a transaction has one instant: the tick's own BUY is her last, and the
  -- run it opens is not whole, so its rows are left out) ──
  update public.fleet_jobs set since = now() - interval '5 hours' where fleet_id = v_fa;
  insert into public.ledger (player_id, fleet_id, kind, ducats_delta, balance_after, created_at) values
    (v_a, v_fa, 'BUY',  -50000, 1, now() - interval '4 hours'),
    (v_a, v_fa, 'SELL',  60000, 1, now() - interval '3 hours'),
    (v_a, v_fa, 'BUY',  -50000, 1, now() - interval '2 hours'),
    (v_a, v_fa, 'SELL',  61000, 1, now() - interval '1 hour');
  v_w := world.workers() #> '{workers,0}';
  if v_w #>> '{action,basis}' <> 'runs' or (v_w->>'measured')::int <> 2 or (v_w #>> '{action,interval_s}')::numeric <> 7200
     or (v_w #>> '{action,per_hour}')::numeric <> 5250
     or (v_w #>> '{action,xp_per_hour}')::numeric <= 0 or v_w #>> '{action,id}' <> v_f->>'id' then
    raise exception 'WR_RUNS: her own runs are not read as written: %', v_w;
  end if;
  raise notice 'PASS: WR_RUNS — basis runs: % whole runs of % s, % coin an hour and % experience an hour, from her own ledger rows',
    v_w->>'measured', v_w #>> '{action,interval_s}', v_w #>> '{action,per_hour}', v_w #>> '{action,xp_per_hour}';

  -- ── WR_AWAY: her party, sent 13 hours ago and never looked at since ──
  update public.land_parties set started_at = started_at - interval '13 hours', touched_at = touched_at - interval '13 hours' where player_id = v_a;
  v_w := world.workers() #> '{workers,1}';
  v_rep := world.away_report();
  if v_w->>'state' <> 'stopped' or v_w #>> '{stop,code}' <> 'cap' or (v_w #>> '{progress,turns_home}')::int < 1
     or not (v_rep ? 'on' and v_rep ? 'company' and v_rep ? 'jobs' and v_rep ? 'since' and v_rep ? 'runs' and v_rep ? 'earned')
     or jsonb_array_length(v_rep->'jobs') <> 1 or v_rep #>> '{jobs,0,state}' <> 'working'
     or jsonb_array_length(v_rep->'parties') <> 1 or v_rep #>> '{parties,0,stop}' <> 'cap' or v_rep #>> '{parties,0,state}' <> 'stopped'
     or (v_rep #>> '{parties,0,turns_home}')::int <> (v_w #>> '{progress,turns_home}')::int
     or v_rep #>> '{parties,0,action}' <> v_l #>> '{options,0,action}' then
    raise exception 'WR_AWAY: a party past the cap is not stopped on her row and in the report, or the report lost a key: % / %', v_w, v_rep;
  end if;
  raise notice 'PASS: WR_AWAY — her party stopped at the away cap with % turns come home, on her row and in world.away_report (jobs, since, runs, earned kept; parties added)',
    v_rep #>> '{parties,0,turns_home}';

  raise notice 'PASS: WR_COST — world.workers() % ms, world.actions() % ms for a fleet and % ms for a party here (printed, not judged); nothing was left out by the clock',
    v_ms_w, v_ms_a, v_ms_p;
end $p$;
