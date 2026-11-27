-- 0510 PROD CHECK, before the deploy; read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/seas-by-continent/before-0510.sql
-- Wanted: lit false; seas 64; table_md5 and the three body md5s equal to the chain image's at 0509 (the file refuses otherwise); title_was_there false.
begin transaction read only;
select (select value from public.world_config where key = 'sea_conditions_bite') as lit,
       (select value from public.world_config where key = 'sea_conditions_bite_npc') as lit_merchants,
       (select count(*) from public.sea_zones) as seas,
       (select md5(string_agg(z.code || z.title_min || ':' || z.wave_min, ',' order by z.code)) from public.sea_zones z) as table_md5,
       exists (select 1 from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'sea_zones' and c.column_name = 'title_was') as title_was_there,
       (select count(*) from public.sea_leg_asks) as pair_rows,
       (select md5(prosrc) from pg_proc where oid = 'public.sea_judge(integer,numeric,text[],integer,integer,integer,integer)'::regprocedure) as judge,
       (select md5(prosrc) from pg_proc where oid = 'voyage.reach_passage(uuid,uuid,uuid,numeric)'::regprocedure) as reach_passage,
       (select md5(prosrc) from pg_proc where oid = 'world.sea_conditions()'::regprocedure) as conditions;
rollback;
