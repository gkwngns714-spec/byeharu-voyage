-- 0328 DARK PARITY SCENE: run by proof-0328.mjs on the world BEFORE the file and AFTER it, rolled back each time, beside scripts/ops/harness/rich-cities/dark-scene.sql (0324's, which covers whole laps, flows, purses and the book).
-- This one covers what 0328 cuts that that scene does not reach: the wage of every kind of fleet, a commissioned ship, a merchant's and a cargo ship's refit. It names only what existed before 0328. Every SCENE line must be equal.
do $$
declare
  v_nat  uuid;
  v_cap  uuid;
  v_fl   uuid;
  v_hum  uuid;
  v_hfl  uuid;
  v_r    text;
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'convoys_enabled', 'npc_refits_enabled');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 90000000, reserve = 0;
  select g.nation_id, p.id into v_nat, v_cap
    from public.great_powers g join public.nations n on n.id = g.nation_id join public.ports p on p.code = n.capital_port_code where n.code = 'PRT';

  -- a commission: class, crew, stores, purse
  perform public.tick_cargo_ships(now(), v_nat);
  v_fl := (select c.fleet_id from public.cargo_ships c where c.nation_id = v_nat and c.ord = 1);
  raise notice 'SCENE: made %', (select jsonb_agg(jsonb_build_array(c.ord, k.code, s.crew, s.water_t, s.food_t, s.name, p.ducats) order by c.ord)
                                   from public.cargo_ships c join public.ships s on s.fleet_id = c.fleet_id join public.ship_classes k on k.id = s.class_id join public.players p on p.id = c.player_id where c.nation_id = v_nat);
  raise notice 'SCENE: wage_cargo % %', public.fleet_wage(v_fl, false), public.fleet_wage(v_fl, true);

  -- a company's wage
  insert into public.players (company_name, nation_id, ducats) values ('Scene 0328 house', v_nat, 0) returning id into v_hum;
  v_hfl := public.form_fleet(v_hum, 'Scene 0328 fleet', v_cap);
  perform public.commission_ship(v_hum, v_hfl, 'navire', 'Scene 0328 hull', true, true);
  raise notice 'SCENE: wage_company % % %', public.fleet_wage(v_hfl, false), public.fleet_wage(v_hfl, true), public.fleet_wage(v_hfl, false, 7);

  -- a cargo ship's refit: crewless, her quay untouched
  update public.ships s set durability = 0 where s.fleet_id = v_fl;
  update public.fleets f set status = 'UNABLE_TO_SAIL' where f.id = v_fl;
  v_r := public.npc_refit_step(v_fl, now());
  raise notice 'SCENE: refit_cargo % % %', v_r, (select jsonb_agg(jsonb_build_array(s.crew, s.durability > 0)) from public.ships s where s.fleet_id = v_fl), (select p.crew_pool from public.ports p where p.id = v_cap);

  -- a merchant's refit: hands from the quay, down to its floor
  v_hfl := (select nf.fleet_id from public.npc_fleets nf order by nf.roster_ord limit 1);
  v_cap := public.fleet_origin(v_hfl);
  update public.ships s set durability = 0, crew = 0 where s.fleet_id = v_hfl;
  update public.fleets f set status = 'UNABLE_TO_SAIL', port_id = v_cap, lat = null, lon = null where f.id = v_hfl;
  update public.ports p set crew_pool = public.wc_int('npc_crew_pool_floor') + 17 where p.id = v_cap;
  v_r := public.npc_refit_step(v_hfl, now());
  raise notice 'SCENE: refit_merchant % % %', v_r, (select jsonb_agg(s.crew) from public.ships s where s.fleet_id = v_hfl), (select p.crew_pool from public.ports p where p.id = v_cap);

  raise exception using errcode = 'ZY328';
exception when sqlstate 'ZY328' then
  null;
end
$$;
