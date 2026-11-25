-- PROOF 243 - A LADEN RUN IS JUDGED  (migration 0516; the review of 0504's laden run, 2026-11-25)
-- @pass LJ_PURSE   run_guard lit, a full hold, no coin, one sail to the sale: she goes and sells; with her stores' price short by a coin she waits `purse`
-- @pass LJ_ONE     jobs_wait lit, one unit of room that alone would lose: the load aboard is judged with it and she goes
-- @pass LJ_TOKEN   one unit aboard, no coin: she waits `low`, jobs_wait lit and dark; a full load that pays goes, with no coin
-- @pass LJ_GLUT    a full load into a glutted quay: she waits `low`, jobs_wait lit and dark
-- @pass LJ_NOBUY   run_guard lit, a paying half load, a purse that bears no BUY: the BUY is left out and she goes
-- @pass LJ_HOME    bring home: the shed holds exactly her load: no BUY, she brings it; the shed full and her load aboard: she waits, not stopped; nothing aboard: E_SHED_FULL as 0492
-- @pass LJ_FITS    the shed has room for a part of her load: she waits (a STORE is whole or refused), not stopped
-- @pass LJ_HOLD    the stores in the hold: the run buys beside its stores, loses her flagship, is mended, and sails with that load
-- @pass LJ_HAUL    a haul whose good changed: the old load is stored first; with the new good in the shed and room aboard, as before
-- @pass LJ_SET     passive settings lit: the same laden run goes on; a stop_profit over what it leaves stops it
-- @pass LJ_EMPTY   nothing aboard: the quote is 0498's to the letter (one unit, all, none), and the plan buys as before
do $p$
declare
  c_a   constant uuid := '00000000-0516-4000-8000-000000000243';
  v_a   uuid;
  v_f   uuid;
  v_lis uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_set uuid := (select p.id from public.ports p where p.code = 'SET' and p.kind = 'HARBOUR');
  v_g   uuid;
  v_c   text;
  v_g2  uuid;
  v_c2  text;
  v_h   numeric;
  v_u   numeric;
  v_p   jsonb;
  v_q   jsonb;
  v_j   record;
  i     int;
begin
  v_a := public.new_house(c_a, 'Casa Julgada 243', 'PRT');
  select f.id into v_f from public.fleets f where f.player_id = v_a;
  update public.players p set ducats = 5000000 where p.id = v_a;
  update public.world_config set value = 'true'::jsonb where key in ('fleet_jobs_enabled', 'sea_courses_enabled', 'land_enabled', 'ship_stores_separate', 'assign_home_enabled');
  update public.world_config set value = 'false'::jsonb where key in ('jobs_wait_enabled', 'run_guard_enabled', 'passive_settings_enabled', 'sea_choices_enabled', 'sea_conditions_bite', 'buy_tax_enabled', 'bargain_total_enabled');
  update public.fleet_jobs set next_at = now() + interval '1 day' where player_id <> v_a;
  update public.ships s set crew = (select b.crew_max from public.ship_base(s.id) b), food_t = 0.5, water_t = 0.5 where s.fleet_id = v_f;
  perform cmd.assume_identity(c_a);
  select g.id, g.code into v_g, v_c from public.goods g
   where public.port_offers(v_lis, g.id) and g.bulk <= 1 and exists (select 1 from public.port_goods pg where pg.good_id = g.id and pg.port_id = v_set)
     and not public.culture_refuses((select h.culture from public.ports h where h.id = v_set), g.culture_mask)
   order by g.code limit 1;
  update public.goods g set bulk = 1 where g.id = v_g;
  -- buying and selling prices that a single unit cannot pay a trip with; a full load of cheap cargo can
  update public.port_goods pg set stock_target = 1000000, stock = 1000000, affinity = 1, demand = 1, drift = 0, season_mod = 0, glut = 0, glut_at = now(), haul = 1, want_period = null
   where pg.good_id = v_g and pg.port_id in (v_lis, v_set);
  if (cmd.set_fleet_job(v_f, 'fixed', jsonb_build_object('good', v_c, 'buy', 'LIS', 'sell', 'SET'))->>'ok')::boolean is not true then
    raise exception 'LJ: the door refused the job';
  end if;
  v_h := public.fleet_free_hold(v_f);

  -- LJ_EMPTY
  v_q := public.fleet_run_quote(v_a, v_f, v_lis, v_c, 'SET', array['SET', 'LIS']);
  if (v_q->>'units')::numeric <> v_h or (v_q->>'load')::numeric <> v_h or (v_q->>'net')::numeric >= 0
     or (v_q->>'cost')::numeric <> round((public.fleet_buy_capacity(v_f, v_g)->>'est_total')::numeric)
     or (v_q->>'net')::numeric <> round((v_q->>'gross')::numeric - (v_q->>'cost')::numeric - (v_q->>'tax')::numeric - (v_q->>'trip')::numeric)
     and abs((v_q->>'net')::numeric - ((v_q->>'gross')::numeric - (v_q->>'cost')::numeric - (v_q->>'tax')::numeric - (v_q->>'trip')::numeric)) > 2 then
    raise exception 'LJ_EMPTY: %', v_q;
  end if;
  v_p := public.fleet_job_plan(v_f);
  if v_p #>> '{lines,0,text}' is distinct from format('BUY %s ALL', v_c) then raise exception 'LJ_EMPTY: the plan %', left(v_p::text, 200); end if;
  raise notice 'PASS: LJ_EMPTY - % units, net % (an empty run that loses: dark it buys as before)', v_q->>'units', v_q->>'net';

  -- a full hold she paid 1 a unit for
  update public.ships s set cargo = jsonb_build_object(v_c, v_h), cargo_basis = jsonb_build_object(v_c, 1) where s.fleet_id = v_f and s.is_flagship;

  -- LJ_PURSE
  update public.world_config set value = 'true'::jsonb where key = 'run_guard_enabled';
  update public.players p set ducats = 100 where p.id = v_a;
  v_p := public.fleet_job_plan(v_f);
  if not (v_p ? 'lines') or v_p->'lines' @? '$[*] ? (@.text like_regex "^BUY")' then raise exception 'LJ_PURSE: a laden run with no coin does not go: %', left(v_p::text, 400); end if;
  v_q := public.run_need(v_a, v_f, v_lis, v_p->'lines');
  if not (v_q ? 'aboard') or (v_q->>'need')::numeric <= 100 then raise exception 'LJ_PURSE: the scene''s reserve is not over her purse: %', v_q; end if;
  if (v_q->>'stores')::numeric >= 1 then
    update public.players p set ducats = ceil((v_q->>'stores')::numeric) - 1 where p.id = v_a;
    v_p := public.fleet_job_plan(v_f);
    if v_p->>'wait' is distinct from 'purse' then raise exception 'LJ_PURSE: her stores not paid for and she goes: %', left(v_p::text, 300); end if;
  end if;
  raise notice 'PASS: LJ_PURSE - purse 100, need %, stores %: she sells', v_q->>'need', v_q->>'stores';
  update public.world_config set value = 'false'::jsonb where key = 'run_guard_enabled';
  update public.players p set ducats = 5000000 where p.id = v_a;

  -- LJ_ONE
  update public.world_config set value = 'true'::jsonb where key = 'jobs_wait_enabled';
  update public.ships s set cargo = jsonb_build_object(v_c, v_h - 1) where s.fleet_id = v_f and s.is_flagship;
  if (public.fleet_buy_capacity(v_f, v_g)->>'max_qty')::numeric <> 1 then raise exception 'LJ_ONE: the scene has not one unit of room'; end if;
  v_p := public.fleet_job_plan(v_f);
  if not (v_p ? 'lines') then raise exception 'LJ_ONE: one unit of room and % aboard: %', v_h - 1, v_p; end if;
  raise notice 'PASS: LJ_ONE - %', v_p #>> '{lines,0,text}';

  -- LJ_TOKEN
  update public.players p set ducats = 0 where p.id = v_a;
  update public.ships s set cargo = jsonb_build_object(v_c, 1), cargo_basis = jsonb_build_object(v_c, (select q.ask from world.price(v_lis, v_g) q)) where s.fleet_id = v_f and s.is_flagship;
  for i in 1 .. 2 loop
    update public.world_config set value = to_jsonb(i = 1) where key = 'jobs_wait_enabled';
    v_p := public.fleet_job_plan(v_f);
    if v_p->>'wait' is distinct from 'low' then raise exception 'LJ_TOKEN: one unit aboard, jobs_wait %: %', i = 1, left(v_p::text, 300); end if;
  end loop;
  update public.ships s set cargo = jsonb_build_object(v_c, v_h), cargo_basis = jsonb_build_object(v_c, 1) where s.fleet_id = v_f and s.is_flagship;
  v_p := public.fleet_job_plan(v_f);
  if not (v_p ? 'lines') then raise exception 'LJ_TOKEN: a full load that pays does not go: %', left(v_p::text, 300); end if;
  raise notice 'PASS: LJ_TOKEN - one unit waits, % go', v_h;

  -- LJ_GLUT
  update public.ships s set cargo_basis = jsonb_build_object(v_c, (select q.ask * 2 from world.price(v_lis, v_g) q)) where s.fleet_id = v_f and s.is_flagship;
  for i in 1 .. 2 loop
    update public.world_config set value = to_jsonb(i = 1) where key = 'jobs_wait_enabled';
    v_p := public.fleet_job_plan(v_f);
    if v_p->>'wait' is distinct from 'low' then raise exception 'LJ_GLUT: a load that would be sold at half its cost, jobs_wait %: %', i = 1, left(v_p::text, 300); end if;
  end loop;
  perform public.fleet_job_note(v_f, v_p);
  select * into v_j from public.fleet_jobs j where j.fleet_id = v_f;
  if v_j.paused_reason is not null or v_j.last->>'wait' <> 'low' or v_j.next_at <= now() then raise exception 'LJ_GLUT: the wait is not 0498''s: %', to_jsonb(v_j); end if;
  raise notice 'PASS: LJ_GLUT - waits "%", not stopped', v_j.last->>'sentence';
  update public.fleet_jobs set next_at = null where fleet_id = v_f;

  -- LJ_NOBUY
  update public.world_config set value = 'true'::jsonb where key = 'run_guard_enabled';
  update public.ships s set cargo = jsonb_build_object(v_c, floor(v_h / 2)), cargo_basis = jsonb_build_object(v_c, 1) where s.fleet_id = v_f and s.is_flagship;
  update public.players p set ducats = 300 where p.id = v_a;
  if (public.fleet_buy_capacity(v_f, v_g)->>'max_qty')::numeric < 1 then
    update public.port_goods pg set affinity = 0.05 where pg.good_id = v_g and pg.port_id = v_lis;
  end if;
  v_p := public.fleet_job_plan(v_f);
  if not (v_p ? 'lines') or v_p->'lines' @? '$[*] ? (@.text like_regex "^BUY")' then raise exception 'LJ_NOBUY: %', left(v_p::text, 400); end if;
  raise notice 'PASS: LJ_NOBUY - half a load, purse 300: %', (select string_agg(l->>'text', ' / ') from jsonb_array_elements(v_p->'lines') l);
  update public.port_goods pg set affinity = 1 where pg.good_id = v_g and pg.port_id = v_lis;
  update public.world_config set value = 'false'::jsonb where key in ('run_guard_enabled', 'jobs_wait_enabled');
  update public.players p set ducats = 5000000 where p.id = v_a;

  -- LJ_SET
  update public.world_config set value = 'true'::jsonb where key = 'passive_settings_enabled';
  update public.ships s set cargo = jsonb_build_object(v_c, v_h) where s.fleet_id = v_f and s.is_flagship;
  update public.fleet_jobs set params = params || '{"crew": 1}'::jsonb where fleet_id = v_f;
  v_p := public.fleet_job_plan(v_f);
  if not (v_p ? 'lines') or v_p->'lines' @? '$[*] ? (@.text like_regex "^BUY")' then raise exception 'LJ_SET: %', left(v_p::text, 300); end if;
  update public.fleet_jobs set params = params || '{"stop_profit": 1000000000}'::jsonb where fleet_id = v_f;
  v_p := public.fleet_job_plan(v_f);
  if v_p->>'pause' is distinct from 'E_STOP_PROFIT' then raise exception 'LJ_SET: %', left(v_p::text, 300); end if;
  raise notice 'PASS: LJ_SET - goes on; %', v_p->>'sentence';
  update public.fleet_jobs set params = params - 'crew' - 'stop_profit' where fleet_id = v_f;
  update public.world_config set value = 'false'::jsonb where key = 'passive_settings_enabled';

  -- LJ_HOME: `sell` is the shed (Setubal), v_h aboard
  update public.fleet_jobs set params = jsonb_build_object('good', v_c, 'buy', 'LIS', 'sell', 'SET', 'stops', '[]'::jsonb, 'end', 'store') where fleet_id = v_f;
  v_u := public.storage_cap(v_set);   -- the shed's tuns; the good is one tun a unit
  insert into public.player_storage (player_id, port_id, good_id, qty) values (v_a, v_set, v_g, greatest(0, v_u - v_h));
  update public.ships s set cargo = jsonb_build_object(v_c, least(v_h, v_u)) where s.fleet_id = v_f and s.is_flagship;
  v_p := public.fleet_job_plan(v_f);
  if not (v_p ? 'lines') or v_p->'lines' @? '$[*] ? (@.text like_regex "^BUY")' or v_p #>> '{lines,-1,text}' <> format('STORE %s ALL', v_c) then
    raise exception 'LJ_HOME: the shed holds exactly her load (% of %): %', least(v_h, v_u), v_u, left(v_p::text, 300);
  end if;
  update public.player_storage ps set qty = v_u where ps.player_id = v_a and ps.port_id = v_set and ps.good_id = v_g;
  v_p := public.fleet_job_plan(v_f);
  if v_p->>'wait' is distinct from 'low' or v_p->>'sentence' is distinct from 'the warehouse at SET is full' then raise exception 'LJ_HOME: the shed full: %', left(v_p::text, 300); end if;
  update public.ships s set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where s.fleet_id = v_f;
  v_p := public.fleet_job_plan(v_f);
  if v_p->>'pause' is distinct from 'E_SHED_FULL' then raise exception 'LJ_HOME: nothing aboard: %', left(v_p::text, 300); end if;
  raise notice 'PASS: LJ_HOME - exactly her load goes home; full: waits; empty and full: E_SHED_FULL';

  -- LJ_FITS
  update public.player_storage ps set qty = v_u - 3 where ps.player_id = v_a and ps.port_id = v_set and ps.good_id = v_g;
  update public.ships s set cargo = jsonb_build_object(v_c, 10), cargo_basis = jsonb_build_object(v_c, 1) where s.fleet_id = v_f and s.is_flagship;
  v_p := public.fleet_job_plan(v_f);
  if v_p->>'wait' is distinct from 'low' then raise exception 'LJ_FITS: room for a part: %', left(v_p::text, 300); end if;
  raise notice 'PASS: LJ_FITS - room for 3 of 10: "%"', v_p->>'sentence';
  delete from public.player_storage ps where ps.player_id = v_a;

  -- LJ_HAUL
  perform public.land_party(v_a);
  update public.land_parties lp set port_id = v_lis where lp.player_id = v_a and lp.ord = 1;
  select g.id, g.code into v_g2, v_c2 from public.land_actions a join public.goods g on g.id = a.good_id where g.id <> v_g order by g.code limit 1;
  update public.fleet_jobs set kind = 'land', params = jsonb_build_object('to', 'SET', 'good', v_c), last_plan = null where fleet_id = v_f;
  update public.ships s set cargo = jsonb_build_object(v_c2, 5), cargo_basis = '{}'::jsonb where s.fleet_id = v_f and s.is_flagship;
  v_p := public.fleet_job_plan(v_f);
  if not (v_p ? 'lines') or v_p #>> '{lines,-1,text}' <> format('STORE %s ALL', v_c2) or v_p->'lines' @? '$[*] ? (@.text like_regex "^TAKE")' then
    raise exception 'LJ_HAUL: the old load waits: %', left(v_p::text, 300);
  end if;
  insert into public.player_storage (player_id, port_id, good_id, qty) values (v_a, v_lis, v_g, 5);
  v_p := public.fleet_job_plan(v_f);
  if not (v_p ? 'lines') or v_p #>> '{lines,-1,text}' <> format('STORE %s ALL', v_c) or not (v_p->'lines' @? '$[*] ? (@.text like_regex "^TAKE")') then
    raise exception 'LJ_HAUL: the new good is there and there is room: %', left(v_p::text, 300);
  end if;
  raise notice 'PASS: LJ_HAUL - % first, then % as before', v_c2, v_c;
  delete from public.player_storage ps where ps.player_id = v_a;

  -- LJ_HOLD: the pool; a run that pays, bought beside its stores
  update public.world_config set value = 'false'::jsonb where key = 'ship_stores_separate';
  update public.ships s set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb, food_t = 0, water_t = 0, hold_grace_until = null where s.fleet_id = v_f;
  update public.port_goods pg set stock = 1000000000, affinity = 0.25 where pg.good_id = v_g and pg.port_id = v_lis;
  update public.port_goods pg set stock = 0, affinity = 3 where pg.good_id = v_g and pg.port_id = v_set;
  update public.fleet_jobs set kind = 'fixed', params = jsonb_build_object('good', v_c, 'buy', 'LIS', 'sell', 'SET', 'stops', '[]'::jsonb), last_plan = null, next_at = null, last = null, paused_reason = null where fleet_id = v_f;
  delete from public.orders o where o.fleet_id = v_f;
  create function pg_temp.wreck_243() returns trigger language plpgsql as $f$
  begin
    update public.ships set durability = 0 where fleet_id = new.fleet_id and is_flagship;
    return null;
  end $f$;
  create trigger wreck_243 after insert on public.orders for each row when (new.verb = 'SAIL') execute function pg_temp.wreck_243();
  call public.tick_fleet_jobs(false);
  drop trigger wreck_243 on public.orders;
  if public.fleet_cargo_qty(v_f, v_c) < 1 or not exists (select 1 from public.orders o where o.fleet_id = v_f and o.error_code = 'E_FLAGSHIP_DISABLED') then
    raise exception 'LJ_HOLD: the scene: %', (select jsonb_agg(jsonb_build_array(o.raw_text, o.status, o.error_code)) from public.orders o where o.fleet_id = v_f);
  end if;
  v_u := public.fleet_cargo_qty(v_f, v_c);
  call public.tick_fleet_jobs(false);
  update public.ships s set durability = (select b.durability from public.ship_base(s.id) b) where s.fleet_id = v_f;
  call public.tick_fleet_jobs(false);
  if (select f.status from public.fleets f where f.id = v_f) <> 'SAILING' then
    raise exception 'LJ_HOLD: mended with her load and her stores in one hold she does not sail: % / %', (select to_jsonb(j) from public.fleet_jobs j where j.fleet_id = v_f),
      (select jsonb_agg(jsonb_build_array(o.raw_text, o.status, o.error_code) order by o.seq) from public.orders o where o.fleet_id = v_f);
  end if;
  raise notice 'PASS: LJ_HOLD - % aboard beside her stores, she sails', v_u;
end
$p$;
