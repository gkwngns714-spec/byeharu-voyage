-- 0398 PROD CHECK (after the DEPLOY of 0398; it lights nothing), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/sea-light/after.sql
-- Wanted: both functions present; ready_volatility 's', light_volatility 'v'; client_can_call false; switch as it was before the deploy (false);
-- news_row 0 (the row is posted by the step, not by the deploy).
begin transaction read only;
select (select max(version) from supabase_migrations.schema_migrations) as head,
       to_regprocedure('public.sea_conditions_ready()') is not null and to_regprocedure('public.sea_conditions_light()') is not null as both_functions,
       (select p.provolatile from pg_proc p where p.oid = to_regprocedure('public.sea_conditions_ready()')) as ready_volatility,
       (select p.provolatile from pg_proc p where p.oid = to_regprocedure('public.sea_conditions_light()')) as light_volatility,
       has_function_privilege('authenticated', 'public.sea_conditions_light()', 'execute') or has_function_privilege('anon', 'public.sea_conditions_light()', 'execute')
         or has_function_privilege('authenticated', 'public.sea_conditions_ready()', 'execute') or has_function_privilege('anon', 'public.sea_conditions_ready()', 'execute') as client_can_call,
       (select value from public.world_config where key = 'sea_conditions_bite') as switch,
       (select count(*) from public.world_news n where n.key = 'update:0398') as news_row;
commit;
