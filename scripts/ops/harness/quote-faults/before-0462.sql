-- PROD CHECK (read only) before 0462: the one body 0462 re-cuts, world.board_origin(uuid), is the chain's at 0461 (md5 of its live definition, CR
-- stripped; local cached world, 2026-11-20: 5638b66f13597c47227b262b12d48e1e); every harbour has a roadstead row; its at-anchor select is still the quay one.
-- Calls no function per row and nothing volatile.
begin transaction read only;
select md5(replace(pg_get_functiondef(to_regprocedure('world.board_origin(uuid)')), E'\r', '')) as md5,                                  -- want 5638b66f13597c47227b262b12d48e1e
       (select count(*) from public.ports p where p.kind = 'HARBOUR' and not exists (select 1 from public.sea_reaches sr where sr.port_id = p.id)) as harbours_without_roadstead,   -- want 0
       (select p.prosrc like '%voyage.gc_distance_nm(f.lat, f.lon, p.lat, p.lon)%' from pg_proc p where p.oid = to_regprocedure('world.board_origin(uuid)')) as quay_select,   -- want true
       (select max(version) from supabase_migrations.schema_migrations) as head;                                                         -- want 20260818000461
commit;
