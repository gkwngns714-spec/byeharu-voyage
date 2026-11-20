-- PROD CHECK (read only) after 0459: its 3 new functions and the new world.trip_leg are there, stable, server only; world.trip_leg answers
-- sail_days; the three walks name world.board_trips; its receipt is recorded. Calls no function per row and nothing volatile.
begin transaction read only;
select (select count(*) from unnest(array['public.stow_takes(jsonb,numeric,numeric)', 'world.trip_stow(jsonb,numeric,numeric)', 'world.board_trips(uuid,jsonb,jsonb)',
                                          'world.trip_leg(jsonb,jsonb,numeric,boolean,numeric)']) n
          join pg_proc p on p.oid = to_regprocedure(n)
         where p.provolatile = 's' and p.prosecdef and not has_function_privilege('authenticated', p.oid, 'execute')) as new_stable_server_only,   -- want 4
       (select 'sail_days' = any (p.proargnames) from pg_proc p where p.oid = to_regprocedure('world.trip_leg(jsonb,jsonb,numeric,boolean,numeric)')) as leg_has_sail_days,   -- want true
       (select p.prosrc like '%world.board_trips(p_fleet, p_ctx, v_legs)%' from pg_proc p where p.oid = to_regprocedure('world.board_legs(uuid,jsonb)'))
         and (select p.prosrc like '%public.stow_takes(%' from pg_proc p where p.oid = to_regprocedure('public.fleet_load(uuid,text,numeric,numeric)')) as recut_in_place,   -- want true
       (select max(version) from supabase_migrations.schema_migrations) as head;                                                                  -- want 20260818000459
commit;
