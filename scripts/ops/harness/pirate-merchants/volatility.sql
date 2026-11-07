-- 0341 PROD CHECK (volatility), read-only, ONE statement: the provolatile of every function before.sql and after.sql call (wanted: every value s or i; the six new ones null before the deploy and s s s s v v after; pirate_found and tick_pirate_merchants are VOLATILE and are NEVER called by the checks).
begin transaction read only;
select jsonb_object_agg(f.fn, (select p.provolatile from pg_proc p where p.oid = to_regprocedure(f.fn)))
  from (values ('pg_catalog.pg_get_functiondef(oid)'), ('pg_catalog.to_regprocedure(text)'), ('pg_catalog.pg_get_constraintdef(oid)'), ('pg_catalog.md5(text)'),
               ('public.treasury_balance(uuid)'), ('public.npc_known_legs(uuid)'), ('public.client_rpc_entry_points()'), ('world.daily_cap_remaining(uuid, uuid, uuid)'), ('public.daily_cap_base(uuid, uuid)'),
               ('public.pirate_home(uuid)'),
               ('public.pirate_merchant(uuid)'),
               ('public.npc_legs_open(jsonb, uuid)'),
               ('public.pirate_merchant_spec(integer)'),
               ('public.pirate_found(timestamp with time zone)'),
               ('public.tick_pirate_merchants(timestamp with time zone)')) f(fn);
commit;
