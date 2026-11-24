-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 197 - A JOB SAILS HARBOUR BY HARBOUR  (migration 0494; docs/design/remaster-2026-11-24.md "One travel rule";
--             docs/dev-log/2026-11-24-job-by-harbours.md)
--
--   The owner's report: a land job {"to": "CAD"}, her fleet at Island of Mozambique, stopped E_LEG_TOO_FAR on "Line 1 (SAIL LIS): that
--   leg is 7052 nm and your navigation carries you 1700 nm". The migration's self-assert runs that scene before its hunks (it stops, as
--   reported) and after (it starts). This proof plays every kind of job through the real tick and her real arrivals, and the retry.
--   Rolled back by proof.mjs. A voyage is brought to its end by moving its clock back (proof 184's way); the read that follows settles her.
--
-- @pass JH_REPORT   the reported case: the land job at ISL starts, one SAIL a harbour, every leg within her reach, and she SAILS IT ALL: she lies at Lisbon, no order failed
-- @pass JH_FIXED    a fixed job Lisbon -> ISL is taken by the door and its loaded run is BUY ALL / SAIL harbour by harbour / SELL ALL; she departs
-- @pass JH_HOME     a bring-home job whose buy harbour lies oceans away: her first sail to it goes harbour by harbour
-- @pass JH_BEST     a best sale's lines (public.sale_lines) from ISL to Lisbon are harbour by harbour, and the plan door takes them whole
-- @pass JH_RETRY    a job stopped E_LEG_TOO_FAR is left alone inside 10 minutes, re-planned after them and its stop lifted; E_ENDURANCE the same
-- @pass JH_NOLOOP   with no chain the retry stays stopped with a plain sentence, is stamped, and the next run asks nothing; a stop on another code is never retried
-- @pass JH_REFUSED  with no chain the door refuses a land, a fixed and a bring-home job when they are set (E_LEG_TOO_FAR, a plain sentence); nothing is written
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_a     constant uuid := '00000000-0494-4000-8000-0000000001a1';
  v_lis   uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_isl   uuid := (select p.id from public.ports p where p.code = 'ISL' and p.kind = 'HARBOUR');
  v_a     uuid;
  v_fa    uuid;
  v_reach numeric;
  v_x     uuid;
  v_xc    text;
  v_g     text;
  v_r     jsonb;
  v_p     jsonb;
  v_j     record;
  v_texts text;
  v_max   numeric;
  v_n     int;
  v_base  jsonb;
  v_orders bigint;
  n       int;
begin
  v_a := public.new_house(c_a, 'Casa do Caminho 197', 'PRT');
  select f.id into v_fa from public.fleets f where f.player_id = v_a;
  update public.players p set ducats = 5000000 where p.id = v_a;
  update public.world_config set value = 'true'::jsonb where key in ('fleet_jobs_enabled', 'sea_courses_enabled', 'land_enabled', 'assign_home_enabled');
  perform cmd.assume_identity(c_a);
  perform public.land_party(v_a);
  v_reach := public.passage_reach_nm(v_a);
  if (select r.nm from voyage.reach_from(v_isl) r where r.port_id = v_lis) <= v_reach then
    raise exception 'JH_REPORT: Island of Mozambique is within one leg of Lisbon in this world: the scene proves nothing';
  end if;

  -- JH_REPORT: her fleet at ISL, the land job as the owner had it
  update public.fleets set port_id = v_isl, status = 'DOCKED' where id = v_fa;
  insert into public.fleet_jobs (fleet_id, player_id, kind, params, since, seen_at) values (v_fa, v_a, 'land', '{"to": "CAD"}'::jsonb, now(), now());
  call public.tick_fleet_jobs(false);
  select * into v_j from public.fleet_jobs j where j.fleet_id = v_fa;
  select string_agg(o.raw_text, ' / ' order by o.seq), count(*),
         max((select sum((s->>'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course(o.args->'path')) s))
    into v_texts, v_n, v_max from public.orders o where o.fleet_id = v_fa and o.plan_id = v_j.last_plan;
  if v_j.paused_reason is not null or v_j.runs <> 1 or v_n < 2 or v_texts not like 'SAIL % / SAIL LIS' or v_max is null or v_max > v_reach
     or v_j.last->>'to' <> 'LIS' or world.away_report() #>> '{jobs,0,state}' <> 'working' then
    raise exception 'JH_REPORT: the land job at ISL did not start harbour by harbour: % (longest % of %; job %)', v_texts, v_max, v_reach, to_jsonb(v_j);
  end if;
  for n in 1 .. 40 loop
    exit when (select f.status from public.fleets f where f.id = v_fa) <> 'SAILING'
              and not exists (select 1 from public.orders o where o.fleet_id = v_fa and o.status in ('pending', 'active'));
    update public.voyages set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute'
     where fleet_id = v_fa and status = 'SAILING';
    perform world.fleets();
  end loop;
  if (select f.port_id from public.fleets f where f.id = v_fa) is distinct from v_lis
     or exists (select 1 from public.orders o where o.fleet_id = v_fa and o.status <> 'done') then
    raise exception 'JH_REPORT: she did not sail the whole chain to Lisbon: she lies at %, orders %',
      (select p.code from public.fleets f join public.ports p on p.id = f.port_id where f.id = v_fa),
      (select jsonb_agg(jsonb_build_object('t', o.raw_text, 's', o.status, 'e', o.error_code) order by o.seq) from public.orders o where o.fleet_id = v_fa);
  end if;
  raise notice 'PASS: JH_REPORT — % (% legs, the longest % of % nm), all sailed: she lies at Lisbon', v_texts, v_n, round(v_max), round(v_reach);

  -- JH_FIXED: at Lisbon, a fixed job to ISL in the good Lisbon offers most
  delete from public.fleet_jobs where fleet_id = v_fa;
  select g.code into v_g from public.port_goods pg join public.goods g on g.id = pg.good_id
   where pg.port_id = v_lis and public.port_offers(v_lis, g.id) and pg.stock > 0 and g.bulk > 0
     and not public.culture_refuses((select p.culture from public.ports p where p.id = v_lis), g.culture_mask)
   order by pg.stock_target desc, g.code limit 1;
  v_r := cmd.set_fleet_job(v_fa, 'fixed', jsonb_build_object('good', v_g, 'buy', 'LIS', 'sell', 'ISL'));
  call public.tick_fleet_jobs(false);
  select * into v_j from public.fleet_jobs j where j.fleet_id = v_fa;
  select string_agg(o.raw_text, ' / ' order by o.seq), count(*),
         max((select sum((s->>'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course(o.args->'path')) s))
    into v_texts, v_n, v_max from public.orders o where o.fleet_id = v_fa and o.plan_id = v_j.last_plan;
  if (v_r->>'ok')::boolean is not true or v_j.paused_reason is not null or v_j.runs <> 1 or v_n < 4
     or v_texts not like format('BUY %s ALL / SAIL %% / SAIL ISL / SELL %s ALL', v_g, v_g) or v_max is null or v_max > v_reach
     or (select f.status from public.fleets f where f.id = v_fa) <> 'SAILING' or public.fleet_cargo_qty(v_fa, v_g) < 1 then
    raise exception 'JH_FIXED: the fixed job Lisbon -> ISL did not go harbour by harbour: % / % (job %)', v_r, v_texts, to_jsonb(v_j);
  end if;
  raise notice 'PASS: JH_FIXED — % (the longest leg % of % nm); she departs with % aboard', v_texts, round(v_max), round(v_reach), v_g;

  -- JH_HOME: back at ISL, empty; a bring-home job that buys at Lisbon's nearest lane harbour (home is Lisbon): her first sail is the chain
  update public.orders set status = 'cancelled' where fleet_id = v_fa and status in ('pending', 'active');
  update public.voyages set status = 'ARRIVED' where fleet_id = v_fa and status = 'SAILING';
  update public.fleets set status = 'DOCKED', port_id = v_isl where id = v_fa;
  perform public.fleet_unload(v_fa, v_g, public.fleet_cargo_qty(v_fa, v_g));
  select k2.to_port, k2.code into v_x, v_xc from public.npc_known_legs(v_lis) k2 join public.ports p on p.id = k2.to_port
   where p.kind = 'HARBOUR' and public.fleet_job_course(v_fa, k2.to_port, v_lis) is not null order by k2.nm, k2.code limit 1;
  v_r := cmd.set_fleet_job(v_fa, 'fixed', jsonb_build_object('good', v_g, 'buy', v_xc, 'end', 'store', 'times', 1));
  call public.tick_fleet_jobs(false);
  select * into v_j from public.fleet_jobs j where j.fleet_id = v_fa;
  select string_agg(o.raw_text, ' / ' order by o.seq), count(*),
         max((select sum((s->>'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course(o.args->'path')) s))
    into v_texts, v_n, v_max from public.orders o where o.fleet_id = v_fa and o.plan_id = v_j.last_plan;
  if (v_r->>'ok')::boolean is not true or v_r #>> '{params,sell}' <> 'LIS' or v_j.paused_reason is not null or v_n < 2
     or v_texts not like 'SAIL % / SAIL ' || v_xc or v_max is null or v_max > v_reach or (v_j.params->>'left')::int <> 1
     or (select f.status from public.fleets f where f.id = v_fa) <> 'SAILING' then
    raise exception 'JH_HOME: the bring-home job''s first sail to % did not go harbour by harbour: % / % (job %)', v_xc, v_r, v_texts, to_jsonb(v_j);
  end if;
  raise notice 'PASS: JH_HOME — bring % home from %: her first sail from ISL is % (the longest leg % nm)', v_g, v_xc, v_texts, round(v_max);

  -- JH_BEST: a best sale's lines from ISL to Lisbon, and the plan door (cmd.issue_lines, as the tick sends them) takes them whole
  delete from public.fleet_jobs where fleet_id = v_fa;
  update public.orders set status = 'cancelled' where fleet_id = v_fa and status in ('pending', 'active');
  update public.voyages set status = 'ARRIVED' where fleet_id = v_fa and status = 'SAILING';
  update public.fleets set status = 'DOCKED', port_id = v_isl where id = v_fa;
  v_p := public.sale_lines(v_fa, v_isl, jsonb_build_object('good', v_g, 'port', 'LIS', 'units', 1, 'basis', 'on_board'), '[]'::jsonb);
  select max((select sum((s->>'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course(l->'path')) s)) into v_max
    from jsonb_array_elements(v_p->'lines') l where l ? 'path';
  v_r := cmd.issue_lines(v_fa, v_p->'lines', (select f.version from public.fleets f where f.id = v_fa));
  if jsonb_array_length(coalesce(v_p->'lines', '[]'::jsonb)) < 3 or v_p #>> '{lines,-1,text}' <> format('SELL %s ALL', v_g)
     or v_p #>> '{lines,-2,text}' <> 'SAIL LIS' or v_max is null or v_max > v_reach or (v_r->>'ok')::boolean is not true
     or (select f.status from public.fleets f where f.id = v_fa) <> 'SAILING' then
    raise exception 'JH_BEST: a best sale''s lines were not harbour by harbour, or the door refused them: % / %', left(v_p::text, 300), left(v_r::text, 300);
  end if;
  raise notice 'PASS: JH_BEST — % lines, the last two SAIL LIS / SELL % ALL, the longest leg % nm; the plan door took them and she departs',
    jsonb_array_length(v_p->'lines'), v_g, round(v_max);

  -- JH_RETRY: a job stopped as prod's is: inside 10 minutes left alone; after them re-planned, started, the stop lifted (both codes)
  update public.orders set status = 'cancelled' where fleet_id = v_fa and status in ('pending', 'active');
  update public.voyages set status = 'ARRIVED' where fleet_id = v_fa and status = 'SAILING';
  update public.fleets set status = 'DOCKED', port_id = v_isl where id = v_fa;
  insert into public.fleet_jobs (fleet_id, player_id, kind, params, since, seen_at, paused_reason, last)
  values (v_fa, v_a, 'land', '{"to": "CAD"}'::jsonb, now() - interval '1 hour', now() - interval '1 hour', 'E_LEG_TOO_FAR',
          jsonb_build_object('at', now() - interval '9 minutes', 'ok', false, 'code', 'E_LEG_TOO_FAR', 'sentence', 'Line 1 (SAIL LIS): that leg is 7052 nm'));
  v_orders := (select count(*) from public.orders o where o.fleet_id = v_fa);
  call public.tick_fleet_jobs(false);
  if (select j.paused_reason from public.fleet_jobs j where j.fleet_id = v_fa) is distinct from 'E_LEG_TOO_FAR'
     or (select count(*) from public.orders o where o.fleet_id = v_fa) <> v_orders
     or (select jsonb_array_length(r.receipt->'steps') from public.fleet_job_runs r order by r.at desc limit 1) <> 0 then
    raise exception 'JH_RETRY: a job stopped 9 minutes ago was asked again';
  end if;
  update public.fleet_jobs set last = last || jsonb_build_object('at', now() - interval '10 minutes') where fleet_id = v_fa;
  call public.tick_fleet_jobs(false);
  select * into v_j from public.fleet_jobs j where j.fleet_id = v_fa;
  if v_j.paused_reason is not null or v_j.runs <> 1 or (v_j.last->>'ok')::boolean is not true
     or (select f.status from public.fleets f where f.id = v_fa) <> 'SAILING' or world.away_report() #>> '{jobs,0,state}' <> 'working' then
    raise exception 'JH_RETRY: a job stopped 10 minutes ago was not re-planned and started: %', to_jsonb(v_j);
  end if;
  update public.orders set status = 'cancelled' where fleet_id = v_fa and status in ('pending', 'active');
  update public.voyages set status = 'ARRIVED' where fleet_id = v_fa and status = 'SAILING';
  update public.fleets set status = 'DOCKED', port_id = v_isl where id = v_fa;
  update public.fleet_jobs set paused_reason = 'E_ENDURANCE', last_plan = null,
         last = jsonb_build_object('at', now() - interval '10 minutes', 'ok', false, 'code', 'E_ENDURANCE', 'sentence', 'old') where fleet_id = v_fa;
  call public.tick_fleet_jobs(false);
  select * into v_j from public.fleet_jobs j where j.fleet_id = v_fa;
  if v_j.paused_reason is not null or v_j.runs <> 2 or (select f.status from public.fleets f where f.id = v_fa) <> 'SAILING' then
    raise exception 'JH_RETRY: a job stopped E_ENDURANCE 10 minutes ago was not re-planned and started: %', to_jsonb(v_j);
  end if;
  raise notice 'PASS: JH_RETRY — stopped 9 minutes ago: not asked; 10 minutes ago: re-planned, started, the stop lifted (E_LEG_TOO_FAR and E_ENDURANCE)';

  -- JH_NOLOOP: no chain (her reach shortened to 100 nm for this proof alone): the retry stays stopped, stamped; the next run asks nothing
  update public.orders set status = 'cancelled' where fleet_id = v_fa and status in ('pending', 'active');
  update public.voyages set status = 'ARRIVED' where fleet_id = v_fa and status = 'SAILING';
  update public.fleets set status = 'DOCKED', port_id = v_isl where id = v_fa;
  v_base := (select c.value from public.world_config c where c.key = 'nav_leg_nm_base');
  update public.world_config set value = to_jsonb(100) where key = 'nav_leg_nm_base';
  update public.fleet_jobs set paused_reason = 'E_LEG_TOO_FAR', last_plan = null,
         last = jsonb_build_object('at', now() - interval '10 minutes', 'ok', false, 'code', 'E_LEG_TOO_FAR', 'sentence', 'old') where fleet_id = v_fa;
  v_orders := (select count(*) from public.orders o where o.fleet_id = v_fa);
  call public.tick_fleet_jobs(false);
  select * into v_j from public.fleet_jobs j where j.fleet_id = v_fa;
  if v_j.paused_reason is distinct from 'E_LEG_TOO_FAR' or (v_j.last->>'at')::timestamptz is distinct from now()
     or v_j.last->>'sentence' not like 'she cannot sail from Island of Mozambique to Lisbon harbour by harbour: that leg is % nm and your navigation carries you 100 nm%'
     or (select count(*) from public.orders o where o.fleet_id = v_fa) <> v_orders or world.away_report() #>> '{jobs,0,state}' <> 'stopped' then
    raise exception 'JH_NOLOOP: with no chain the job did not stay stopped with its plain sentence: %', to_jsonb(v_j);
  end if;
  v_texts := v_j.last->>'sentence';
  call public.tick_fleet_jobs(false);
  if (select jsonb_array_length(r.receipt->'steps') from public.fleet_job_runs r order by r.at desc limit 1) <> 0 then
    raise exception 'JH_NOLOOP: the job was asked again by the very next run';
  end if;
  update public.fleet_jobs set paused_reason = 'E_NO_COURSE', last = last || jsonb_build_object('at', now() - interval '1 day') where fleet_id = v_fa;
  call public.tick_fleet_jobs(false);
  if (select jsonb_array_length(r.receipt->'steps') from public.fleet_job_runs r order by r.at desc limit 1) <> 0
     or (select j.paused_reason from public.fleet_jobs j where j.fleet_id = v_fa) <> 'E_NO_COURSE' then
    raise exception 'JH_NOLOOP: a job stopped on another code was asked again';
  end if;
  raise notice 'PASS: JH_NOLOOP — "%"; stamped now, the next run asked nothing; a stop on E_NO_COURSE is never retried', v_texts;

  -- JH_REFUSED: still no chain: the door refuses each kind that names a harbour; her job row is not touched
  v_r := cmd.set_fleet_job(v_fa, 'land', '{"to": "CAD"}'::jsonb);
  v_p := cmd.set_fleet_job(v_fa, 'fixed', jsonb_build_object('good', v_g, 'buy', 'LIS', 'sell', 'ISL'));
  if v_r->>'error_code' is distinct from 'E_LEG_TOO_FAR' or v_r->>'error_message' not ilike '%cannot sail from % harbour by harbour%'
     or v_p->>'error_code' is distinct from 'E_LEG_TOO_FAR' or v_p->>'error_message' not ilike '%cannot sail from Lisbon to Island of Mozambique harbour by harbour%' then
    raise exception 'JH_REFUSED: the door did not refuse a land and a fixed job with no chain: % / %', v_r, v_p;
  end if;
  v_p := cmd.set_fleet_job(v_fa, 'fixed', jsonb_build_object('good', v_g, 'buy', 'ISL', 'end', 'store'));
  if v_p->>'error_code' is distinct from 'E_LEG_TOO_FAR'
     or (select j.kind || ':' || j.paused_reason from public.fleet_jobs j where j.fleet_id = v_fa) is distinct from 'land:E_NO_COURSE' then
    raise exception 'JH_REFUSED: the door did not refuse a bring-home job with no chain, or wrote a job: %', v_p;
  end if;
  update public.world_config set value = v_base where key = 'nav_leg_nm_base';
  raise notice 'PASS: JH_REFUSED — land: "%"; fixed and bring home refused the same way (E_LEG_TOO_FAR)', v_r->>'error_message';
end $p$;
