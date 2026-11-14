-- premise.sql: READ ONLY on prod, one statement (2026-11-15, before 0419): the shape of the four kinds of ship, the sizes of the books a raid count
-- could read (catalog figures only, no scan), and the Stats count's last runs. Small tables only: navy_ships, pirate_ships, cargo_ships (with their fleets
-- and ships by key), stats_runs (7 days of receipts).
begin transaction read only;
select jsonb_build_object(
  'at', now(),
  'sizes', (select jsonb_object_agg(c.relname, jsonb_build_object('rows', c.reltuples::bigint, 'mb', round(c.relpages * 8 / 1024.0)))
              from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname in ('voyage_events', 'events', 'ledger', 'voyages', 'navy_fight_log', 'ships', 'fleets')),
  'navy', (select jsonb_agg(x) from (select nn.code, f.status, (n.laid_up_at is not null) as laid_up, count(*) as fleets,
                                             sum((select count(*) from public.ships s where s.fleet_id = n.fleet_id)) as ships,
                                             count(*) filter (where n.fought_at > now() - interval '24 hours') as fought_24h
                                        from public.navy_ships n join public.fleets f on f.id = n.fleet_id join public.nations nn on nn.id = n.nation_id
                                       group by 1, 2, 3 order by 1, 2, 3) x),
  'navy_results_24h', (select jsonb_object_agg(r, k) from (select n.fought ->> 'result' as r, count(*) as k from public.navy_ships n where n.fought_at > now() - interval '24 hours' group by 1) y),
  'pirates', (select jsonb_agg(x) from (select p.code as home, f.status, (n.laid_up_at is not null) as laid_up, (n.wrecked_at is not null) as wrecked, (n.ord > 1000) as roster,
                                               count(*) as fleets, sum((select count(*) from public.ships s where s.fleet_id = n.fleet_id)) as ships,
                                               count(*) filter (where n.fought_at > now() - interval '24 hours') as fought_24h
                                          from public.pirate_ships n join public.fleets f on f.id = n.fleet_id left join public.ports p on p.id = n.home_port
                                         group by 1, 2, 3, 4, 5 order by 1, 2, 3, 4, 5) x),
  'cargo', (select jsonb_agg(x) from (select f.status, (c.laid_up_at is not null) as laid_up, count(*) as fleets,
                                             sum((select count(*) from public.ships s where s.fleet_id = c.fleet_id)) as ships
                                        from public.cargo_ships c join public.fleets f on f.id = c.fleet_id group by 1, 2 order by 1, 2) x),
  'runs', (select jsonb_agg(x order by x.at desc) from (select r.at, r.ms, r.receipt -> 'phases' as phases from public.stats_runs r order by r.at desc limit 4) x)
) as premise;
commit;
