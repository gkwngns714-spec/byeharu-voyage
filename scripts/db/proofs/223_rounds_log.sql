-- ══════════════════════════════════════════════════════════════════════════════════
-- PROOF 223 - ROUNDS: THE READ, THE STOP RULE, REPEAT OR GO  (migration 0519; docs/design/rounds-2026-11-25.md)
--
--   The doors, the read and the job of rounds, through the real tick. Its own company, work and stores. Rolled back by proof.mjs.
--
-- @pass RL_DARK    dark: the read is {on: false}, the doors and the job refused
-- @pass RL_DOORS   lit: cmd.round_send and cmd.round_home; another company's fleet is refused; the read says what a round costs and no odds
-- @pass RL_LOG     the log keeps the last 20 lines, one a round, newest last, and the row stays small
-- @pass RL_REPEAT  a job set to repeat: the tick hires, provisions, sends; its stop passed the tick brings her in, restocks and sends her again; one wait for what is short
-- @pass RL_HOME    set to go home after one run: the job is cleared when she is back
-- @pass RL_AWAY    set from another harbour: she sails to her base first
-- @pass RL_COST    the jobs' tick with 100 fleets out and none over, in ms (fails over 20 ms a tick more than with none out)
-- ══════════════════════════════════════════════════════════════════════════════════
do $p$
declare
  c_a  constant uuid := '00000000-0223-4000-8000-0000000000a1';
  c_b  constant uuid := '00000000-0223-4000-8000-0000000000b2';
  v_a  uuid; v_f uuid; v_b uuid; v_fb uuid; v_lis uuid; v_base text; r jsonb; q jsonb; v_j record; v_sent timestamptz; i int; v_o text; t timestamptz; m0 numeric := 0; m1 numeric := 0; v_run record;
