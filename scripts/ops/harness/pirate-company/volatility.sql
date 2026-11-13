-- 0380 / 0381 PROD CHECK (run FIRST, either side of either deploy), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/pirate-company/volatility.sql
-- Wanted: every value 's' or 'i'. These are the functions the other check files here call; one that reads 'v' must not be selected on prod.
begin transaction read only;
select jsonb_object_agg(f.name, (select p.provolatile from pg_proc p where p.oid = to_regprocedure(f.name))) as volatility
  from unnest(array['world.snapshot()', 'public.treasury_balance(uuid)', 'public.pirate_power(uuid)', 'public.nation_joinable(uuid)', 'public.port_nation(uuid)',
                    'public.economy_closed()', 'public.city_treasury_on()', 'public.port_is_free(uuid)']) f(name);
commit;
