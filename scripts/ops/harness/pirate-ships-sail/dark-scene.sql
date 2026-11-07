-- 0339 DARK PARITY SCENE: run by proof-0339.mjs on the world BEFORE the file and AFTER it, rolled back each time, beside the rich-cities, armed-cargo, navy, navy-comes and brethren scenes.
-- It covers what 0339 cuts: the map's two reads, byte for byte with the clock taken out; who is on the sea; the kind, origin, wage and dock fee of a merchant, a cargo ship and a company; a departure's FROZEN PATH, byte for
-- byte; 960 RAID DAYS settled through the real engine with the voyage id pinned (the fight's seed), every payload digested; the lifted share; a pirate home's market after one regen run at a pinned clock (stock, target, glut, day);
-- the money figures; the attack door's refusal of a merchant; and the job with the switch off. It names only what existed before 0339, except the job, which is skipped when absent.
do $$
declare
  c_t    constant timestamptz := '2026-11-07 12:00:00+00';
  c_voy  constant uuid := '00000000-0339-4000-8000-00000000d960';
  v_nat  uuid;
  v_cap  uuid;
  v_por  uuid;
  v_fl   uuid;
  v_pl   uuid;
  v_hum  uuid;
  v_hfl  uuid;
  v_mer  uuid;
  v_ml   uuid;
  v_voy  uuid;
  v_p    jsonb;
  v_n    int;
  v_d    int;
  v_flow bigint := coalesce((select max(id) from public.treasury_flows), 0);
  v_ev   bigint := (select count(*) from public.events);
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'convoys_enabled', 'npc_traders_enabled', 'standing_routes_enabled', 'combat_bite');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 90000000, reserve = 0;
  select g.nation_id, p.id into v_nat, v_cap
    from public.great_powers g join public.nations n on n.id = g.nation_id join public.ports p on p.code = n.capital_port_code where n.code = 'PRT';
  v_por := (select p.id from public.ports p where p.code = 'POR');
  perform public.tick_cargo_ships(c_t, v_nat);
  select c.fleet_id, c.player_id into v_fl, v_pl from public.cargo_ships c where c.nation_id = v_nat and c.ord = 1;
  insert into public.players (company_name, nation_id, ducats) values ('Scene 0339 house', v_nat, 1000000) returning id into v_hum;
  v_hfl := public.form_fleet(v_hum, 'Scene 0339 fleet', v_cap);
  perform public.commission_ship(v_hum, v_hfl, 'navire', 'Scene 0339 hull', true, true);
  -- 0276 rolls every new hull her own figures: pinned, so her speed (the path's nm a day) and her hull (the fight's sides) are the same before and after the file
  update public.ships s set roll_speed = 1, roll_hold = 1, roll_stores = 1, roll_hull = 1, roll_crew = 1, roll_handling = 1, water_t = 100000, food_t = 100000 where s.fleet_id = v_hfl;
  update public.ships s set durability = (select b.durability from public.ship_base(s.id) b) where s.fleet_id = v_hfl;
  select nf.fleet_id, nf.player_id into v_mer, v_ml from public.npc_fleets nf order by nf.roster_ord limit 1;

  -- the map's reads, byte for byte, ids of this run's new rows and every clock out
  raise notice 'SCENE: roster %', md5((select jsonb_agg(e - array['id', 'company', 'next_lap_at'] order by e ->> 'name', e ->> 'status', e ->> 'port') from jsonb_array_elements(world.sea_roster(null) -> 'fleets') e)::text);
  raise notice 'SCENE: roster_keys %', (select jsonb_agg(distinct k) from jsonb_array_elements(world.sea_roster(null) -> 'fleets') e cross join lateral jsonb_object_keys(e) k);
  raise notice 'SCENE: roster_merchant %', (select md5(e::text) from jsonb_array_elements(world.sea_roster(null) -> 'fleets') e where e ->> 'id' = v_mer::text);
  raise notice 'SCENE: traffic % %', (select count(*) from jsonb_array_elements(world.sea_traffic(jsonb_build_object('south', -89, 'north', 89, 'west', -179, 'east', 179)) -> 'fleets') e),
                                     (world.sea_traffic(jsonb_build_object('south', -89, 'north', 89, 'west', -179, 'east', 179)) ->> 'total');
  raise notice 'SCENE: houses %', (select jsonb_agg(jsonb_build_array(h.ink, h.kind, h.n) order by h.ink, h.kind) from (select s.ink, s.kind, count(*) as n from public.sea_houses() s group by 1, 2) h);
  raise notice 'SCENE: figures %', public.cargo_figures();

  -- what a fleet is, and what she owes
  raise notice 'SCENE: kinds % % %', public.fleet_kind(v_fl), public.fleet_kind(v_mer), public.fleet_kind(v_hfl);
  raise notice 'SCENE: origins % % %', public.fleet_origin(v_fl) = v_cap, public.fleet_origin(v_mer) is not null, public.fleet_origin(v_hfl);
  raise notice 'SCENE: crown % % % %', public.crown_house(v_pl), public.crown_house(v_ml), public.crown_house(v_hum), public.crown_nation(v_fl) = v_nat;
  raise notice 'SCENE: wage % % %', public.fleet_wage(v_fl, false), public.fleet_wage(v_mer, false), public.fleet_wage(v_hfl, false);
  raise notice 'SCENE: fee % % %', public.port_fee(v_cap, v_pl, 1000), public.port_fee(v_cap, v_ml, 1000), public.port_fee(v_cap, v_hum, 1000);

  -- a departure's frozen path, byte for byte: 960 voyage-days, every sea in turn, the id pinned so the fight's seed is the same before and after
  v_p := (select jsonb_agg(jsonb_build_object('a', jsonb_build_array(0, 0), 'b', jsonb_build_array(0, 0), 'nm', round(voyage.fleet_speed(v_hfl) * 24, 2), 'sea_id', s.id, 'hazard_mult', 1000) order by d.n)
            from generate_series(1, 960) d(n) cross join lateral (select x.id from public.seas x order by x.code offset (d.n - 1) % (select count(*) from public.seas) limit 1) s);
  v_voy := voyage.depart(v_hfl, v_p, v_cap, v_cap, c_t);
  update public.voyages set id = c_voy where id = v_voy;
  raise notice 'SCENE: path % %', (select md5(o.path::text) from public.voyages o where o.id = c_voy), (select jsonb_array_length(o.path) from public.voyages o where o.id = c_voy);
  raise notice 'SCENE: share % %', voyage.raid_takes(c_voy, 7, v_hfl, 'EVADED'), (select md5(string_agg(d.n || ':' || voyage.rng(c_voy, d.n, 'plunder')::text, ',' order by d.n)) from generate_series(1, 20) d(n));

  -- 960 raid days through the real settle: the sea on one setting (PIRATES, magnitude 0.5), hull, hands and stores restored after each day
  alter function voyage.hazard_roll(uuid, integer) rename to hazard_roll_real_s39;
  execute $f$
