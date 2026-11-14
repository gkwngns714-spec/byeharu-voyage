do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
-- cost.sql: LOCAL SCENE (rolled back by the runner). What 0419 adds to the Stats count, at production's size (2026-11-15: 372 cargo ships, 43 navy
-- ships, the pirates growing to 108 fleets; ~943 merchant ships). Builds cargo ships (37 a realm), navy ships (4 a realm) and 0339's seven pirate
-- ships, a hold on every cargo ship, then times public.stats_fleets_count five times (the phase's work), one whole count, and world.stats_fleets
-- 200 times (the face's read, asked each second). Run: node scripts/ops/harness/qq-tmp.mjs (or more-ships/q.mjs) scripts/ops/harness/stats-fleets/cost.sql
do $c$
declare
  r      record;
  o      int;
  v_t    timestamptz;
  v_ms   numeric[] := '{}';
  v_read numeric;
  v_ret  jsonb;
  v_f    jsonb;
  v_cap  uuid;
  v_stn  uuid;
  i      int;
begin
  update public.world_config set value = 'true'::jsonb
   where key in ('city_treasury_enabled', 'economy_closed', 'convoys_enabled', 'pirates_bite', 'npc_refits_enabled') and value is distinct from 'true'::jsonb;
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.cargo_fleet_sizes set ships = 37, read_at = now();
  for r in select g.nation_id, public.realm_capital(g.nation_id) as cap from public.great_powers g join public.nations n on n.id = g.nation_id
             join public.ports p on p.code = n.capital_port_code and p.kind = 'HARBOUR' where not g.pirate order by n.code loop
    for i in 1 .. 10 loop perform public.cargo_ships_commission(r.nation_id); end loop;   -- a call builds a few; ten calls reach the number
    if r.cap is not null then
      update public.port_treasury t set ducats = 50000000 where t.port_id = r.cap;
      select a.port_id into v_stn from public.port_allegiance a where a.nation_id = r.nation_id and public.refit_yard(a.port_id) is not null order by a.port_id limit 1;
      for o in 1 .. 4 loop
        perform public.navy_commission(r.nation_id, 9000 + o, r.cap, public.refit_yard(r.cap), v_stn, now() - interval '3 days');
      end loop;
    end if;
  end loop;
  update public.port_treasury t set ducats = 975934180 where t.port_id = public.pirate_capital();
  for o in 1 .. 7 loop
    perform public.pirate_commission(o, public.pirate_home_of(o), public.refit_yard(public.pirate_home_of(o)), now() - interval '2 days');
  end loop;
  update public.ships s set cargo = (select jsonb_object_agg(g.code, 5) from (select g.code from public.goods g order by g.code limit 4) g)
   where s.fleet_id in (select c.fleet_id from public.cargo_ships c);
  for i in 1 .. 5 loop
    v_t := clock_timestamp();
    v_f := public.stats_fleets_count(now() - interval '30 minutes', now());
    v_ms := v_ms || round(extract(epoch from clock_timestamp() - v_t) * 1000, 1);
  end loop;
  v_ret := public.tick_stats(now());
  v_t := clock_timestamp();
  for i in 1 .. 200 loop
    perform world.stats_fleets();
  end loop;
  v_read := round(extract(epoch from clock_timestamp() - v_t) * 1000 / 200.0, 2);
  raise notice 'COST: navy % fleets, pirates % fleets, cargo % fleets (% ships), merchant ships %; stats_fleets_count ms x5 %; the whole count % ms, its fleets phase % ms; world.stats_fleets % ms a read',
    v_f -> 'navy' ->> 'fleets', v_f -> 'pirates' ->> 'fleets', v_f -> 'cargo' ->> 'fleets', v_f -> 'cargo' ->> 'ships', v_f -> 'merchants' ->> 'ships', v_ms,
    v_ret ->> 'ms', (select r2.receipt -> 'phases' ->> 'fleets' from public.stats_runs r2 order by r2.at desc limit 1), v_read;
end $c$;
