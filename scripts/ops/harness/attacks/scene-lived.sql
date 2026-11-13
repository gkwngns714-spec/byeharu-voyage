do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
-- ATTACKS, LOCAL SCENE (it WRITES). A WORLD LIVED IN, AS PRODUCTION WILL BE WHEN 0375 IS DEPLOYED: the switches the owner lit on production and this chain does not
-- (convoys, the armed cargo ship, the navy, the city purses) and the lights 0369 to 0373 that go before (regard, crown hulls at their level), with Spain's and France's cargo
-- ships made by the real job, every one the armed navire, some at sea, and the level written by the real writer. public.attack_ready() then answers ready.
-- proof-0375.mjs applies 0375 on it, and on the same world with one thing taken away each time. Run it alone to look:
--   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/attacks/run.mjs --before=20260818000375 scripts/ops/harness/attacks/scene-lived.sql scripts/ops/harness/attacks/before-light.sql
do $$
declare
  r record;
  c public.cargo_ships%rowtype;
  i int := 0;
begin
  update public.world_config set value = 'true'::jsonb
   where key in ('city_treasury_enabled', 'convoys_enabled', 'convoy_armed_enabled', 'navy_enabled', 'regard_enabled', 'npc_ship_level_enabled');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 50000000, reserve = 0;
  update public.ports set crew_pool = 5000;
  for r in select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code in ('ESP', 'FRA') loop
    perform public.tick_cargo_ships(now(), r.nation_id);
    perform public.tick_cargo_ships(now(), r.nation_id);
  end loop;
  -- ten of them sail with funds aboard, slowed so they are still at sea
  for c in select x.* from public.cargo_ships x join public.fleets f on f.id = x.fleet_id where f.status = 'DOCKED' and x.out_load is null order by x.nation_id, x.ord limit 10 loop
    update public.fleets set ready_at = null where id = c.fleet_id;
    perform public.convoy_book('LOADED', c.fleet_id, c.player_id, c.home_port_id, 100000 + 40000 * i);
    perform public.cargo_ship_step(c.fleet_id, now());
    update public.voyages vo set speed_profile = (select jsonb_agg(to_jsonb(e::text::numeric / 100) order by o) from jsonb_array_elements(vo.speed_profile) with ordinality t(e, o))
     where vo.fleet_id = c.fleet_id and vo.status = 'SAILING';
    perform voyage.recompute_eta(vo.id) from public.voyages vo where vo.fleet_id = c.fleet_id and vo.status = 'SAILING';
    i := i + 1;
  end loop;
  perform public.crown_hull_level_fix();
  raise notice 'scene-lived: % cargo ships, % at sea; public.attack_ready: %', (select count(*) from public.cargo_ships),
    (select count(*) from public.cargo_ships x join public.fleets f on f.id = x.fleet_id where f.status = 'SAILING'), public.attack_ready();
end $$;
