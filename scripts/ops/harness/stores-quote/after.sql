-- PROD CHECK (read only) after 0454: its 5 new functions are there, stable, server only; 0361's world.trip_leg is gone; its receipt is recorded.
begin transaction read only;
select (select count(*) from unnest(array['voyage.ship_speed_parts(uuid)', 'voyage.ship_speed_of(jsonb,numeric)', 'voyage.fleet_speed_parts(uuid,boolean)',
                                          'voyage.fleet_speed_of(jsonb,numeric,jsonb)', 'world.trip_leg(jsonb,jsonb,numeric,boolean,numeric)']) n
          join pg_proc p on p.oid = to_regprocedure(n)
         where p.provolatile = 's' and p.prosecdef and not has_function_privilege('authenticated', p.oid, 'execute')) as new_stable_server_only,   -- want 5
       to_regprocedure('world.trip_leg(jsonb,numeric,numeric,boolean,numeric)') is null as old_walk_gone,                                         -- want true
       (select max(version) from supabase_migrations.schema_migrations) as head;                                                                  -- want 20260818000454
commit;
