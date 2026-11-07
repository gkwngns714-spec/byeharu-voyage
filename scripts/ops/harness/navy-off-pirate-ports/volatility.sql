-- 0342 PROD CHECK (volatility), read-only, ONE statement: the provolatile of every function before.sql and after.sql call (wanted: every value s or i; navy_harbour_ok null before the deploy and s after; navy_patrol_drop null before and v after, and it is NEVER called by the checks).
begin transaction read only;
select jsonb_object_agg(f.fn, (select p.provolatile from pg_proc p where p.oid = to_regprocedure(f.fn)))
  from (values ('pg_catalog.pg_get_functiondef(oid)'), ('pg_catalog.to_regprocedure(text)'), ('pg_catalog.md5(text)'), ('pg_catalog.replace(text, text, text)'), ('pg_catalog.has_function_privilege(text, oid, text)'),
               ('public.port_nation(uuid)'), ('public.pirate_power(uuid)'), ('public.realm_capital(uuid)'), ('public.harbour_nearest(double precision, double precision)'),
               ('public.navy_hunt_targets(uuid, timestamp with time zone)'), ('voyage.sea_danger(uuid, timestamp with time zone)'), ('voyage.gc_distance_nm(double precision, double precision, double precision, double precision)'),
               ('public.navy_harbour_ok(uuid)'),
               ('public.navy_patrol_drop(bigint)')) f(fn);
commit;
