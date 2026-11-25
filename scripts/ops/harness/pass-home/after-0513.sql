-- 0513 PROD CHECK, after the deploy; read-only, ONE statement (four STABLE reads, no player named). Wanted: lit as before; five 's'; sixth 0.
select (select value from public.world_config where key = 'sea_conditions_bite') as lit,
       (select string_agg(p.provolatile::text, '' order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname in ('sea_home', 'sea_lies', 'sea_passes', 'sea_beyond', 'sea_passes_lit')) as kinds,
       (select count(*) from public.sea_passes(null, null)) as nobody;
