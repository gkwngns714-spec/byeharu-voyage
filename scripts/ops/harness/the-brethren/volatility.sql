-- 0338 PROD CHECK (volatility), read-only, ONE statement: run it BEFORE before.sql and after.sql. Prints provolatile of every function they call; wanted: all 's' or 'i' (the three new readers are null before the deploy, 's' after).
begin transaction read only;
select jsonb_object_agg(f.fn, (select p.provolatile::text from pg_proc p where p.oid = to_regprocedure(f.fn))) as provolatile
  from (values ('pg_get_functiondef(oid)'), ('to_regprocedure(text)'), ('replace(text,text,text)'), ('md5(text)'), ('public.treasury_balance(uuid)'), ('public.city_capital(uuid)'),
               ('public.convoy_ships_wanted()'), ('world.tax_rate(uuid,uuid)'), ('public.pirate_power(uuid)'), ('public.port_is_free(uuid)'), ('public.nation_joinable(uuid)')) f(fn);
commit;
