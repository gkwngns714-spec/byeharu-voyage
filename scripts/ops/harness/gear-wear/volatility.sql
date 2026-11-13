-- gear_wear_bite PROD CHECK (volatility), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/gear-wear/volatility.sql
-- Run it BEFORE before-light.sql and after-light.sql. Prints provolatile of every function they call; wanted: all 's' or 'i'.
begin transaction read only;
select jsonb_object_agg(f.fn, (select p.provolatile::text from pg_proc p where p.oid = to_regprocedure(f.fn))) as provolatile
  from (values ('pg_get_functiondef(oid)'), ('to_regprocedure(text)'), ('replace(text,text,text)'), ('strpos(text,text)'), ('length(text)'),
               ('public.gear_wear_on()'), ('public.unit_repair_cost(text,numeric)'), ('public.wear_factor(numeric)'), ('public.item_recipe_value(text)'),
               ('public.wc_num(text)')) f(fn);
commit;
