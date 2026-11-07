-- 0340 PROD CHECK AFTER DEPLOY, read-only, one statement: supabase db query --linked -f scripts/ops/harness/the-navy-hunts/after.sql
-- Every function read here is STABLE (public.navy_on, public.pirates_on, public.navy_hunts_on, public.navy_hunt_targets, public.fleet_sea). No game function is called.
-- Wanted: navy_on false; pirates_on false; hunts_on false; keys 3; columns 4; fns 7 (every new function present) and client_callable 0; navy_ships 0; hunt_rows 0; fought 0; public_fights 0;
--         lisbon_targets > 1 (the seas in reach of Lisbon, the most dangerous first) with lisbon_own true; head 20260818000340.
begin transaction read only;
select public.navy_on() as navy_on,
       public.pirates_on() as pirates_on,
       public.navy_hunts_on() as hunts_on,
       (select count(*) from public.world_config c where c.key in ('navy_hunt_hours', 'navy_hunts_per_run', 'regard_pirate_beaten')) as keys,
       (select jsonb_object_agg(c.key, c.value) from public.world_config c where c.key in ('navy_hunt_hours', 'navy_hunts_per_run', 'regard_pirate_beaten')) as knobs,
       (select count(*) from pg_attribute a where a.attrelid = 'public.navy_ships'::regclass and a.attname in ('fought_at', 'fought', 'hunt_port', 'hunt_until') and not a.attisdropped) as columns,
       (select count(*) from unnest(array['public.navy_hunts_on()', 'public.fleet_sea(uuid,timestamp with time zone)', 'public.navy_hunt_targets(uuid,timestamp with time zone)',
                                          'public.navy_hunt_step(uuid,uuid,uuid,boolean,timestamp with time zone)', 'public.fight_hulls_write(jsonb)', 'public.navy_fight(uuid,uuid,timestamp with time zone)',
                                          'public.navy_hunt_pass(timestamp with time zone,uuid)']) f where to_regprocedure(f) is not null) as fns,
       (select count(*) from unnest(array['public.navy_hunts_on()', 'public.fleet_sea(uuid,timestamp with time zone)', 'public.navy_hunt_targets(uuid,timestamp with time zone)',
                                          'public.navy_hunt_step(uuid,uuid,uuid,boolean,timestamp with time zone)', 'public.fight_hulls_write(jsonb)', 'public.navy_fight(uuid,uuid,timestamp with time zone)',
                                          'public.navy_hunt_pass(timestamp with time zone,uuid)']) f
         where to_regprocedure(f) is not null and (has_function_privilege('anon', f::regprocedure, 'execute') or has_function_privilege('authenticated', f::regprocedure, 'execute'))) as client_callable,
       (select count(*) from public.navy_ships) as navy_ships,
       (select count(*) from public.navy_ships n where n.mission = 'HUNT' or n.hunt_port is not null) as hunt_rows,
       (select count(*) from public.navy_ships n where n.fought_at is not null or n.fought is not null) as fought,
       (select count(*) from public.events e where e.player_id is null and e.kind = 'NAVY_FIGHT') as public_fights,
       (select count(*) from public.navy_hunt_targets((select p.id from public.ports p where p.code = 'LIS'), now())) as lisbon_targets,
       (select t.nm = 0 and t.port_id = (select p.id from public.ports p where p.code = 'LIS') from public.navy_hunt_targets((select p.id from public.ports p where p.code = 'LIS'), now()) t
         where t.sea_id = (select p.sea_id from public.ports p where p.code = 'LIS')) as lisbon_own,
       (select max(version) from supabase_migrations.schema_migrations) as head;
commit;
