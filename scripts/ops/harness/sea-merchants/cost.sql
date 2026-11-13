-- 0397 COST SCENE (sim.mjs --scene=scripts/ops/harness/sea-merchants/cost.sql runs it dark and lit; sea-conditions/run.mjs runs it before the file): 60 merchants
-- spread over the roster, each one's loops on offer timed (public.npc_loop_candidates) and then her lap start (public.npc_plan, alone). One COST line.
-- LOCAL PGlite WORLD ONLY (scripts/ops/harness/README.md): this scene writes and its runner rolls it back. The first statement refuses a real server.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $$
declare t timestamptz; r record; c numeric := 0; p numeric := 0; n int := 0; m int; j jsonb; cmax numeric := 0; pmax numeric := 0; d numeric;
begin
  update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled');
  update public.standing_routes sr set fleet_id = nf.fleet_id, lap_id = null, paused_reason = null from public.npc_fleets nf where nf.route_id = sr.id;
  for r in select nf.fleet_id, nf.route_id, h.home_port_id from public.npc_fleets nf join public.npc_houses h on h.player_id = nf.player_id where nf.roster_ord % 14 = 5 order by nf.roster_ord limit 60 loop
    t := clock_timestamp();
    select count(*) into m from public.npc_loop_candidates(r.route_id, r.fleet_id, r.home_port_id, public.fleet_free_hold(r.fleet_id), greatest(coalesce(voyage.fleet_speed_at(r.fleet_id, 1), 0), 0.1));
    d := extract(epoch from clock_timestamp() - t) * 1000; c := c + d; cmax := greatest(cmax, d);
    t := clock_timestamp();
    j := public.npc_plan(now(), r.route_id);
    d := extract(epoch from clock_timestamp() - t) * 1000; p := p + d; pmax := greatest(pmax, d);
    n := n + 1;
  end loop;
  raise notice 'COST over % merchants: candidates avg % ms max % ms; a lap start (npc_plan alone) avg % ms max % ms', n, round(c / n), round(cmax), round(p / n), round(pmax);
end $$;
