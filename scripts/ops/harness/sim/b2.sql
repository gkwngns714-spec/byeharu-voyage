begin transaction read only;
select json_object_agg(fn, replace(pg_get_functiondef(fn::regprocedure), E'\r', '')) j from (
 select p.oid::regprocedure::text fn from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where (n.nspname,p.proname) in (('cmd','do_make'),('world','workstation'),('public','promotion_credit'),('world','building_yard'),('cmd','do_build'),('public','item_recipe_value'),('public','mount_fitting'))) v;
rollback;
