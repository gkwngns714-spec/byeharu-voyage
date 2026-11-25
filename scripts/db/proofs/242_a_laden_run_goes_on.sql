-- PROOF 242 - A LADEN RUN GOES ON  (migration 0504; docs/dev-log/2026-11-25-assign-fast.md)
-- @pass LD_FULL    a fixed run bought a full hold and lost her flagship before the sail; mended, the next tick sails her with that load, nothing bought, no refusal
-- @pass LD_QUOTE   the same with jobs_wait_enabled and run_guard_enabled lit: not "nothing to buy" for ever
-- @pass LD_PARTLY  room, coin and quay left: the plan buys as before
-- @pass LD_PURSE   an empty purse and a part load: she goes on with what she has
-- @pass LD_EMPTY   nothing aboard and nothing to be had: the BUY stands in the plan as before (its refusal is hers to read)
-- @pass LD_HAUL    a land haul cut short after its TAKE (the shed empty, or the hold full): she sails and stores
do $p$
declare
  c_a   constant uuid := '00000000-0504-4000-8000-000000000242';
  v_a   uuid;
  v_f   uuid;
  v_lis uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_g   uuid;
  v_c   text;
  v_q   numeric;
  v_p   jsonb;
  v_j   record;
begin
  v_a := public.new_house(c_a, 'Casa Carregada 242', 'PRT');
  select f.id into v_f from public.fleets f where f.player_id = v_a;
  update public.players p set ducats = 5000000 where p.id = v_a;
  update public.world_config set value = 'true'::jsonb where key in ('fleet_jobs_enabled', 'sea_courses_enabled', 'land_enabled', 'ship_stores_separate');
  update public.world_config set value = 'false'::jsonb where key in ('jobs_wait_enabled', 'run_guard_enabled');
  update public.fleet_jobs set next_at = now() + interval '1 day' where player_id <> v_a;
  update public.ships s set crew = (select b.crew_max from public.ship_base(s.id) b), food_t = 3, water_t = 3 where s.fleet_id = v_f;
  perform cmd.assume_identity(c_a);
  select g.id, g.code into v_g, v_c from public.goods g
   where public.port_offers(v_lis, g.id) and g.bulk <= 1
     and exists (select 1 from public.port_goods pg join public.ports h on h.id = pg.port_id and h.code = 'SET' where pg.good_id = g.id)
     and not public.culture_refuses((select h.culture from public.ports h where h.code = 'SET'), g.culture_mask)
   order by g.code limit 1;
  update public.goods g set bulk = 1 where g.id = v_g;   -- a full hold is full to the last tun (a hull's hold is rolled in whole tuns)
  update public.port_goods pg set stock_target = 1000000, stock = 1000000000, affinity = 0.25, demand = 1, drift = 0, season_mod = 0, glut = 0.5, glut_at = now(), haul = 1
   where pg.port_id = v_lis and pg.good_id = v_g;
  update public.port_goods pg set stock_target = 1000000 where pg.good_id = v_g and pg.port_id = (select h.id from public.ports h where h.code = 'SET');
  -- the first sail order finds her flagship a wreck, as it is written
  create function pg_temp.wreck_242() returns trigger language plpgsql as $f$
  begin
    update public.ships set durability = 0 where fleet_id = new.fleet_id and is_flagship;
    return null;
  end $f$;
  create trigger wreck_242 after insert on public.orders for each row when (new.verb = 'SAIL') execute function pg_temp.wreck_242();
  if (cmd.set_fleet_job(v_f, 'fixed', jsonb_build_object('good', v_c, 'buy', 'LIS', 'sell', 'SET'))->>'ok')::boolean is not true then
    raise exception 'LD_FULL: the door refused the job';
  end if;

  -- LD_FULL
  call public.tick_fleet_jobs(false);
  v_q := public.fleet_cargo_qty(v_f, v_c);
  if v_q < 1 or not exists (select 1 from public.orders o where o.fleet_id = v_f and o.verb = 'SAIL' and o.error_code = 'E_FLAGSHIP_DISABLED')
     or (public.fleet_buy_capacity(v_f, v_g)->>'max_qty')::numeric >= 1 then
    raise exception 'LD_FULL: the scene is not a full hold and a refused sail (% aboard, %)', v_q, public.fleet_buy_capacity(v_f, v_g);
  end if;
  call public.tick_fleet_jobs(false);   -- she waits for her repair (0500)
  drop trigger wreck_242 on public.orders;
  update public.ships s set durability = (select b.durability from public.ship_base(s.id) b) where s.fleet_id = v_f;
  begin
    call public.tick_fleet_jobs(false);
    select * into v_j from public.fleet_jobs j where j.fleet_id = v_f;
    if (select f.status from public.fleets f where f.id = v_f) <> 'SAILING' or v_j.paused_reason is not null or public.fleet_cargo_qty(v_f, v_c) <> v_q
       or exists (select 1 from public.orders o where o.fleet_id = v_f and o.error_code = 'E_HOLD_FULL') then
      raise exception 'LD_FULL: mended with a full hold she does not go on: % / %', to_jsonb(v_j),
        (select jsonb_agg(jsonb_build_array(o.raw_text, o.status, o.error_code) order by o.seq) from public.orders o where o.fleet_id = v_f);
    end if;
    raise notice 'PASS: LD_FULL - % % aboard, she sails and buys nothing', v_q, v_c;
    raise exception using errcode = 'ZP242', message = 'undo';
  exception when sqlstate 'ZP242' then null;
  end;

  -- LD_QUOTE
  update public.world_config set value = 'true'::jsonb where key in ('jobs_wait_enabled', 'run_guard_enabled');
  v_p := public.fleet_job_plan(v_f);
  if not (v_p ? 'lines') or v_p->'lines' @? '$[*] ? (@.text like_regex "^BUY")' or v_p #>> '{lines,-1,text}' <> format('SELL %s ALL', v_c) then
    raise exception 'LD_QUOTE: %', left(v_p::text, 300);
  end if;
  raise notice 'PASS: LD_QUOTE - %', (select string_agg(l->>'text', ' / ') from jsonb_array_elements(v_p->'lines') l);
  update public.world_config set value = 'false'::jsonb where key in ('jobs_wait_enabled', 'run_guard_enabled');

  -- LD_PARTLY, LD_PURSE, LD_EMPTY
  update public.ships s set cargo = jsonb_build_object(v_c, 5) where s.fleet_id = v_f and s.is_flagship;
  v_p := public.fleet_job_plan(v_f);
  if (v_p->'lines' @? '$[*] ? (@.text like_regex "^BUY")') is not true then
    raise exception 'LD_PARTLY: with room, coin and quay left she does not buy: %', left(v_p::text, 300);
  end if;
  raise notice 'PASS: LD_PARTLY - %', v_p #>> '{lines,0,text}';
  update public.players p set ducats = 0 where p.id = v_a;
  v_p := public.fleet_job_plan(v_f);
  if not (v_p ? 'lines') or v_p->'lines' @? '$[*] ? (@.text like_regex "^BUY")' then
    raise exception 'LD_PURSE: %', left(v_p::text, 300);
  end if;
  raise notice 'PASS: LD_PURSE - 5 aboard, no coin: %', v_p #>> '{lines,0,text}';
  update public.ships s set cargo = '{}'::jsonb where s.fleet_id = v_f;
  v_p := public.fleet_job_plan(v_f);
  if (v_p->'lines' @? '$[*] ? (@.text like_regex "^BUY")') is not true then
    raise exception 'LD_EMPTY: %', left(v_p::text, 300);
  end if;
  raise notice 'PASS: LD_EMPTY - %', v_p #>> '{lines,0,text}';

  -- LD_HAUL
  update public.players p set ducats = 5000000 where p.id = v_a;
  perform public.land_party(v_a);
  update public.land_parties lp set port_id = v_lis where lp.player_id = v_a and lp.ord = 1;
  update public.fleet_jobs set kind = 'land', params = jsonb_build_object('to', 'SET', 'good', v_c), next_at = null, paused_reason = null, last_plan = null where fleet_id = v_f;
  if public.fleet_job_plan(v_f)->>'wait' is distinct from 'nothing' then
    raise exception 'LD_HAUL: nothing in the shed, nothing aboard, and she does not wait: %', public.fleet_job_plan(v_f);
  end if;
  update public.ships s set cargo = jsonb_build_object(v_c, 5) where s.fleet_id = v_f and s.is_flagship;
  v_p := public.fleet_job_plan(v_f);
  if not (v_p ? 'lines') or v_p->'lines' @? '$[*] ? (@.text like_regex "^TAKE")' or v_p #>> '{lines,-1,text}' <> format('STORE %s ALL', v_c) then
    raise exception 'LD_HAUL: the shed empty: %', left(v_p::text, 300);
  end if;
  insert into public.player_storage (player_id, port_id, good_id, qty) values (v_a, v_lis, v_g, 50);
  v_p := public.fleet_job_plan(v_f);
  if (v_p->'lines' @? '$[*] ? (@.text like_regex "^TAKE")') is not true then
    raise exception 'LD_HAUL: goods in the shed and room aboard, and she takes none: %', left(v_p::text, 300);
  end if;
  perform public.fleet_load(v_f, v_c, 100000, 1);
  v_p := public.fleet_job_plan(v_f);
  if not (v_p ? 'lines') or v_p->'lines' @? '$[*] ? (@.text like_regex "^TAKE")' then
    raise exception 'LD_HAUL: the hold full: %', left(v_p::text, 300);
  end if;
  raise notice 'PASS: LD_HAUL - %', (select string_agg(l->>'text', ' / ') from jsonb_array_elements(v_p->'lines') l);
end
$p$;
