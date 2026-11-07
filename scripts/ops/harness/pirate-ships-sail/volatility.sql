-- 0339 PROD CHECK (volatility), read-only, ONE statement: run it BEFORE before.sql and after.sql. Prints provolatile of every function they call; wanted: all 's' or 'i' (the new readers are null before the deploy, 's' after).
begin transaction read only;
select jsonb_object_agg(f.fn, (select p.provolatile::text from pg_proc p where p.oid = to_regprocedure(f.fn))) as provolatile
  from (values ('pg_get_functiondef(oid)'), ('to_regprocedure(text)'), ('replace(text,text,text)'), ('md5(text)'), ('public.treasury_balance(uuid)'), ('public.realm_purse(uuid)'), ('public.port_is_free(uuid)'),
               ('public.pirates_on()'), ('public.pirate_hoard()'), ('public.pirate_size()'), ('public.pirate_spend_room(timestamptz)'), ('public.pirate_capital()'), ('public.pirate_home_of(integer)'),
               ('public.pirate_ship_in_sea(uuid)'), ('voyage.freeze_raiders(jsonb,uuid)'), ('public.client_rpc_entry_points()')) f(fn);
commit;
