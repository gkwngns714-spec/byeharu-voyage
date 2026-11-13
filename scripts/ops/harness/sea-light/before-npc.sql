-- 0399 PROD CHECK (before lighting sea_conditions_bite_npc), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/sea-light/before-npc.sql
-- HEAD IT MEETS: 20260818000398 (0399 deploys after 0398, the players' step).
-- Run AFTER 0399 is deployed. THE GUARDS OF THE MERCHANTS' STEP, as it will judge them. Wanted before the light: guards.ready true. That is: lit false,
-- players_lit true (the players' window is closed and clean), merchants_with_no_open_leg 0. loops_closed is how many merchants the planner will move, each at
-- her next lap start; closed_at_sea of them are at sea now and finish their trip. Wanted too: ready_volatility 's', light_volatility 'v', client_can_call false,
-- news_row 0. Then take scripts/ops/harness/sea-merchants/after-lit.sql once as the baseline of the window.
-- Not ready: do NOT light; the step would refuse anyway, naming the same figures.
begin transaction read only;
select now() as read_at,
       (select max(version) from supabase_migrations.schema_migrations) as head,
       public.sea_conditions_npc_ready() as guards,
       (select p.provolatile from pg_proc p where p.oid = to_regprocedure('public.sea_conditions_npc_ready()')) as ready_volatility,
       (select p.provolatile from pg_proc p where p.oid = to_regprocedure('public.sea_conditions_npc_light()')) as light_volatility,
       has_function_privilege('authenticated', 'public.sea_conditions_npc_light()', 'execute') or has_function_privilege('anon', 'public.sea_conditions_npc_light()', 'execute') as client_can_call,
       (select count(*) from public.world_news n where n.key = 'update:0399') as news_row;
commit;
