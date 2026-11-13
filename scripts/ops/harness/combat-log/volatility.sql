-- 0353 PROD CHECK (volatility), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/combat-log/volatility.sql
-- Run it BEFORE the other files here. Prints provolatile of every function they call; wanted: all 's' or 'i' (the readers 0353 makes are null before the deploy, 's' after).
begin transaction read only;
select jsonb_object_agg(f.fn, (select p.provolatile::text from pg_proc p where p.oid = to_regprocedure(f.fn))) as provolatile
  from (values ('pg_get_functiondef(oid)'), ('to_regprocedure(text)'), ('to_regclass(text)'), ('replace(text,text,text)'), ('md5(text)'),
               ('has_function_privilege(name,oid,text)'), ('has_table_privilege(name,oid,text)'),
               ('public.client_rpc_entry_points()'), ('public.raid_orders_on()'), ('public.pirate_capital()'), ('public.pirate_hoard()'),
               ('public.city_treasury_on()'), ('public.wc_num(text)'), ('public.wc(text)'),
               ('voyage.fight_resolve(uuid,integer,numeric,numeric,jsonb)')) f(fn);
commit;