create function voyage.hazard_roll(p_voyage uuid, p_day integer)
returns table (occurred boolean, kind text, magnitude numeric, p_hazard numeric)
language plpgsql stable
as $b$
begin
  return query select true, 'PIRATES'::text, 0.5::numeric, 1::numeric;
end
$b$
  $f$;
  for v_d in 1 .. 960 loop
    perform voyage.settle(v_hfl, voyage.day_ends_at(c_voy, v_d));
    update public.ships s set durability = (select b.durability from public.ship_base(s.id) b), crew = 60, water_t = 100000, food_t = 100000 where s.fleet_id = v_hfl;
    update public.players p set ducats = 1000000 where p.id = v_hum;
  end loop;
  select count(*), count(*) filter (where e.kind = 'PIRATES') into v_n, v_d from public.voyage_events e where e.voyage_id = c_voy;
  raise notice 'SCENE: raids % % %', v_n, v_d, (select md5(string_agg(e.day_index || ':' || e.kind || ':' || e.resolved_at::text || ':' || e.payload::text, E'\n' order by e.day_index)) from public.voyage_events e where e.voyage_id = c_voy);
  raise notice 'SCENE: outcomes %', (select jsonb_object_agg(x.o, x.n) from (select e.payload ->> 'outcome' as o, count(*) as n from public.voyage_events e where e.voyage_id = c_voy group by 1) x);
  raise notice 'SCENE: after_raids %', (select jsonb_build_array(sum(s.durability), sum(s.crew), md5(string_agg(s.cargo::text, ',' order by s.id))) from public.ships s where s.fleet_id = v_hfl);

  -- a pirate home's market after one regen run at a pinned clock: stock, target, base, glut and the day (the drift's noise is random and is left out)
  perform public.tick_market_drift(c_t + interval '1 day', v_por);
  raise notice 'SCENE: regen %', (select md5(string_agg(g.code || ':' || pg.stock || ':' || pg.stock_target || ':' || coalesce(pg.base_target::text, '-') || ':' || pg.glut || ':' || pg.last_regen_day, ',' order by g.code))
                                    from public.port_goods pg join public.goods g on g.id = pg.good_id where pg.port_id = v_por);

  -- the money figures: the fold's own arithmetic
  raise notice 'SCENE: at_sea %', (select jsonb_build_array(
    (select count(*) from public.fleets f join public.players p on p.id = f.player_id where f.status = 'SAILING' and p.is_npc),
    (select count(*) from public.fleets f where f.status = 'SAILING')));
  perform public.stats_live_fold(c_t + interval '2 days', true);
  raise notice 'SCENE: fold %', (select jsonb_build_array(l.at_sea, l.at_sea_merchants, l.set_aside) from public.stats_live l);

  -- the attack door refuses a merchant, with the words it had
  update public.world_config set value = 'true'::jsonb where key = 'attack_enabled';
  begin
    perform public.attack_for(v_hum, v_hfl, v_mer, null, c_t + interval '3 days');
    raise notice 'SCENE: attack_merchant opened';
  exception when others then
    raise notice 'SCENE: attack_merchant %', left(sqlerrm, 60);
  end;
  update public.world_config set value = 'false'::jsonb where key = 'attack_enabled';

  -- the job, if it exists, with the switch off: nothing written
  if to_regprocedure('public.tick_pirates(timestamp with time zone)') is not null then
    execute 'select public.tick_pirates()';
  end if;
  raise notice 'SCENE: moved % %', (select count(*) from public.treasury_flows f where f.id > v_flow and f.kind not in ('CROWN_CALL')), (select count(*) from public.events) - v_ev;

  raise exception using errcode = 'ZY339';
exception when sqlstate 'ZY339' then
  null;
end
$$;
