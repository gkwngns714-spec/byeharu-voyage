do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
-- cost.sql: LOCAL SCENE (rolled back by the runner). What 0431 costs at production's size (2026-11-15: ~40 navy fleets, the pirates growing to ~108,
-- 100-370 cargo ships). Builds 0419's scene (cargo ships, 4 navy ships a realm, 0339's seven pirates), then fills the book as 8 full days would:
-- every fleet a row every hour (192 hours, five keys each; the real book is thinner: a cargo ship's idle hours write nothing), and 12 lines a fleet.
-- Times public.fleet_book_add (1,000 calls), the three lists (public.stats_fleet_list_rows, five times), the whole Stats count with its fleets phase,
-- world.stats_fleet_list and world.stats_fleet (200 reads each: each face asks every second).
-- Run: BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/more-ships/q.mjs scripts/ops/harness/fleet-tabs/cost.sql
do $c$
declare
  r      record;
  o      int;
  i      int;
  v_t    timestamptz;
  v_ms   numeric[] := '{}';
  v_add  numeric;
  v_list numeric;
  v_page numeric;
  v_ret  jsonb;
  v_stn  uuid;
  v_one  uuid;
  v_rows bigint;
begin
  update public.world_config set value = 'true'::jsonb
   where key in ('city_treasury_enabled', 'economy_closed', 'convoys_enabled', 'pirates_bite', 'npc_refits_enabled') and value is distinct from 'true'::jsonb;
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.cargo_fleet_sizes set ships = 37, read_at = now();
  for r in select g.nation_id, public.realm_capital(g.nation_id) as cap from public.great_powers g join public.nations n on n.id = g.nation_id
             join public.ports p on p.code = n.capital_port_code and p.kind = 'HARBOUR' where not g.pirate order by n.code loop
    for i in 1 .. 10 loop perform public.cargo_ships_commission(r.nation_id); end loop;
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

  -- 8 days of a full book: every fleet, every hour; 12 lines a fleet
  insert into public.fleet_book (fleet_id, hour, figs)
  select f.id, to_timestamp(floor(extract(epoch from now()) / 3600) * 3600) - make_interval(hours => h),
         jsonb_build_object('upkeep', 500, 'fights', 1, 'won', 1, 'hull', 12.5, 'delivered', 2000)
    from (select fleet_id as id from public.navy_ships union all select fleet_id from public.pirate_ships union all select fleet_id from public.cargo_ships) f
   cross join generate_series(0, 191) h;
  insert into public.fleet_lines (fleet_id, at, kind, line)
  select f.id, now() - make_interval(mins => k), 'FIGHT', jsonb_build_object('foe', 'Someone', 'result', 'WON', 'hull', 3)
    from (select fleet_id as id from public.navy_ships union all select fleet_id from public.pirate_ships union all select fleet_id from public.cargo_ships) f
   cross join generate_series(1, 12) k;
  select count(*) into v_rows from public.fleet_book;
  analyze public.fleet_book;
  analyze public.fleet_lines;

  select c.fleet_id into v_one from public.cargo_ships c order by c.fleet_id limit 1;
  v_t := clock_timestamp();
  for i in 1 .. 1000 loop
    perform public.fleet_book_add(v_one, now(), '{"upkeep": 500, "fights": 1}'::jsonb, case when i % 4 = 0 then 'FIGHT' end, '{"foe": "x"}'::jsonb);
  end loop;
  v_add := round(extract(epoch from clock_timestamp() - v_t) * 1000 / 1000.0, 3);
  for i in 1 .. 5 loop
    v_t := clock_timestamp();
    perform public.stats_fleet_list_rows(k.kind, now()) from (values ('NAVY'), ('PIRATE'), ('CARGO')) k(kind);
    v_ms := v_ms || round(extract(epoch from clock_timestamp() - v_t) * 1000, 1);
  end loop;
  v_ret := public.tick_stats(now());
  v_t := clock_timestamp();
  for i in 1 .. 200 loop
    perform world.stats_fleet_list('CARGO');
  end loop;
  v_list := round(extract(epoch from clock_timestamp() - v_t) * 1000 / 200.0, 2);
  v_t := clock_timestamp();
  for i in 1 .. 200 loop
    perform world.stats_fleet(v_one);
  end loop;
  v_page := round(extract(epoch from clock_timestamp() - v_t) * 1000 / 200.0, 2);
  raise notice 'COST: navy %, pirates %, cargo % fleets; book % rows, % lines, % kB; fleet_book_add % ms a call; the three lists x5 % ms; the whole count % ms, its fleets phase % ms; world.stats_fleet_list(CARGO) % ms a read (% kB); world.stats_fleet % ms a read',
    (select count(*) from public.navy_ships), (select count(*) from public.pirate_ships), (select count(*) from public.cargo_ships), v_rows,
    (select count(*) from public.fleet_lines), (pg_total_relation_size('public.fleet_book') + pg_total_relation_size('public.fleet_lines')) / 1024, v_add, v_ms,
    v_ret ->> 'ms', (select r2.receipt -> 'phases' ->> 'fleets' from public.stats_runs r2 order by r2.at desc limit 1), v_list,
    (select length(x.figures::text) / 1024 from public.stats_fleet_list x where x.kind = 'CARGO'), v_page;
end $c$;
