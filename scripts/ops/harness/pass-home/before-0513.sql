-- 0513 PROD CHECK, before the deploy; read-only, ONE statement. Wanted: there 0; 0510 in (title_was true); matrix_harbours = harbours; lit false.
select (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('sea_home', 'sea_lies', 'sea_passes', 'sea_beyond', 'sea_passes_lit')) as there,
       exists (select 1 from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'sea_zones' and c.column_name = 'title_was') as title_was,
       (select cardinality(ids) from public.sea_reach_matrix where id = 1) as matrix_harbours,
       (select count(*) from public.ports where kind = 'HARBOUR') as harbours,
       (select value from public.world_config where key = 'sea_conditions_bite') as lit,
       (select value from public.world_config where key = 'nav_leg_nm_base') as leg_base;
