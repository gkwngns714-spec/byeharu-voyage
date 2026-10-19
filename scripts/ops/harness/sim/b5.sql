begin transaction read only;
select json_agg(n.nspname||'.'||p.proname) j from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','cmd','voyage','world') and p.prosrc ~ 'item_recipe_value';
rollback;
