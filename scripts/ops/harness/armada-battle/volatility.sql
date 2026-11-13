-- 0379 PROD CHECK (volatility), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/armada-battle/volatility.sql
-- Run it BEFORE before.sql and after.sql. Prints provolatile of every function they call; wanted: all 's' or 'i'.
begin transaction read only;
select jsonb_object_agg(f.fn, (select p.provolatile::text from pg_proc p where p.oid = to_regprocedure(f.fn))) as provolatile
  from (values ('pg_get_functiondef(oid)'), ('pg_get_constraintdef(oid)'), ('to_regprocedure(text)'), ('to_regclass(text)'), ('replace(text,text,text)'), ('md5(text)'),
               ('has_function_privilege(name,oid,text)'), ('public.attack_on()')) f(fn);
commit;
