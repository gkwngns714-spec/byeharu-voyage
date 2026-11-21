-- PROD CHECK (read only) after 0462: world.board_origin(uuid) is the re-cut body (md5 of its live definition, CR stripped; local cached world,
-- 2026-11-20: 81084646af5fbe66daf1028ed34544c1), reads the roadstead, is stable, definer and still server only; the receipt is recorded. Nothing volatile.
begin transaction read only;
select md5(replace(pg_get_functiondef(to_regprocedure('world.board_origin(uuid)')), E'\r', '')) as md5,                                  -- want 81084646af5fbe66daf1028ed34544c1
       (select p.prosrc like '%sr.roadstead_lat%' and p.prosrc not like '%voyage.gc_distance_nm(f.lat, f.lon, p.lat, p.lon)%' from pg_proc p where p.oid = to_regprocedure('world.board_origin(uuid)')) as roadstead_select,   -- want true
       (select p.provolatile = 's' and p.prosecdef and not has_function_privilege('authenticated', p.oid, 'execute') from pg_proc p where p.oid = to_regprocedure('world.board_origin(uuid)')) as stable_server_only,   -- want true
       (select max(version) from supabase_migrations.schema_migrations) as head;                                                         -- want 20260818000462
commit;
