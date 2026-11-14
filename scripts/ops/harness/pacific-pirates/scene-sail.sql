-- scene-sail.sql: AFTER 0414, lit: the pirates' own job adds roster fleets and each sails from her hub for a haunt; one is wrecked at her haunt and comes home. Run by probe.mjs (rolled back).
-- LOCAL SCENE (tests/harness.guard.spec.ts): it writes; the guard refuses anywhere but the local PGlite world.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $s$
declare
  v_now timestamptz := now();
  i int;
  v_r jsonb;
  v_f uuid;
  v_s text;
begin
  update public.world_config set value = 'true'::jsonb where key in ('pirates_bite', 'city_treasury_enabled', 'npc_refits_enabled') and value is distinct from 'true'::jsonb;
  update public.port_treasury t set ducats = greatest(t.ducats, 900000000) where t.port_id = public.pirate_capital();
  raise notice 'pirates_on %, refits_on %, size %, room %', public.pirates_on(), public.npc_refits_on(), public.pirate_size(), public.pirate_spend_room(v_now);
  for i in 0..40 loop
    v_r := public.tick_pirates(v_now + make_interval(mins => 10 * i));
    if i in (0, 1, 20, 40) then raise notice 'tick %: %', i, v_r; end if;
  end loop;
  raise notice 'fleets %, of the roster %, sailing %, cruising %, ships %, houses %, spent today %', (select count(*) from public.pirate_ships),
    (select count(*) from public.pirate_ships where ord > 1000),
    (select count(*) from public.pirate_ships n join public.fleets f on f.id = n.fleet_id where f.status = 'SAILING'),
    (select count(*) from public.pirate_ships_cruising), (select count(*) from public.ships s join public.pirate_ships n on n.fleet_id = s.fleet_id),
    (select count(distinct player_id) from public.pirate_ships), (select sum(spent) from public.pirate_spend_day);
  raise notice 'by hub: %', (select jsonb_object_agg(p.code, x.j) from (select n.home_port, jsonb_build_object('fleets', count(*), 'sailing', count(*) filter (where f.status = 'SAILING'),
      'haunts', count(distinct n.haunt_port), 'crew', (select sum(s.crew) from public.ships s where s.fleet_id = any (array_agg(n.fleet_id)))) as j
      from public.pirate_ships n join public.fleets f on f.id = n.fleet_id group by 1) x join public.ports p on p.id = x.home_port);
  raise notice 'pressure: %', (select jsonb_object_agg(s.code, sp.value) from public.sea_pressure sp join public.seas s on s.id = sp.sea_id);
  -- one roster fleet at sea is taken (every hull at 0, as the navy leaves her): her next step brings her home; an hour on she is whole
  select n.fleet_id into v_f from public.pirate_ships n join public.fleets f on f.id = n.fleet_id where n.ord > 1000 and f.status = 'SAILING' order by n.ord limit 1;
  update public.ships set durability = 0 where fleet_id = v_f;
  update public.voyages set status = 'ABORTED' where fleet_id = v_f and status = 'SAILING';
  update public.fleets set status = 'UNABLE_TO_SAIL', port_id = (select haunt_port from public.pirate_ships where fleet_id = v_f), lat = null, lon = null where id = v_f;
  v_s := public.pirate_ship_step(v_f, v_now + interval '7 hours');
  raise notice 'taken: step % (at home %, wrecked_at set %)', v_s, (select f.port_id = n.home_port from public.fleets f join public.pirate_ships n on n.fleet_id = f.id where f.id = v_f),
    (select wrecked_at is not null from public.pirate_ships where fleet_id = v_f);
  v_s := public.pirate_ship_step(v_f, v_now + interval '8 hours 1 minute');
  raise notice 'an hour on: step %, hull %, status %; next step %', v_s, (select min(durability) from public.ships where fleet_id = v_f), (select status from public.fleets where id = v_f),
    public.pirate_ship_step(v_f, v_now + interval '8 hours 2 minutes');
  raise notice 'the refit event: %', (select e.payload from public.events e where e.kind = 'REFITTED' and e.player_id = (select player_id from public.pirate_ships where fleet_id = v_f) order by e.created_at desc limit 1);
end
$s$;
