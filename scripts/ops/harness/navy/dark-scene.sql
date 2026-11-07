-- 0331 DARK PARITY SCENE: run by proof-0331.mjs on the world BEFORE the file and AFTER it, rolled back each time, beside the rich-cities and armed-cargo scenes.
-- This one covers what 0331 cuts that those do not reach: the map's two reads, byte for byte with the clock taken out; who is on the sea; the kind, origin, wage and dock fee of a merchant, a cargo ship and a company;
-- crown stores and a patch, the lifted lines; the purse the fleet curve reads; the money figures; and the job with the switch off. It names only what existed before 0331, except the job, which is skipped when absent.
-- LOCAL PGlite WORLD ONLY (scripts/ops/harness/README.md): this scene writes and its runner rolls it back. The first statement refuses a real server (inet_server_addr() is not null there, null on PGlite), so `db query --linked -f` can never commit it on production.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $$
declare
  v_nat  uuid;
  v_cap  uuid;
  v_fl   uuid;
  v_pl   uuid;
  v_hum  uuid;
  v_hfl  uuid;
  v_mer  uuid;
  v_ml   uuid;
  v_s    text;
  v_flow bigint := coalesce((select max(id) from public.treasury_flows), 0);
  v_ev   bigint := (select count(*) from public.events);
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'convoys_enabled', 'npc_traders_enabled', 'standing_routes_enabled');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 90000000, reserve = 0;
  select g.nation_id, p.id into v_nat, v_cap
    from public.great_powers g join public.nations n on n.id = g.nation_id join public.ports p on p.code = n.capital_port_code where n.code = 'PRT';
  perform public.tick_cargo_ships(now(), v_nat);
  select c.fleet_id, c.player_id into v_fl, v_pl from public.cargo_ships c where c.nation_id = v_nat and c.ord = 1;
  insert into public.players (company_name, nation_id, ducats) values ('Scene 0331 house', v_nat, 0) returning id into v_hum;
  v_hfl := public.form_fleet(v_hum, 'Scene 0331 fleet', v_cap);
  perform public.commission_ship(v_hum, v_hfl, 'navire', 'Scene 0331 hull', true, true);
  select nf.fleet_id, nf.player_id into v_mer, v_ml from public.npc_fleets nf order by nf.roster_ord limit 1;

  -- the map's reads, byte for byte, ids of this run's new rows and every clock out
  raise notice 'SCENE: roster %', md5((select jsonb_agg(e - array['id', 'company', 'next_lap_at'] order by e ->> 'name', e ->> 'status', e ->> 'port') from jsonb_array_elements(world.sea_roster(null) -> 'fleets') e)::text);
  raise notice 'SCENE: roster_keys %', (select jsonb_agg(distinct k) from jsonb_array_elements(world.sea_roster(null) -> 'fleets') e cross join lateral jsonb_object_keys(e) k);
  raise notice 'SCENE: roster_merchant %', (select md5(e::text) from jsonb_array_elements(world.sea_roster(null) -> 'fleets') e where e ->> 'id' = v_mer::text);
  raise notice 'SCENE: traffic % %', (select count(*) from jsonb_array_elements(world.sea_traffic(jsonb_build_object('south', -89, 'north', 89, 'west', -179, 'east', 179)) -> 'fleets') e),
                                     (world.sea_traffic(jsonb_build_object('south', -89, 'north', 89, 'west', -179, 'east', 179)) ->> 'total');
  raise notice 'SCENE: houses %', (select jsonb_agg(jsonb_build_array(h.ink, h.kind, h.n) order by h.ink, h.kind) from (select s.ink, s.kind, count(*) as n from public.sea_houses() s group by 1, 2) h);

  -- what a fleet is, and what she owes
  raise notice 'SCENE: kinds % % %', public.fleet_kind(v_fl), public.fleet_kind(v_mer), public.fleet_kind(v_hfl);
  raise notice 'SCENE: origins % % %', public.fleet_origin(v_fl) = v_cap, public.fleet_origin(v_mer) is not null, public.fleet_origin(v_hfl);
  raise notice 'SCENE: wage % % %', public.fleet_wage(v_fl, false), public.fleet_wage(v_mer, false), public.fleet_wage(v_hfl, false);
  raise notice 'SCENE: fee % % %', public.port_fee(v_cap, v_pl, 1000), public.port_fee(v_cap, v_ml, 1000), public.port_fee(v_cap, v_hum, 1000);

  -- the lifted lines: an armed hull's stores, a wrecked cargo ship's patch, the curve's purse
  perform public.cargo_upkeep(v_hfl, v_cap);
  raise notice 'SCENE: stores %', (select jsonb_agg(jsonb_build_array(s.water_t, s.food_t)) from public.ships s where s.fleet_id = v_hfl);
  update public.world_config set value = to_jsonb('navire'::text) where key = 'convoy_ship_class';
  update public.world_config set value = 'true'::jsonb where key = 'convoy_armed_enabled';
  update public.ships s set durability = 1 where s.fleet_id = v_fl;
  update public.fleets f set status = 'UNABLE_TO_SAIL', ready_at = null where f.id = v_fl;
  v_s := public.cargo_ship_step(v_fl, now());
  raise notice 'SCENE: patch % %', v_s, (select jsonb_agg(jsonb_build_array(f.status, f.ready_at - now() > interval '0', s.durability > 1)) from public.fleets f join public.ships s on s.fleet_id = f.id where f.id = v_fl);
  update public.world_config set value = 'false'::jsonb where key = 'convoy_armed_enabled';
  update public.world_config set value = to_jsonb('qpinnace'::text) where key = 'convoy_ship_class';
  raise notice 'SCENE: curve %', (select jsonb_agg(jsonb_build_array(w.cash, w.ships) order by n.code) from public.convoy_ships_wanted() w join public.nations n on n.id = w.nation_id);

  -- the money figures: the fold's own arithmetic
  raise notice 'SCENE: at_sea %', (select jsonb_build_array(
    (select count(*) from public.fleets f join public.players p on p.id = f.player_id where f.status = 'SAILING' and p.is_npc),
    (select count(*) from public.fleets f where f.status = 'SAILING')));
  update public.fleets f set status = 'SAILING', port_id = null, lat = null, lon = null where f.id = v_fl;
  perform public.stats_live_fold(now(), true);
  raise notice 'SCENE: fold %', (select jsonb_build_array(l.at_sea, l.at_sea_merchants) from public.stats_live l);

  raise notice 'SCENE: figures %', public.cargo_figures();

  -- the job, if it exists, with the switch off: nothing written
  if to_regprocedure('public.tick_navy(timestamp with time zone,uuid)') is not null then
    execute 'select public.tick_navy()';
  end if;
  raise notice 'SCENE: moved % %', (select count(*) from public.treasury_flows f where f.id > v_flow and f.kind not in ('CROWN_CALL')) , (select count(*) from public.events) - v_ev;

  raise exception using errcode = 'ZY331';
exception when sqlstate 'ZY331' then
  null;
end
$$;
