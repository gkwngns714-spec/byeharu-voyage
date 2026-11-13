-- 0391 PROD CHECK (either side), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/sea-wall/volatility.sql
-- The cut bodies, the two new functions (after the deploy) and what they compose: volatility, definer, settings and who may run it. Wanted: every row s or
-- i (cmd.refusal_caught i) except cmd.found_house (v, a command); world.sea_conditions, world.route_legs, world.sea_zone_map (after) and cmd.found_house open to authenticated and
-- not to anon; public.sea_refusal, public.sea_gate, public.far_powers (after), public.fleet_wave, public.title_level server only. The same rows before and
-- after but for the two new functions.
begin transaction read only;
select p.oid::regprocedure::text as fn, p.provolatile as volatile, p.prosecdef as definer, coalesce(p.proconfig::text, '') as settings,
       has_function_privilege('authenticated', p.oid, 'execute') as authenticated_may, has_function_privilege('anon', p.oid, 'execute') as anon_may
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where (n.nspname, p.proname) in (('public', 'sea_refusal'), ('cmd', 'found_house'), ('world', 'sea_conditions'), ('world', 'route_legs'), ('world', 'sea_zone_map'),
                                  ('public', 'far_powers'), ('public', 'sea_gate'), ('public', 'sea_conditions_on'), ('public', 'fleet_wave'), ('public', 'title_level'),
                                  ('public', 'nation_joinable'), ('public', 'client_rpc_entry_points'), ('cmd', 'refusal_caught'), ('cmd', 'refusal'))
 order by 1;
commit;