begin
  v_a := public.new_house(c_a, 'Casa da Prova 223', 'PRT');
  v_b := public.new_house(c_b, 'Outra Casa 223', 'PRT');
  select f.id, f.port_id into v_f, v_lis from public.fleets f where f.player_id = v_a;
  select f.id into v_fb from public.fleets f where f.player_id = v_b;
  update public.players set ducats = 1000000 where id in (v_a, v_b);
  update public.ports set crew_pool = 500 where id = v_lis;
  update public.world_config set value = 'true'::jsonb where key in ('fleet_jobs_enabled', 'sea_courses_enabled', 'ship_stores_separate');
  insert into public.round_works (code, ord, kind, word, skill, seconds, food_days, water_days, crew_pct) values ('w_probe', 1, 'sea', 'Probe', 'exploration', 600, 0.05, 0.05, 0.2);
  perform cmd.assume_identity(c_a);

  if world.rounds(v_f) is distinct from '{"on": false}'::jsonb or cmd.round_send(v_f, 'w_probe', '{}')->>'error_code' <> 'E_NOT_IN_USE' or cmd.set_fleet_job(v_f, 'round', '{"work": "w_probe"}')->>'error_code' <> 'E_NOT_IN_USE' then
    raise exception 'RL_DARK: %', world.rounds(v_f);
  end if;
  raise notice 'PASS: RL_DARK - {on: false}, E_NOT_IN_USE twice';

  update public.world_config set value = 'true'::jsonb where key = 'rounds_enabled';
  update public.ships s set crew = (select sb.crew_max from public.ship_base(s.id) sb), food_t = 30, water_t = 60 where s.fleet_id in (v_f, v_fb);
  r := cmd.round_send(v_fb, 'w_probe', '{}');
  q := cmd.round_send(v_f, 'w_probe', '{"rounds": 40, "days": 0}');
  if r->>'error_code' is distinct from 'E_NO_SUCH_FLEET' or not (q->>'ok')::boolean or position('odds' in world.rounds(v_f)::text) + position('chance' in world.rounds(v_f)::text) > 0
     or (world.rounds(v_f) #>> '{works,0,terms,most}') is null or (world.rounds(null) #> '{works}') <> '[]'::jsonb or world.rounds(v_f) #>> '{runs,0,cost,food}' is null then
    raise exception 'RL_DOORS: % % %', r, q, world.rounds(v_f);
  end if;
  raise notice 'PASS: RL_DOORS - sent for % rounds (%); a round costs %; another company''s fleet: %', q #>> '{terms,most}', q #>> '{terms,why}', world.rounds(v_f) #> '{runs,0,cost}', r->>'error_code';

  perform public.round_settle(v_f, now() + interval '250 minutes');
  q := world.rounds(v_f) #> '{runs,0}';
  if jsonb_array_length(q->'log') <> 20 or (q #>> '{log,-1,r}')::int <> 25 or (q #>> '{log,0,r}')::int <> 6 or (select pg_column_size(z.*) from public.round_runs z where z.fleet_id = v_f) > 4000 then
    raise exception 'RL_LOG: %', q;
  end if;
  raise notice 'PASS: RL_LOG - 25 rounds, lines 6 to 25 kept, the row % bytes', (select pg_column_size(z.*) from public.round_runs z where z.fleet_id = v_f);
  perform cmd.round_home(v_f);

  -- RL_REPEAT
  update public.ships s set crew = (select sb.crew_max from public.ship_base(s.id) sb) - 2, food_t = 0, water_t = 0 where s.fleet_id = v_f;
  r := cmd.set_fleet_job(v_f, 'round', '{"work": "w_probe", "days": 15, "stop": {"rounds": 4, "days": 0}, "then": "repeat"}'::jsonb
                           || jsonb_build_object('crew', (select sum((select sb.crew_max from public.ship_base(s.id) sb)) from public.ships s where s.fleet_id = v_f)));
  call public.tick_fleet_jobs(false);
  call public.tick_fleet_jobs(false);
  select string_agg(o.raw_text, ', ' order by o.seq) into v_o from public.orders o where o.fleet_id = v_f;
  select z.* into v_run from public.round_runs z where z.fleet_id = v_f;
  v_sent := v_run.sent_at;
  if v_run.state <> 'out' or (v_run.terms->>'most')::int <> 4 or v_o !~ 'HIRE 2, PROVISION DAYS 15' or (world.workers() #>> '{workers,0,state}') <> 'working' then
    raise exception 'RL_REPEAT: % / % / %', to_jsonb(v_run), v_o, (select to_jsonb(j) from public.fleet_jobs j where j.fleet_id = v_f);
  end if;
  update public.round_runs set sent_at = sent_at - interval '1 hour', stop_at = stop_at - interval '1 hour' where fleet_id = v_f;
  update public.fleets set busy_until = busy_until - interval '1 hour' where id = v_f;
  call public.tick_fleet_jobs(false);
  call public.tick_fleet_jobs(false);
  select z.* into v_run from public.round_runs z where z.fleet_id = v_f;
  if v_run.state <> 'out' or v_run.sent_at <> v_sent or (select f.status from public.fleets f where f.id = v_f) <> 'ROUNDS'
     or (select count(*) from public.events e where e.player_id = v_a and e.kind = 'ROUNDS_DONE') <> 1 then
    raise exception 'RL_REPEAT: not sent again: % / %', to_jsonb(v_run), (select to_jsonb(j) from public.fleet_jobs j where j.fleet_id = v_f);
  end if;
  -- short of stores and none to be taken on: it waits, not stopped
  perform cmd.round_home(v_f);
  update public.ships s set food_t = 0, water_t = 0 where s.fleet_id = v_f;
  update public.fleet_jobs set params = params - 'days' - 'crew' where fleet_id = v_f;
  call public.tick_fleet_jobs(false);
  if (world.workers() #>> '{workers,0,wait,code}') is distinct from 'range' or (world.workers() #>> '{workers,0,wait,sentence}') !~ '^not enough' then
    raise exception 'RL_REPEAT: short: %', world.workers() #> '{workers,0}';
  end if;
  raise notice 'PASS: RL_REPEAT - %; 4 rounds; brought in and sent again by the tick; short: "%"', v_o, world.workers() #>> '{workers,0,wait,sentence}';

  -- RL_HOME
  update public.ships s set food_t = 30, water_t = 60 where s.fleet_id = v_f;
  r := cmd.set_fleet_job(v_f, 'round', '{"work": "w_probe", "stop": {"rounds": 2}, "then": "home"}');
  call public.tick_fleet_jobs(false);
  if (select f.status from public.fleets f where f.id = v_f) <> 'ROUNDS' then raise exception 'RL_HOME: not sent'; end if;
  update public.fleet_jobs set since = since - interval '2 hours' where fleet_id = v_f;
  update public.round_runs set sent_at = sent_at - interval '1 hour', stop_at = stop_at - interval '1 hour' where fleet_id = v_f;
  update public.fleets set busy_until = busy_until - interval '1 hour' where id = v_f;
  call public.tick_fleet_jobs(false);
  if exists (select 1 from public.fleet_jobs j where j.fleet_id = v_f) or (select f.status from public.fleets f where f.id = v_f) <> 'DOCKED' then
    raise exception 'RL_HOME: %', (select to_jsonb(j) from public.fleet_jobs j where j.fleet_id = v_f);
  end if;
  raise notice 'PASS: RL_HOME - two rounds, home, the job cleared';

  -- RL_AWAY
  select k.code into v_base from public.npc_known_legs(v_lis) k join public.ports h on h.id = k.to_port and h.kind = 'HARBOUR' and h.sea_id is not null order by k.nm limit 1;
  r := cmd.set_fleet_job(v_f, 'round', jsonb_build_object('work', 'w_probe', 'base', v_base));
  q := public.fleet_job_plan(v_f);
  if not (r->>'ok')::boolean or q #>> '{lines,0,text}' !~ '^SAIL ' then
    raise exception 'RL_AWAY: % %', r, q;
  end if;
  raise notice 'PASS: RL_AWAY - %', q #>> '{lines,-1,text}';
  perform cmd.clear_fleet_job(v_f);

  -- RL_COST
  for i in 1 .. 10 loop
    t := clock_timestamp(); call public.tick_fleet_jobs(false); m0 := m0 + extract(epoch from clock_timestamp() - t) * 1000;
  end loop;
  for i in 1 .. 100 loop
    r := jsonb_build_object('p', public.new_house(('00000000-0223-4000-9000-' || lpad(i::text, 12, '0'))::uuid, 'Casa Cento ' || i, 'PRT'));
    select f.id into v_fb from public.fleets f where f.player_id = (r->>'p')::uuid;
    update public.ships s set crew = (select sb.crew_max from public.ship_base(s.id) sb), food_t = 30, water_t = 60 where s.fleet_id = v_fb;
    perform public.round_send_for((r->>'p')::uuid, v_fb, 'w_probe', '{"days": 0}', now());
  end loop;
  for i in 1 .. 10 loop
    t := clock_timestamp(); call public.tick_fleet_jobs(false); m1 := m1 + extract(epoch from clock_timestamp() - t) * 1000;
  end loop;
  if (m1 - m0) / 10 > 20 then raise exception 'RL_COST: % ms more a tick', round((m1 - m0) / 10, 2); end if;
  t := clock_timestamp();
  i := public.round_settle_due(now() + interval '2 days', 20);
  raise notice 'PASS: RL_COST - the tick % ms with none out, % ms with 100 out; a tick that brings 20 in: % ms', round(m0 / 10, 2), round(m1 / 10, 2), round(extract(epoch from clock_timestamp() - t) * 1000, 1);
end $p$;
