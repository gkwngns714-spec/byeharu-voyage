-- PROD CHECK (read only) before 0459: the 9 bodies 0459 re-cuts or replaces are the chain's at 0458 (md5 of each live definition, CR stripped),
-- its 3 new names are free, and what its probe needs is there. Compare each md5 with the line in docs/dev-log/2026-11-19-quote-faults.md (PROD CHECKS).
begin transaction read only;
select f.fn, md5(replace(pg_get_functiondef(to_regprocedure(f.fn)), E'\r', '')) as md5,
       (select bool_and(to_regprocedure(n) is null) from unnest(array['public.stow_takes(jsonb,numeric,numeric)', 'world.trip_stow(jsonb,numeric,numeric)',
                                                                  'world.board_trips(uuid,jsonb,jsonb)']) n) as new_names_free,
       (select count(*) from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR') = 1
         and (select count(*) from public.ship_classes c where c.code in ('barca', 'caravelao')) = 2
         and (select count(*) from public.nations n where n.code = 'PRT') = 1 as probe_needs_there
  from unnest(array['voyage.fleet_speed_of(jsonb,numeric,jsonb)', 'world.trip_hulls(uuid)', 'world.trip_leg(jsonb,jsonb,numeric,boolean,numeric)',
                    'world.trip_cost(uuid,jsonb)', 'world.board_legs(uuid,jsonb)', 'world.board_sell(uuid,uuid,jsonb)',
                    'world.good_board(uuid,uuid,uuid,numeric)', 'world.best_sales(uuid,uuid)', 'public.fleet_load(uuid,text,numeric,numeric)']) f(fn)
 order by f.fn;
commit;
