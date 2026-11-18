-- PROD CHECK (read only) before 0454: the 7 bodies 0454 re-cuts are the chain's at 0453 (md5 of each live definition, CR stripped), its 5 new
-- names are free, and what its probe needs is there. Compare each md5 with the line in docs/dev-log/2026-11-18-stores-quote.md (PROD CHECKS).
begin transaction read only;
select f.fn, md5(replace(pg_get_functiondef(to_regprocedure(f.fn)), E'\r', '')) as md5,
       (select bool_and(to_regprocedure(n) is null) from unnest(array['voyage.ship_speed_parts(uuid)', 'voyage.ship_speed_of(jsonb,numeric)', 'voyage.fleet_speed_parts(uuid,boolean)',
                                                                  'voyage.fleet_speed_of(jsonb,numeric,jsonb)', 'world.trip_leg(jsonb,jsonb,numeric,boolean,numeric)']) n) as new_names_free,
       (select count(*) from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR') = 1
         and (select count(*) from public.ship_classes c where c.code = 'barca') = 1
         and (select count(*) from public.nations n where n.code = 'PRT') = 1 as probe_needs_there
  from unnest(array['voyage.ship_speed_at(uuid,numeric)', 'voyage.fleet_speed_alone_at(uuid,numeric)', 'voyage.fleet_speed_at(uuid,numeric)',
                    'world.trip_hulls(uuid)', 'world.trip_cost(uuid,jsonb)', 'world.board_legs(uuid,jsonb)',
                    'world.trip_leg(jsonb,numeric,numeric,boolean,numeric)']) f(fn)
 order by f.fn;
commit;
