-- 0525 PROD CHECK, before the deploy; read-only, ONE statement. Wanted: there 0; relit_in true; classes = profiles; rule as the chain's at 0514 (the file compares its answers itself).
begin transaction read only;
select (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('sea_stats_derive', 'ship_sea_stat', 'fleet_sea_stats', 'sea_more')) as there,
       to_regprocedure('public.seas_relit_ready()') is not null as relit_in,
       (select count(*) from public.ship_classes) as classes, (select count(*) from public.class_profile) as profiles, (select count(*) from public.item_profile) as items,
       (select md5(prosrc) from pg_proc where oid = to_regprocedure('public.sea_refusal(integer,numeric,text[])')) as rule,
       (select value from public.world_config where key = 'sea_conditions_bite') as lit;
rollback;
