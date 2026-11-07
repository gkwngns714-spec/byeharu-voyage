-- 0343 PROD CHECK (volatility), read-only, ONE statement: run it BEFORE before.sql and after.sql. Prints provolatile of every function they call; wanted: all 's' or 'i' (the new readers are null before the deploy, 's' after).
begin transaction read only;
select jsonb_object_agg(f.fn, (select p.provolatile::text from pg_proc p where p.oid = to_regprocedure(f.fn))) as provolatile
  from (values ('pg_get_functiondef(oid)'), ('to_regprocedure(text)'), ('replace(text,text,text)'), ('md5(text)'), ('has_function_privilege(name,text,text)'),
               ('public.treasury_balance(uuid)'), ('public.city_capital(uuid)'), ('public.city_aid_target(uuid)'), ('public.wc_num(text)'),
               ('public.city_reserve_on()'), ('public.city_default_reserve(uuid)'), ('public.city_floor(uuid)')) f(fn);
commit;
